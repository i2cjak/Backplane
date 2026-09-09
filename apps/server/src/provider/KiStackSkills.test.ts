// @effect-diagnostics nodeBuiltinImport:off
import * as NodeFSP from "node:fs/promises";
import * as NodeOS from "node:os";
import * as NodePath from "node:path";
import { expect, it } from "vite-plus/test";
import {
  buildKiStackInstructions,
  createKiStackSkills,
  installKiStackSkills,
} from "./KiStackSkills.ts";
import bundle from "./kistack.bundle.json" with { type: "json" };

it("installs all nine skills and supporting files offline, and repairs missing resources", async () => {
  const directory = await NodeFSP.mkdtemp(
    NodePath.join(NodeOS.tmpdir(), "backplane-kistack-test-"),
  );
  try {
    await installKiStackSkills(directory);
    expect(bundle.skills).toHaveLength(9);
    for (const [relative, contents] of Object.entries(bundle.files)) {
      expect(await NodeFSP.readFile(NodePath.join(directory, relative), "utf8")).toBe(contents);
    }
    const schematic = NodePath.join(directory, "skills/schematic/SKILL.md");
    const before = (await NodeFSP.stat(schematic)).mtimeMs;
    const helper = NodePath.join(directory, "skills/export/scripts/convert_position.py");
    await NodeFSP.unlink(helper);
    await installKiStackSkills(directory);
    expect((await NodeFSP.stat(schematic)).mtimeMs).toBe(before);
    expect(await NodeFSP.readFile(helper, "utf8")).toBe(
      bundle.files["skills/export/scripts/convert_position.py"],
    );
    const instructions = buildKiStackInstructions(directory);
    for (const skill of bundle.skills) {
      expect(instructions).toContain(JSON.stringify(NodePath.join(directory, skill.path)));
    }
    expect(instructions).toContain("User instructions take precedence");
  } finally {
    await NodeFSP.rm(directory, { recursive: true, force: true });
  }
});

it("reports installation errors instead of advertising unavailable skills", async () => {
  const directory = await NodeFSP.mkdtemp(
    NodePath.join(NodeOS.tmpdir(), "backplane-kistack-error-"),
  );
  try {
    const file = NodePath.join(directory, "not-a-directory");
    await NodeFSP.writeFile(file, "existing");
    await expect(installKiStackSkills(file)).rejects.toThrow();
    expect(await NodeFSP.readFile(file, "utf8")).toBe("existing");
  } finally {
    await NodeFSP.rm(directory, { recursive: true, force: true });
  }
});

const revision = "a".repeat(40);
const skill = "---\nname: kicad-test\ndescription: A test skill\n---\n\nUse it.\n";
const tree = [
  { path: "LICENSE", type: "blob", mode: "100644", size: 5 },
  { path: "skills/test/SKILL.md", type: "blob", mode: "100644", size: skill.length },
];

it("refreshes an immutable revision, coalesces concurrent checks, and restores it after restart", async () => {
  const root = await NodeFSP.mkdtemp(NodePath.join(NodeOS.tmpdir(), "backplane-kistack-refresh-"));
  let calls = 0;
  const fetchImpl = async (input: string): Promise<Response> => {
    calls += 1;
    if (input.endsWith("/commits/HEAD"))
      return new Response(JSON.stringify({ sha: revision }), { headers: { etag: '"test"' } });
    if (input.includes("/git/trees/")) return new Response(JSON.stringify({ tree }));
    if (input.endsWith("/LICENSE")) return new Response("test\n");
    return new Response(skill);
  };
  try {
    const instance = createKiStackSkills({ cacheDirectory: root, fetchImpl });
    const [first, second] = await Promise.all([instance.refresh(), instance.refresh()]);
    expect(first).toBe(true);
    expect(second).toBe(true);
    expect(calls).toBe(4);
    expect(instance.revision).toBe(revision);
    expect(
      await NodeFSP.readFile(NodePath.join(root, revision, "skills/test/SKILL.md"), "utf8"),
    ).toBe(skill);
    const restarted = createKiStackSkills({
      cacheDirectory: root,
      fetchImpl: async () => {
        throw new Error("network");
      },
    });
    await restarted.install();
    expect(restarted.revision).toBe(revision);
    expect(restarted.directory).toBe(NodePath.join(root, revision));
    await expect(restarted.refresh()).rejects.toThrow("network");
    expect(restarted.revision).toBe(revision);
  } finally {
    await NodeFSP.rm(root, { recursive: true, force: true });
  }
});

it("uses the ETag for an unchanged check", async () => {
  const root = await NodeFSP.mkdtemp(NodePath.join(NodeOS.tmpdir(), "backplane-kistack-etag-"));
  let calls = 0;
  const fetchImpl = async (input: string, init?: RequestInit): Promise<Response> => {
    calls += 1;
    if (input.endsWith("/commits/HEAD")) {
      if (calls === 1)
        return new Response(JSON.stringify({ sha: revision }), { headers: { etag: '"same"' } });
      expect(new Headers(init?.headers).get("if-none-match")).toBe('"same"');
      return new Response(null, { status: 304 });
    }
    if (input.includes("/git/trees/")) return new Response(JSON.stringify({ tree }));
    return new Response(input.endsWith("/LICENSE") ? "test\n" : skill);
  };
  try {
    const instance = createKiStackSkills({ cacheDirectory: root, fetchImpl });
    await instance.install();
    expect(await instance.refresh()).toBe(true);
    expect(await instance.refresh()).toBe(false);
    expect(calls).toBe(5);
  } finally {
    await NodeFSP.rm(root, { recursive: true, force: true });
  }
});

it("keeps the previous snapshot after a partial download and retries the same revision", async () => {
  const root = await NodeFSP.mkdtemp(NodePath.join(NodeOS.tmpdir(), "backplane-kistack-partial-"));
  let fail = true;
  const fetchImpl = async (input: string, init?: RequestInit): Promise<Response> => {
    if (input.endsWith("/commits/HEAD")) {
      expect(new Headers(init?.headers).get("if-none-match")).toBeNull();
      return new Response(JSON.stringify({ sha: revision }), { headers: { etag: '"retry"' } });
    }
    if (input.includes("/git/trees/")) return new Response(JSON.stringify({ tree }));
    if (input.endsWith("/LICENSE")) return new Response("test\n");
    if (fail) {
      fail = false;
      return new Response("broken", { status: 503 });
    }
    return new Response(skill);
  };
  try {
    const instance = createKiStackSkills({ cacheDirectory: root, fetchImpl });
    await expect(instance.refresh()).rejects.toThrow();
    expect(instance.revision).toBe(bundle.revision);
    expect(
      await NodeFSP.stat(NodePath.join(root, revision)).catch(() => undefined),
    ).toBeUndefined();
    expect(await instance.refresh()).toBe(true);
    expect(instance.revision).toBe(revision);
  } finally {
    await NodeFSP.rm(root, { recursive: true, force: true });
  }
});

it("rejects unsafe paths and preserves binary files while parsing multiline YAML", async () => {
  const root = await NodeFSP.mkdtemp(NodePath.join(NodeOS.tmpdir(), "backplane-kistack-safety-"));
  const binaryRevision = "b".repeat(40);
  const binary = new Uint8Array([0, 255, 1, 2]);
  const multiline = "---\nname: kicad-binary\ndescription: >\n  A multiline\n  description.\n---\n";
  const fetchImpl = async (input: string): Promise<Response> => {
    if (input.endsWith("/commits/HEAD"))
      return new Response(JSON.stringify({ sha: binaryRevision }));
    if (input.includes("/git/trees/"))
      return new Response(
        JSON.stringify({
          tree: [
            { path: "LICENSE", type: "blob", mode: "100644", size: 1 },
            { path: "skills/test/SKILL.md", type: "blob", mode: "100644", size: multiline.length },
            { path: "skills/test/data.bin", type: "blob", mode: "100755", size: binary.length },
            { path: "skills/../escape", type: "blob", mode: "100644", size: 1 },
          ],
        }),
      );
    return new Response("x");
  };
  try {
    const instance = createKiStackSkills({ cacheDirectory: root, fetchImpl });
    await expect(instance.refresh()).rejects.toThrow();
    expect(
      await NodeFSP.stat(NodePath.join(root, binaryRevision)).catch(() => undefined),
    ).toBeUndefined();
    const validFetch = async (input: string): Promise<Response> => {
      if (input.endsWith("/commits/HEAD"))
        return new Response(JSON.stringify({ sha: binaryRevision }));
      if (input.includes("/git/trees/"))
        return new Response(
          JSON.stringify({
            tree: [
              { path: "LICENSE", type: "blob", mode: "100644", size: 1 },
              {
                path: "skills/test/SKILL.md",
                type: "blob",
                mode: "100644",
                size: multiline.length,
              },
              { path: "skills/test/data.bin", type: "blob", mode: "100755", size: binary.length },
            ],
          }),
        );
      if (input.endsWith("data.bin")) return new Response(binary);
      return new Response(multiline);
    };
    const valid = createKiStackSkills({ cacheDirectory: root, fetchImpl: validFetch });
    expect(await valid.refresh()).toBe(true);
    expect(
      new Uint8Array(
        await NodeFSP.readFile(NodePath.join(root, binaryRevision, "skills/test/data.bin")),
      ),
    ).toEqual(binary);
    expect(valid.buildInstructions()).toContain("A multiline description.");
  } finally {
    await NodeFSP.rm(root, { recursive: true, force: true });
  }
});

it("backs off after rate limiting and resumes when the retry window expires", async () => {
  const root = await NodeFSP.mkdtemp(NodePath.join(NodeOS.tmpdir(), "backplane-kistack-rate-"));
  let current = 100;
  let calls = 0;
  const fetchImpl = async (): Promise<Response> => {
    calls += 1;
    if (calls === 1) return new Response(null, { status: 429, headers: { "retry-after": "10" } });
    return new Response(JSON.stringify({ sha: bundle.revision }));
  };
  try {
    const instance = createKiStackSkills({ cacheDirectory: root, fetchImpl, now: () => current });
    await expect(instance.refresh()).rejects.toThrow();
    current = 5_000;
    expect(await instance.refresh()).toBe(false);
    expect(calls).toBe(1);
    current = 10_100;
    expect(await instance.refresh()).toBe(false);
    expect(calls).toBe(2);
  } finally {
    await NodeFSP.rm(root, { recursive: true, force: true });
  }
});
