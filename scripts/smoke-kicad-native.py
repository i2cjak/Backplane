#!/usr/bin/env python3
"""Exercise the bundled KiCad native IPC server with bounded cleanup.

The protocol bindings are generated from the supplied KiCad checkout, so this
smoke test cannot accidentally pass with a mismatched client schema. It opens
one disposable PCB and schematic and verifies the corresponding document lists.
Requires protobuf==5.29.6, pynng==0.9.0, and grpcio-tools==1.71.0 in the
interpreter used to run it.
"""

from __future__ import annotations

import argparse
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time
import uuid


TIMEOUT_SECONDS = 30


def generate_bindings(source: Path, output: Path) -> None:
    proto_root = source / "api" / "proto"
    files = sorted(proto_root.rglob("*.proto"))
    if not files:
        raise RuntimeError(f"KiCad protocol sources are missing below {proto_root}")
    subprocess.run(
        [sys.executable, "-m", "grpc_tools.protoc", f"-I{proto_root}", f"--python_out={output}", *map(str, files)],
        check=True,
        timeout=TIMEOUT_SECONDS,
    )


def request(connection, envelope, command, response_type, token: str):
    from google.protobuf.message import Message

    message = envelope.ApiRequest()
    message.header.client_name = "backplane.native-kicad-smoke"
    message.header.kicad_token = token
    message.message.Pack(command)
    connection.send(message.SerializeToString())
    response = envelope.ApiResponse.FromString(connection.recv())
    if response.status.status != envelope.AS_OK:
        raise RuntimeError(f"{command.DESCRIPTOR.full_name}: {response.status}")
    result = response_type()
    if not isinstance(result, Message) or not response.message.Unpack(result):
        raise RuntimeError(f"Unexpected reply to {command.DESCRIPTOR.full_name}")
    return result, response.header.kicad_token


def wait_for_ipc(endpoint: str, environment: dict[str, str], imports: tuple) -> None:
    import pynng
    from google.protobuf.empty_pb2 import Empty

    envelope, base, project, editor, types = imports
    deadline = time.monotonic() + TIMEOUT_SECONDS
    last_error: BaseException | None = None
    connection = None
    token = ""
    while time.monotonic() < deadline:
        try:
            connection = pynng.Req0(dial=endpoint, block_on_dial=False, send_timeout=1000, recv_timeout=1000)
            _, token = request(connection, envelope, base.Ping(), Empty, token)
            version, token = request(connection, envelope, base.GetVersion(), base.GetVersionResponse, token)
            connection.send_timeout = 15000
            connection.recv_timeout = 15000
            print(f"KiCad API server ready: {version.version}", flush=True)
            break
        except Exception as error:  # pynng reports transport startup races as several exception types.
            last_error = error
            if connection is not None:
                connection.close()
                connection = None
            time.sleep(0.1)
    if connection is None:
        raise RuntimeError(f"KiCad API server did not answer within {TIMEOUT_SECONDS}s: {last_error}")
    with connection:
        for kind, suffix in ((types.DOCTYPE_PCB, "kicad_pcb"), (types.DOCTYPE_SCHEMATIC, "kicad_sch")):
            path = environment["BACKPLANE_SMOKE_PROJECT"] + f"/test_project.{suffix}"
            opened, token = request(connection, envelope, project.OpenDocument(type=kind, path=path), project.OpenDocumentResponse, token)
            listed, token = request(connection, envelope, editor.GetOpenDocuments(type=kind), editor.GetOpenDocumentsResponse, token)
            if not opened.document or len(listed.documents) < 1:
                raise RuntimeError(f"KiCad did not report the opened {suffix} document")
            print(f"{suffix}: OpenDocument/GetOpenDocuments passed", flush=True)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path, help="KiCad source checkout containing api/proto and QA fixtures")
    parser.add_argument("executable", type=Path, help="bundled kicad-cli executable")
    args = parser.parse_args()
    source = args.source.resolve(strict=True)
    cli = args.executable.resolve(strict=True)
    for required in (source / "api" / "proto", source / "qa" / "data" / "libraries" / "test_project"):
        if not required.exists():
            raise RuntimeError(f"KiCad smoke source is incomplete: {required}")
    with tempfile.TemporaryDirectory(prefix="backplane-kicad-native-") as temporary:
        root = Path(temporary)
        bindings = root / "bindings"
        bindings.mkdir()
        generate_bindings(source, bindings)
        sys.path.insert(0, str(bindings))
        from common import envelope_pb2 as envelope
        from common.commands import base_commands_pb2 as base
        from common.commands import editor_commands_pb2 as editor
        from common.commands import project_commands_pb2 as project
        from common.types import base_types_pb2 as types

        design = root / "project"
        shutil.copytree(source / "qa" / "data" / "libraries" / "test_project", design)
        socket_path: Path | None = None
        if os.name == "nt":
            endpoint = f"ipc://backplane-kicad-smoke-{os.getpid()}-{uuid.uuid4().hex}"
        else:
            socket_path = Path("/tmp") / f"backplane-kicad-{uuid.uuid4().hex}.sock"
            endpoint = f"ipc://{socket_path}"
        environment = dict(os.environ)
        environment.update({
            "HOME": str(root / "home"),
            "XDG_DATA_HOME": str(root / "data"),
            "XDG_CACHE_HOME": str(root / "cache"),
            "XDG_CONFIG_HOME": str(root / "config"),
            "KICAD_CONFIG_HOME": str(root / "config" / "kicad"),
            "BACKPLANE_SMOKE_PROJECT": str(design),
        })
        for directory in ("home", "data", "cache", "config"):
            (root / directory).mkdir(parents=True)
        environment.pop("DISPLAY", None)
        environment.pop("WAYLAND_DISPLAY", None)
        log_path = root / "api-server.log"
        with log_path.open("w", encoding="utf-8") as log:
            process = subprocess.Popen([str(cli), "api-server", "--socket", endpoint.removeprefix("ipc://")], env=environment, stdout=log, stderr=subprocess.STDOUT)
            try:
                wait_for_ipc(endpoint, environment, (envelope, base, project, editor, types))
            except Exception:
                log.flush()
                print(log_path.read_text(errors="replace"), file=sys.stderr)
                raise
            finally:
                if process.poll() is None:
                    process.terminate()
                    try:
                        process.wait(timeout=5)
                    except subprocess.TimeoutExpired:
                        process.kill()
                        process.wait(timeout=5)
                if socket_path is not None:
                    socket_path.unlink(missing_ok=True)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, RuntimeError, subprocess.SubprocessError) as error:
        print(str(error), file=sys.stderr)
        raise SystemExit(1)
