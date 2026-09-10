#!/usr/bin/env python3
"""Discover KiCad viewer inputs and optionally update project selection."""
import argparse
import json
import os
from pathlib import Path
import re


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("workspace", type=Path)
    parser.add_argument("--pcb")
    parser.add_argument("--schematic")
    parser.add_argument("--gerbers", action="append")
    parser.add_argument("--enclosure-params")
    parser.add_argument("--enclosure-solid", action="append", metavar="NAME=PATH")
    parser.add_argument("--product-scene")
    parser.add_argument("--product-still")
    parser.add_argument("--product-load-viz")
    parser.add_argument("--driver", action="append", metavar="DOMAIN=MCP_NAME")
    parser.add_argument("--driver-reference", action="append", metavar="DOMAIN=URL")
    parser.add_argument("--driver-mutation", action="append", metavar="DOMAIN=LABEL")
    parser.add_argument("--write", action="store_true")
    args = parser.parse_args()
    root = args.workspace.resolve(strict=True)
    if not root.is_dir():
        parser.error("workspace must be a directory")
    config_path = root / ".backplane.json"
    if config_path.is_symlink():
        parser.error(".backplane.json must not be a symlink")
    try:
        config = json.loads(config_path.read_text()) if config_path.exists() else {}
        if not isinstance(config, dict):
            raise ValueError(".backplane.json must contain an object")
    except (ValueError, OSError) as error:
        parser.error(str(error))
    found = {"pcb": [], "schematic": [], "gerbers": set(), "solids": [], "stills": [], "json": []}
    for directory, dirs, files in os.walk(root, followlinks=False):
        dirs[:] = sorted(d for d in dirs if d not in {".git", ".history", "node_modules", ".venv"} and not (Path(directory) / d).is_symlink())
        for name in sorted(files):
            path = Path(directory) / name
            if path.is_symlink():
                continue
            rel = path.relative_to(root).as_posix()
            suffix = path.suffix.lower()
            if suffix == ".kicad_pcb":
                found["pcb"].append(rel)
            elif suffix == ".kicad_sch":
                found["schematic"].append(rel)
            elif suffix in {".gbr", ".ger", ".gtl", ".gbl", ".gto", ".gbo", ".gts", ".gbs", ".gta", ".gba", ".gtp", ".gbp", ".gm1", ".gko", ".drl", ".xln"} or re.fullmatch(r"\.g\d+", suffix):
                found["gerbers"].add(path.parent.relative_to(root).as_posix())
            elif suffix in {".stl", ".step", ".stp", ".glb", ".gltf", ".obj"}:
                found["solids"].append(rel)
            elif suffix in {".png", ".jpg", ".jpeg", ".webp"}:
                found["stills"].append(rel)
            elif suffix == ".json":
                found["json"].append(rel)
    found["gerbers"] = sorted(found["gerbers"])
    for key in ("pcb", "schematic", "gerbers"):
        value = getattr(args, key)
        if value is None:
            continue
        values = value if isinstance(value, list) else [value]
        normalized = []
        for item in values:
            path = root / item
            try:
                relative = path.resolve(strict=True).relative_to(root)
            except (ValueError, OSError):
                parser.error(f"{key} must exist inside the workspace: {item}")
            if any(p.is_symlink() for p in [path, *path.parents] if p != root):
                parser.error(f"symlinks are not viewer inputs: {item}")
            if ".history" in relative.parts:
                parser.error(f"history files are not viewer inputs: {item}")
            if key == "gerbers" and not path.is_dir():
                parser.error(f"Gerber path must be a directory: {item}")
            if key != "gerbers" and relative.as_posix() not in found[key]:
                parser.error(f"not a {key} file: {item}")
            normalized.append(relative.as_posix())
        config[key] = normalized if key == "gerbers" else normalized[0]

    def relative_inside(item, key):
        path = root / item
        try:
            relative = path.resolve(strict=True).relative_to(root)
        except (ValueError, OSError):
            parser.error(f"{key} must exist inside the workspace: {item}")
        if any(p.is_symlink() for p in [path, *path.parents] if p != root):
            parser.error(f"symlinks are not viewer inputs: {item}")
        if ".history" in relative.parts:
            parser.error(f"history files are not viewer inputs: {item}")
        return relative.as_posix()

    if args.enclosure_params or args.enclosure_solid:
        enclosure = dict(config.get("enclosure") or {})
        if not isinstance(enclosure, dict):
            enclosure = {}
        if args.enclosure_params:
            enclosure["params"] = relative_inside(args.enclosure_params, "enclosure-params")
        if args.enclosure_solid:
            solids = dict(enclosure.get("solids") or {})
            if not isinstance(solids, dict):
                solids = {}
            for item in args.enclosure_solid:
                if "=" not in item:
                    parser.error("enclosure-solid must be NAME=PATH")
                name, path = item.split("=", 1)
                solids[name] = relative_inside(path, "enclosure-solid")
            enclosure["solids"] = solids
        config["enclosure"] = enclosure
    if args.product_scene or args.product_still or args.product_load_viz:
        product = dict(config.get("product") or {})
        if not isinstance(product, dict):
            product = {}
        if args.product_scene:
            product["scene"] = relative_inside(args.product_scene, "product-scene")
        if args.product_still:
            product["still"] = relative_inside(args.product_still, "product-still")
        if args.product_load_viz:
            product["loadViz"] = relative_inside(args.product_load_viz, "product-load-viz")
        config["product"] = product
    if args.driver or args.driver_reference or args.driver_mutation:
        drivers = dict(config.get("drivers") or {})
        if not isinstance(drivers, dict):
            drivers = {}

        def split_domain(item, key):
            if "=" not in item:
                parser.error(f"{key} must be DOMAIN=VALUE")
            domain, value = item.split("=", 1)
            domain = domain.strip()
            value = value.strip()
            if not domain or not value:
                parser.error(f"{key} must be DOMAIN=VALUE")
            return domain, value

        for item in args.driver or []:
            domain, mcp = split_domain(item, "driver")
            entry = dict(drivers.get(domain) or {})
            if not isinstance(entry, dict):
                entry = {}
            entry["mcp"] = mcp
            drivers[domain] = entry
        for item in args.driver_reference or []:
            domain, url = split_domain(item, "driver-reference")
            entry = dict(drivers.get(domain) or {})
            if not isinstance(entry, dict):
                entry = {}
            if "mcp" not in entry:
                parser.error(f"driver-reference {domain} needs --driver {domain}=MCP_NAME")
            entry["reference"] = url
            drivers[domain] = entry
        for item in args.driver_mutation or []:
            domain, label = split_domain(item, "driver-mutation")
            entry = dict(drivers.get(domain) or {})
            if not isinstance(entry, dict):
                entry = {}
            if "mcp" not in entry:
                parser.error(f"driver-mutation {domain} needs --driver {domain}=MCP_NAME")
            mutations = list(entry.get("mutations") or [])
            if label not in mutations:
                mutations.append(label)
            entry["mutations"] = mutations
            drivers[domain] = entry
        config["drivers"] = drivers
    write_keys = (
        "pcb",
        "schematic",
        "gerbers",
        "enclosure_params",
        "enclosure_solid",
        "product_scene",
        "product_still",
        "product_load_viz",
        "driver",
        "driver_reference",
        "driver_mutation",
    )
    if args.write:
        if not any(getattr(args, key) is not None for key in write_keys):
            parser.error("--write requires at least one explicit selection")
        temporary = root / ".backplane.json.tmp"
        with temporary.open("x") as output:
            json.dump(config, output, indent=2)
            output.write("\n")
        temporary.replace(config_path)
    print(json.dumps({"workspace": str(root), "config": config, "candidates": found, "written": args.write}, indent=2))


if __name__ == "__main__":
    main()
