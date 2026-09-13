// A small host-side hierarchy navigator for the schematic pages exposed by Prism.

const normalize = (value) => String(value ?? "").replaceAll("\\", "/");

export function schematicTree(pages) {
  const nodes = pages
    .filter((page) => page?.projectPath)
    .map((page) => ({
      ...page,
      projectPath: normalize(page.projectPath),
      sheetPath: normalize(page.sheetPath),
      parentProjectPath: page.parentProjectPath ? normalize(page.parentProjectPath) : undefined,
      children: [],
    }));
  const byPath = new Map(nodes.map((node) => [node.projectPath, node]));
  const roots = [];
  for (const node of nodes) {
    const parent = node.parentProjectPath && byPath.get(node.parentProjectPath);
    if (parent && parent !== node) parent.children.push(node);
    else roots.push(node);
  }
  const visited = new Set();
  const visit = (node) => {
    visited.add(node.projectPath);
    node.children = node.children.filter((child) => {
      if (visited.has(child.projectPath)) return false;
      visit(child);
      return true;
    });
  };
  for (const root of roots) visit(root);
  // Preserve unreachable pages from malformed cycles without recursive loops.
  for (const node of nodes) {
    if (visited.has(node.projectPath)) continue;
    roots.push(node);
    visit(node);
  }
  return { roots, nodes };
}

export function schematicAncestors(tree, projectPath) {
  const byPath = new Map(tree.nodes.map((node) => [node.projectPath, node]));
  const result = new Set();
  let current = byPath.get(normalize(projectPath));
  while (current?.parentProjectPath && !result.has(current.parentProjectPath)) {
    result.add(current.parentProjectPath);
    current = byPath.get(current.parentProjectPath);
  }
  return result;
}

const text = (node) => node.name || node.page || node.filename || node.projectPath;

function button(label, className) {
  const element = document.createElement("button");
  element.type = "button";
  element.className = className;
  element.textContent = label;
  return element;
}

export function installSchematicHierarchy(host, viewer) {
  if (!host || !viewer?.getSchematicPages) return undefined;
  let panel = host.querySelector(".schematic-hierarchy-panel");
  if (panel?.__backplaneHierarchy?.viewer === viewer) return panel.__backplaneHierarchy;
  panel?.__backplaneHierarchy?.dispose?.();
  panel?.remove();

  const state = {
    viewer,
    history: [],
    expanded: new Set(),
    currentPath: undefined,
    suppressHistory: false,
  };
  const root = document.createElement("section");
  root.className = "schematic-hierarchy-panel";
  if (matchMedia("(max-width: 640px)").matches) root.classList.add("is-collapsed");
  root.setAttribute("aria-label", "Schematic hierarchy");
  const heading = document.createElement("div");
  heading.className = "schematic-hierarchy-heading";
  const toggle = button("Hierarchy", "schematic-hierarchy-toggle");
  toggle.setAttribute("aria-expanded", String(!root.classList.contains("is-collapsed")));
  toggle.addEventListener("click", () => {
    const collapsed = root.classList.toggle("is-collapsed");
    toggle.setAttribute("aria-expanded", String(!collapsed));
  });
  heading.append(toggle);
  const actions = document.createElement("div");
  actions.className = "schematic-hierarchy-actions";
  const back = button("Back", "schematic-hierarchy-back");
  const up = button("Up", "schematic-hierarchy-up");
  actions.append(back, up);
  heading.append(actions);
  const treeElement = document.createElement("div");
  treeElement.className = "schematic-hierarchy-tree";
  treeElement.setAttribute("role", "tree");
  const status = document.createElement("div");
  status.className = "schematic-hierarchy-status";
  status.setAttribute("role", "status");
  root.append(heading, treeElement, status);
  host.append(root);
  panel = root;

  const getPages = () => viewer.getSchematicPages?.() ?? [];
  const activePath = () => viewer.getActiveSchematicPage?.()?.projectPath;
  const navigate = async (path, remember = true) => {
    const pages = getPages();
    if (
      state.suppressHistory ||
      !path ||
      path === activePath() ||
      !pages.some((page) => page.projectPath === path)
    )
      return false;
    const previous = activePath();
    state.suppressHistory = true;
    status.textContent = "";
    try {
      await viewer.showPage(path);
      const changed = activePath() === path;
      if (changed && remember && previous) state.history.push(previous);
      return changed;
    } catch {
      status.textContent = "Could not open sheet. Refresh saved files and try again.";
      return false;
    } finally {
      state.suppressHistory = false;
      render();
    }
  };
  const renderNode = (node, depth, tree) => {
    const hasChildren = node.children.length > 0;
    const open = state.expanded.has(node.projectPath);
    const row = document.createElement("div");
    row.className = "schematic-hierarchy-row";
    row.style.setProperty("--schematic-depth", String(depth));
    row.setAttribute("role", "treeitem");
    row.setAttribute("aria-selected", String(node.projectPath === state.currentPath));
    row.setAttribute("aria-level", String(depth + 1));
    if (hasChildren) {
      const disclosure = button(open ? "▾" : "▸", "schematic-hierarchy-disclosure");
      disclosure.setAttribute("aria-label", `${open ? "Collapse" : "Expand"} ${text(node)}`);
      disclosure.addEventListener("click", (event) => {
        event.stopPropagation();
        if (open) state.expanded.delete(node.projectPath);
        else state.expanded.add(node.projectPath);
        render();
      });
      row.append(disclosure);
    } else {
      const spacer = document.createElement("span");
      spacer.className = "schematic-hierarchy-disclosure-spacer";
      row.append(spacer);
    }
    const select = button(text(node), "schematic-hierarchy-item");
    select.setAttribute("aria-current", node.projectPath === state.currentPath ? "page" : "false");
    select.addEventListener("click", () => void navigate(node.projectPath));
    row.append(select);
    tree.append(row);
    if (hasChildren && open) {
      row.setAttribute("aria-expanded", "true");
      for (const child of node.children) renderNode(child, depth + 1, tree);
    } else if (hasChildren) row.setAttribute("aria-expanded", "false");
  };
  let renderedState;
  const render = () => {
    const pages = getPages();
    const tree = schematicTree(pages);
    const available = new Set(pages.map((page) => page.projectPath));
    state.history = state.history.filter((path) => available.has(path));
    if (state.currentPath === undefined)
      for (const node of tree.roots) state.expanded.add(node.projectPath);
    const nextPath = activePath() ?? pages.find((page) => page.active)?.projectPath;
    if (nextPath !== state.currentPath)
      for (const ancestor of schematicAncestors(tree, nextPath)) state.expanded.add(ancestor);
    state.currentPath = nextPath;
    const nextRender = JSON.stringify([
      pages,
      state.currentPath,
      [...state.expanded],
      state.history,
    ]);
    if (nextRender === renderedState) return;
    renderedState = nextRender;
    treeElement.replaceChildren();
    for (const node of tree.roots) renderNode(node, 0, treeElement);
    back.disabled = state.history.length === 0;
    const current = pages.find((page) => page.projectPath === state.currentPath);
    up.disabled = !available.has(current?.parentProjectPath);
    if (!pages.length) treeElement.textContent = "No schematic pages";
  };
  back.addEventListener("click", async () => {
    if (state.suppressHistory) return;
    const target = state.history.at(-1);
    if (target && (await navigate(target, false))) {
      state.history.pop();
      render();
    }
  });
  up.addEventListener("click", () => {
    const target = viewer.getActiveSchematicPage?.()?.parentProjectPath;
    if (target) void navigate(target);
  });
  const sync = () => {
    const next = activePath();
    if (next && state.currentPath && next !== state.currentPath && !state.suppressHistory)
      state.history.push(state.currentPath);
    render();
  };
  viewer.addEventListener?.("ecad-viewer:view-state-change", sync);
  state.sync = sync;
  state.dispose = () => {
    viewer.removeEventListener?.("ecad-viewer:view-state-change", sync);
    root.remove();
  };
  panel.__backplaneHierarchy = state;
  render();
  return state;
}
