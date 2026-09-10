const styledRoots = new WeakSet();
const installedViewers = new WeakMap();
const panelStates = new WeakMap();
let inspectorId = 0;

// The viewer keeps the selected item in its own property list. The adapter only
// reads that list and gives it a calmer, responsive presentation; selection,
// close, and the vendor's update lifecycle remain owned by the viewer.
const BASE_PROPERTIES_CSS = `
:host {
  --backplane-bg: #111617;
  --backplane-panel: #171e20;
  --backplane-panel-raised: #1e292a;
  --backplane-line: #354243;
  --backplane-line-strong: #536461;
  --backplane-fg: #d7e3dc;
  --backplane-muted: #9aada2;
  --backplane-accent: #a6d4ad;
  --panel-subtitle-bg: var(--backplane-panel-raised);
  --panel-subtitle-fg: var(--backplane-fg);
  --fg: var(--backplane-fg);
  --scrollbar-bg: var(--backplane-bg);
  --scrollbar-fg: var(--backplane-line-strong);
  --scrollbar-hover-fg: var(--backplane-accent);
  color: var(--backplane-fg);
  font-family: "Berkeley Mono", ui-monospace, SFMono-Regular, Menlo, monospace;
}

.bottom-left-icon,
a[aria-label*="KiCAD Prism" i] {
  display: none !important;
}

kc-board-properties-panel,
kc-schematic-properties-panel {
  --floating-pro-panel-width: min(24rem, calc(100% - 1rem));
  --backplane-properties-height: clamp(18rem, 36vh, 24rem);
  position: absolute !important;
  inset: auto 0 0 auto !important;
  width: 0 !important;
  height: 0 !important;
  min-width: 0 !important;
  min-height: 0 !important;
  display: block !important;
  overflow: visible !important;
  pointer-events: none;
  color: var(--backplane-fg);
  font-family: inherit;
  font-size: 14px;
  line-height: 1.35;
}

kc-board-properties-panel[hidden],
kc-schematic-properties-panel[hidden] {
  display: none !important;
}

kc-ui-panel {
  background: var(--backplane-panel) !important;
  border: 1px solid var(--backplane-line) !important;
  border-radius: 0 !important;
  box-shadow: 0 10px 28px #0008 !important;
  color: var(--backplane-fg) !important;
}

:host(kc-board-properties-panel) > kc-ui-panel,
:host(kc-schematic-properties-panel) > kc-ui-panel {
  position: fixed !important;
  inset: auto 0 0 !important;
  z-index: 40 !important;
  box-sizing: border-box !important;
  width: 100vw !important;
  max-width: none !important;
  height: var(--backplane-properties-height) !important;
  min-height: 0 !important;
  max-height: calc(100vh - 0.5rem) !important;
  display: flex !important;
  flex-direction: column !important;
  font-size: 14px !important;
  line-height: 1.35 !important;
  pointer-events: auto;
  background: var(--backplane-panel) !important;
  border: 1px solid var(--backplane-line) !important;
  border-radius: 0 !important;
  box-shadow: 0 10px 28px #0008 !important;
  color: var(--backplane-fg) !important;
}

kc-board-properties-panel[data-backplane-properties-expanded="true"],
kc-schematic-properties-panel[data-backplane-properties-expanded="true"],
:host([data-backplane-properties-expanded="true"]) {
  --backplane-properties-height: min(70vh, 42rem);
}

kc-ui-panel-title,
kc-ui-panel-title-with-close {
  background: var(--backplane-panel-raised) !important;
  border-bottom: 1px solid var(--backplane-line) !important;
  color: var(--backplane-muted) !important;
  font-family: inherit !important;
  letter-spacing: 0.01em;
}

:host(kc-ui-panel-title-with-close) {
  min-height: 2.25rem !important;
  justify-content: flex-end;
}

:host(kc-ui-panel-title-with-close) .title {
  display: none !important;
}

kc-ui-panel-body {
  flex: 1 1 auto !important;
  min-height: 0 !important;
  overflow: auto !important;
  background: var(--backplane-panel) !important;
  color: var(--backplane-fg) !important;
}

button,
input,
select {
  font: inherit;
}

kc-ui-icon {
  color: var(--backplane-accent) !important;
  font-family: inherit !important;
}

@media (max-width: 640px) {
  kc-board-properties-panel,
  kc-schematic-properties-panel {
    --floating-pro-panel-width: calc(100% - 1rem);
    --backplane-properties-height: min(42vh, 20rem);
  }

  kc-board-properties-panel[data-backplane-properties-expanded="true"],
  kc-schematic-properties-panel[data-backplane-properties-expanded="true"],
  :host([data-backplane-properties-expanded="true"]) {
    --backplane-properties-height: min(84vh, 38rem);
  }

  :host(kc-ui-panel-title-with-close) {
    min-height: 2.75rem !important;
  }

  kc-ui-button[variant="close"],
  kc-ui-button[variant="close"]::part(base) {
    min-width: 44px !important;
    min-height: 44px !important;
  }
}
`;

const INSPECTOR_CSS = `
:host {
  display: block;
  color: #d7e3dc;
  font: 14px/1.4 "Berkeley Mono", ui-monospace, SFMono-Regular, Menlo, monospace;
  --line: #354243;
  --muted: #9aada2;
  --accent: #a6d4ad;
  --raised: #1e292a;
  --focus: #d6f2db;
}

.inspector {
  min-width: 0;
  padding: 0.9rem 1rem 1rem;
}

.inspector-header {
  display: flex;
  align-items: flex-start;
  gap: 1rem;
  justify-content: space-between;
  padding-bottom: 0.8rem;
  border-bottom: 1px solid var(--line);
}

.heading {
  min-width: 0;
}

.headline {
  color: var(--accent);
  font-size: 1rem;
  font-weight: 700;
  line-height: 1.35;
  overflow-wrap: anywhere;
}

.kind {
  margin-top: 0.2rem;
  color: var(--muted);
  font-size: 0.875rem;
}

.toggle {
  flex: 0 0 auto;
  min-height: 2.25rem;
  padding: 0.45rem 0.7rem;
  border: 1px solid var(--line);
  border-radius: 0;
  background: transparent;
  color: var(--accent);
  cursor: pointer;
  font-size: 0.875rem;
  text-align: left;
}

.toggle:hover {
  background: var(--raised);
}

.toggle:focus-visible {
  outline: 2px solid var(--focus);
  outline-offset: 2px;
}

.summary {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(min(18rem, 100%), 1fr));
  column-gap: 2rem;
}

.property {
  display: grid;
  grid-template-columns: minmax(7rem, 34%) minmax(0, 1fr);
  gap: 0.75rem;
  min-width: 0;
  padding: 0.58rem 0;
  border-bottom: 1px solid var(--line);
}

dt {
  min-width: 0;
  color: var(--muted);
  font-size: 0.875rem;
}

dd {
  min-width: 0;
  margin: 0;
  color: #e0ebe3;
  font-size: 1rem;
  overflow-wrap: anywhere;
  white-space: pre-wrap;
}

.all-properties {
  padding-top: 0.25rem;
}

.section {
  min-width: 0;
}

.section-properties {
  margin: 0;
}

.section + .section {
  margin-top: 0.9rem;
}

.section-title {
  margin: 0;
  padding: 0.55rem 0 0.35rem;
  color: var(--muted);
  font-size: 0.875rem;
  font-weight: 400;
}

.empty {
  margin: 0.8rem 0 0;
  color: var(--muted);
}

@media (max-width: 640px) {
  .inspector {
    padding: 0.8rem 0.7rem 0.9rem;
  }

  .inspector-header {
    gap: 0.7rem;
  }

  .toggle {
    max-width: 9rem;
    font-size: 0.875rem;
  }

  .summary {
    grid-template-columns: 1fr;
  }

  .property {
    grid-template-columns: minmax(6.5rem, 36%) minmax(0, 1fr);
    gap: 0.55rem;
  }
}
`;

const panelSheet = new CSSStyleSheet();
panelSheet.replaceSync(BASE_PROPERTIES_CSS);

function installStyle(root) {
  if (styledRoots.has(root)) return;
  styledRoots.add(root);
  root.adoptedStyleSheets = [...root.adoptedStyleSheets, panelSheet];
}

function normalizeBooleanIcons(root) {
  for (const icon of root.querySelectorAll?.("kc-ui-icon") ?? []) {
    const text = icon.textContent?.trim();
    const replacement =
      text === "check" || text === "yes"
        ? "Yes"
        : text === "close" || text === "no"
          ? "No"
          : undefined;
    if (!replacement || text === replacement) continue;
    icon.dataset.backplaneBooleanIcon = replacement;
    icon.setAttribute("aria-label", replacement);
    icon.textContent = replacement;
  }
}

function cleanText(value) {
  return String(value ?? "")
    .replace(/\s+/g, " ")
    .trim();
}

function sentenceCaseLabel(label) {
  const normalized = cleanText(label)
    .replace(/[_-]+/g, " ")
    .replace(/([a-z])([A-Z])/g, "$1 $2");
  const special = {
    lcsc: "LCSC",
    mpn: "MPN",
    bom: "BOM",
    dnp: "DNP",
    kicad: "KiCad",
    pcb: "PCB",
    x: "X",
    y: "Y",
  };
  const lower = normalized.toLowerCase();
  if (special[lower]) return special[lower];
  return lower ? lower[0].toUpperCase() + lower.slice(1) : "Property";
}

function readRows(list) {
  return [...list.children]
    .filter((item) => item.localName === "kc-ui-property-list-item")
    .map((item) => ({
      group: item.classList.contains("label"),
      name: cleanText(item.getAttribute("name")),
      value: cleanText(item.textContent),
    }))
    .filter((row) => row.name);
}

function rowKey(row) {
  return row.name.toLowerCase().replace(/[_-]+/g, " ").replace(/\s+/g, " ").trim();
}

const COORDINATE_ROWS = new Set(["x", "y", "end x", "end y", "width", "height", "orientation"]);

const SUMMARY_ORDER = [
  "footprint",
  "library link",
  "mpn",
  "manufacturer",
  "voltage",
  "dielectric",
  "datasheet",
  "description",
  "type",
  "net",
  "layer",
  "shape",
  "drill",
  "pin function",
  "pin type",
  "pinnum",
  "pads",
  "unit",
  "power",
];

function summaryRows(rows) {
  const properties = rows.filter((row) => !row.group);
  const meaningful = properties.filter((row) => !COORDINATE_ROWS.has(rowKey(row)));
  const selected = [];
  for (const key of SUMMARY_ORDER) {
    const row = meaningful.find(
      (candidate) => rowKey(candidate) === key && candidate.value && !selected.includes(candidate),
    );
    if (row) selected.push(row);
  }
  for (const row of meaningful) {
    if (selected.length >= 8) break;
    if (!selected.includes(row) && row.value) selected.push(row);
  }
  return selected.slice(0, 8);
}

function panelKind(panel) {
  const title = panel.shadowRoot?.querySelector("kc-ui-panel-title-with-close");
  return (
    cleanText(title?.title || title?.getAttribute("title")) ||
    (panel.localName === "kc-board-properties-panel" ? "Board item" : "Schematic item")
  );
}

function makeElement(tag, className, text) {
  const element = document.createElement(tag);
  if (className) element.className = className;
  if (text !== undefined) element.textContent = text;
  return element;
}

function appendProperty(parent, row) {
  const item = makeElement("div", "property");
  const label = makeElement("dt", undefined, sentenceCaseLabel(row.name));
  const value = makeElement("dd", undefined, row.value || "—");
  item.append(label, value);
  parent.append(item);
}

function renderAllProperties(parent, rows) {
  const all = makeElement("div", "all-properties");
  let section;
  let propertyList;
  for (const row of rows) {
    if (row.group || !section) {
      section = makeElement("section", "section");
      propertyList = makeElement("dl", "section-properties");
      if (row.group)
        section.append(makeElement("h3", "section-title", sentenceCaseLabel(row.name)));
      section.append(propertyList);
      all.append(section);
      if (row.group) continue;
    }
    appendProperty(propertyList, row);
  }
  parent.append(all);
}

function createInspector() {
  const host = document.createElement("div");
  host.dataset.backplanePropertyInspector = "true";
  const shadow = host.attachShadow({ mode: "open" });
  const style = document.createElement("style");
  style.textContent = INSPECTOR_CSS;
  const root = makeElement("div", "inspector");
  shadow.append(style, root);
  return { host, root };
}

function updateInspector(panel, body, list, rows) {
  let state = panelStates.get(panel);
  if (!state) {
    state = { ...createInspector(), expanded: false, signature: "" };
    panelStates.set(panel, state);
  }

  list.style.display = "none";
  if (state.host.parentElement !== body) body.append(state.host);

  const kind = panelKind(panel);
  const reference = rows.find((row) => !row.group && rowKey(row) === "reference")?.value;
  const value = rows.find((row) => !row.group && rowKey(row) === "value")?.value;
  const headline = [reference, value].filter(Boolean).join(" · ") || kind || "Selected item";
  const signature = `${kind}\u0000${headline}\u0000${rows.map((row) => `${row.group ? "g" : "p"}:${row.name}:${row.value}`).join("\u0001")}`;
  const expanded = state.expanded;
  const viewSignature = `${signature}\u0000${expanded ? "expanded" : "compact"}`;
  if (state.signature === viewSignature) return;
  state.signature = viewSignature;

  const inspector = state.root;
  inspector.replaceChildren();
  const header = makeElement("div", "inspector-header");
  const heading = makeElement("div", "heading");
  heading.append(makeElement("div", "headline", headline), makeElement("div", "kind", kind));
  const propertyCount = rows.filter((row) => !row.group).length;
  const toggle = makeElement(
    "button",
    "toggle",
    expanded ? `Collapse properties (${propertyCount})` : `All properties (${propertyCount})`,
  );
  const propertiesId = `backplane-properties-${++inspectorId}`;
  toggle.type = "button";
  toggle.setAttribute("aria-expanded", String(expanded));
  toggle.setAttribute("aria-controls", propertiesId);
  toggle.addEventListener("click", () => {
    state.expanded = !state.expanded;
    if (state.expanded) panel.setAttribute("data-backplane-properties-expanded", "true");
    else panel.removeAttribute("data-backplane-properties-expanded");
    updateInspector(panel, body, list, rows);
  });
  header.append(heading, toggle);
  inspector.append(header);

  if (expanded) {
    const content = makeElement("div");
    content.id = propertiesId;
    renderAllProperties(content, rows);
    inspector.append(content);
  } else {
    const summary = makeElement("dl", "summary");
    const compact = summaryRows(rows);
    if (compact.length) compact.forEach((row) => appendProperty(summary, row));
    else summary.append(makeElement("dd", "empty", "No additional properties"));
    summary.id = propertiesId;
    inspector.append(summary);
  }
}

function decoratePropertyPanel(panel) {
  const body = panel.shadowRoot?.querySelector("kc-ui-panel-body");
  const list = body?.querySelector("kc-ui-property-list");
  if (!body || !list) return;
  updateInspector(panel, body, list, readRows(list));
}

export function installMobileProperties(viewer) {
  if (!viewer.shadowRoot) return;
  const refresh = installedViewers.get(viewer);
  if (refresh) {
    refresh();
    return;
  }
  const observedRoots = new WeakSet();
  let refreshQueued = false;
  const visit = (root) => {
    installStyle(root);
    normalizeBooleanIcons(root);
    for (const panel of root.querySelectorAll?.(
      "kc-board-properties-panel, kc-schematic-properties-panel",
    ) ?? []) {
      decoratePropertyPanel(panel);
    }
    if (!observedRoots.has(root)) {
      observedRoots.add(root);
      new MutationObserver(() => {
        if (refreshQueued) return;
        refreshQueued = true;
        requestAnimationFrame(() => {
          refreshQueued = false;
          if (viewer.shadowRoot) visit(viewer.shadowRoot);
        });
      }).observe(root, { childList: true, subtree: true });
    }
    for (const element of root.querySelectorAll("*")) {
      if (element.shadowRoot) visit(element.shadowRoot);
    }
  };
  const refreshViewer = () => {
    if (viewer.shadowRoot) visit(viewer.shadowRoot);
  };
  installedViewers.set(viewer, refreshViewer);
  refreshViewer();
}
