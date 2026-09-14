import { afterEach, describe, expect, it, vi } from "vite-plus/test";

type SheetPage = {
  projectPath: string;
  sheetPath: string;
  name: string;
  filename?: string;
  parentProjectPath?: string;
};
type SheetNode = SheetPage & { children: SheetNode[] };
type SheetTree = { roots: SheetNode[]; nodes: SheetNode[] };
const { schematicAncestors, schematicTree, installSchematicHierarchy } = (await import(
  /* @vite-ignore */
  `${new URL("../../public/kicad-viewer/", import.meta.url).href}schematic-hierarchy.js`
)) as {
  schematicAncestors: (tree: SheetTree, path: string) => Set<string>;
  schematicTree: (pages: SheetPage[]) => SheetTree;
  installSchematicHierarchy: (host: TestElement, viewer: TestViewer) => void;
};

const page = (projectPath: string, parentProjectPath?: string) => ({
  projectPath,
  sheetPath: `/${projectPath}`,
  name: projectPath,
  ...(parentProjectPath ? { parentProjectPath } : {}),
});

// Only the DOM operations used by the navigator; page changes still run through
// its real event handlers and asynchronous navigation/history implementation.
class TestElement extends EventTarget {
  className = "";
  textContent = "";
  disabled = false;
  children: TestElement[] = [];
  attributes = new Map<string, string>();
  style = { setProperty() {} };
  classList = {
    contains: (name: string) => this.className.split(" ").includes(name),
    add: (name: string) => {
      this.className += ` ${name}`;
    },
    toggle: (name: string) => {
      const present = this.classList.contains(name);
      this.className = this.className
        .split(" ")
        .filter((value) => value !== name)
        .join(" ");
      if (!present) this.classList.add(name);
      return !present;
    },
  };
  append(...children: TestElement[]) {
    this.children.push(...children);
  }
  replaceChildren(...children: TestElement[]) {
    this.children = children;
  }
  setAttribute(name: string, value: string) {
    this.attributes.set(name, value);
  }
  querySelector(selector: string): TestElement | undefined {
    for (const child of this.children) {
      if (child.classList.contains(selector.slice(1))) return child;
      const nested = child.querySelector(selector);
      if (nested) return nested;
    }
    return undefined;
  }
  remove() {}
}

class TestViewer extends EventTarget {
  pages = [page("root"), page("child", "root")];
  active = "root";
  getSchematicPages() {
    return this.pages;
  }
  getActiveSchematicPage() {
    return this.pages.find((item) => item.projectPath === this.active);
  }
  async showPage(path: string) {
    this.active = path;
    this.dispatchEvent(new Event("ecad-viewer:view-state-change"));
  }
}

afterEach(() => vi.unstubAllGlobals());

describe("schematic hierarchy navigation", () => {
  function install(coarse: boolean) {
    vi.stubGlobal("document", { createElement: () => new TestElement() });
    vi.stubGlobal("matchMedia", (query: string) => ({
      matches: query.includes("max-width") && (!query.includes("pointer: coarse") || coarse),
    }));
    const host = new TestElement();
    const viewer = new TestViewer();
    installSchematicHierarchy(host, viewer);
    return { host, viewer, panel: host.querySelector(".schematic-hierarchy-panel")! };
  }

  it("shows sheets in a narrow desktop panel and preserves manual collapse", () => {
    const { host, viewer, panel } = install(false);
    expect(panel.classList.contains("is-collapsed")).toBe(false);
    expect(panel.querySelector(".schematic-hierarchy-tree")?.children).toHaveLength(2);
    panel.querySelector(".schematic-hierarchy-toggle")!.dispatchEvent(new Event("click"));
    installSchematicHierarchy(host, viewer);
    expect(panel.classList.contains("is-collapsed")).toBe(true);
  });

  it("lets a small touch viewer open its initially collapsed sheets", () => {
    const { panel } = install(true);
    expect(panel.classList.contains("is-collapsed")).toBe(true);
    panel.querySelector(".schematic-hierarchy-toggle")!.dispatchEvent(new Event("click"));
    expect(panel.classList.contains("is-collapsed")).toBe(false);
  });

  it("navigates to a child, returns with Back/Up, and refreshes a retained tree", async () => {
    const { host, viewer, panel } = install(false);
    const child = () =>
      panel
        .querySelector(".schematic-hierarchy-tree")!
        .children[1]!.querySelector(".schematic-hierarchy-item")!;
    child().dispatchEvent(new Event("click"));
    await Promise.resolve();
    expect(viewer.active).toBe("child");
    panel.querySelector(".schematic-hierarchy-back")!.dispatchEvent(new Event("click"));
    await Promise.resolve();
    await Promise.resolve();
    expect(viewer.active).toBe("root");
    child().dispatchEvent(new Event("click"));
    await Promise.resolve();
    panel.querySelector(".schematic-hierarchy-up")!.dispatchEvent(new Event("click"));
    await Promise.resolve();
    expect(viewer.active).toBe("root");
    viewer.pages.push(page("new sheet", "root"));
    installSchematicHierarchy(host, viewer);
    expect(panel.querySelector(".schematic-hierarchy-tree")?.children).toHaveLength(3);
    expect(host.children).toHaveLength(1);
  });
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
