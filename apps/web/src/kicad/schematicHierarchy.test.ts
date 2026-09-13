import { describe, expect, it } from "vite-plus/test";

type SheetPage = {
  projectPath: string;
  sheetPath: string;
  name: string;
  filename?: string;
  parentProjectPath?: string;
};
type SheetNode = SheetPage & { children: SheetNode[] };
type SheetTree = { roots: SheetNode[]; nodes: SheetNode[] };
const { schematicAncestors, schematicTree } = (await import(
  /* @vite-ignore */
  `${new URL("../../public/kicad-viewer/", import.meta.url).href}schematic-hierarchy.js`
)) as {
  schematicAncestors: (tree: SheetTree, path: string) => Set<string>;
  schematicTree: (pages: SheetPage[]) => SheetTree;
};

const page = (projectPath: string, parentProjectPath?: string) => ({
  projectPath,
  sheetPath: `/${projectPath}`,
  name: projectPath,
  ...(parentProjectPath ? { parentProjectPath } : {}),
});

describe("schematic hierarchy model", () => {
  it("builds parent-child rows while preserving repeated source files", () => {
    const tree = schematicTree([
      page("root"),
      page("root:/a", "root"),
      page("root:/b", "root"),
      { ...page("root:/b:/shared", "root:/b"), filename: "shared.kicad_sch" },
      { ...page("root:/a:/shared", "root:/a"), filename: "shared.kicad_sch" },
    ]);
    expect(tree.roots.map((node) => node.projectPath)).toEqual(["root"]);
    expect(tree.roots[0]!.children.map((node) => node.projectPath)).toEqual(["root:/a", "root:/b"]);
    expect(tree.nodes.filter((node) => node.filename === "shared.kicad_sch")).toHaveLength(2);
    expect(schematicAncestors(tree, "root:/b:/shared")).toEqual(new Set(["root:/b", "root"]));
  });

  it("promotes missing parents and breaks cyclic links", () => {
    const tree = schematicTree([page("orphan", "missing"), page("a", "b"), page("b", "a")]);
    expect(tree.roots.map((node) => node.projectPath)).toEqual(["orphan", "a"]);
    expect(tree.roots[1]!.children.map((node) => node.projectPath)).toEqual(["b"]);
    expect(tree.roots[1]!.children[0]!.children).toHaveLength(0);
  });
});
