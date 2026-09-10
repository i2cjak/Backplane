const styledRoots = new WeakSet();
const installedViewers = new WeakMap();

// The property panels live across several nested custom-element shadow roots.
// Keep this adapter outside the vendor bundle and install the same compact
// Backplane treatment at each root as it appears.
const BASE_PROPERTIES_CSS = `
:host {
  --backplane-bg: #111617;
  --backplane-panel: #171e20;
  --backplane-panel-raised: #1e292a;
  --backplane-line: #354243;
  --backplane-line-strong: #536461;
  --backplane-fg: #d7e3dc;
  --backplane-accent: #8fbe9a;
  --prop-panel-bg: var(--backplane-line);
  --prop-border-color: var(--backplane-line);
  --panel-subtitle-bg: var(--backplane-panel-raised);
  --panel-subtitle-fg: var(--backplane-accent);
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
  color: var(--backplane-fg);
  font-family: inherit;
}

kc-ui-panel {
  background: var(--backplane-panel) !important;
  border: 1px solid var(--backplane-line) !important;
  border-radius: 0 !important;
  box-shadow: 0 10px 28px #0008 !important;
  color: var(--backplane-fg) !important;
}

kc-ui-panel-title,
kc-ui-panel-title-with-close {
  background: var(--backplane-panel-raised) !important;
  border-bottom: 1px solid var(--backplane-line) !important;
  color: var(--backplane-fg) !important;
  font-family: inherit !important;
  letter-spacing: 0.02em;
}

kc-ui-panel-body {
  background: var(--backplane-panel) !important;
  color: var(--backplane-fg) !important;
}

kc-ui-property-list {
  width: 100%;
  min-width: 0;
  grid-template-columns: minmax(5.5rem, 38%) minmax(0, 1fr) !important;
  gap: 1px !important;
  background: var(--backplane-line) !important;
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
    right: 0.5rem !important;
    left: 0.5rem;
    width: auto !important;
    max-height: calc(100% - 1rem);
  }
}
`;

const BASE_PROPERTY_ITEM_CSS = `
:host span {
  box-sizing: border-box;
  min-width: 0;
  padding: 0.3rem 0.42rem !important;
  background: var(--backplane-panel) !important;
  border: 0 !important;
  border-bottom: 1px solid var(--backplane-line) !important;
  color: var(--backplane-fg) !important;
  font: inherit !important;
  line-height: 1.3;
  overflow-wrap: anywhere;
  white-space: normal !important;
}

:host(.label) span:first-of-type {
  background: var(--backplane-panel-raised) !important;
  color: var(--backplane-accent) !important;
  font-size: 0.86em;
  letter-spacing: 0.04em;
  text-transform: uppercase;
}
`;

const MOBILE_PROPERTIES_CSS = `
@media (max-width: 640px) {
  kc-board-properties-panel,
  kc-schematic-properties-panel {
    position: fixed !important;
    left: 8px !important;
    right: 8px !important;
    top: auto !important;
    bottom: 8px !important;
    width: auto !important;
    height: min(48vh, 360px) !important;
    max-height: calc(100vh - 16px) !important;
    min-height: 0 !important;
    z-index: 40 !important;
    align-items: stretch !important;
    border-radius: 0 !important;
    overflow: hidden !important;
    box-shadow: 0 10px 30px rgb(0 0 0 / 0.35) !important;
  }

  kc-board-properties-panel[hidden],
  kc-schematic-properties-panel[hidden] {
    display: none !important;
  }

  kc-ui-panel {
    width: 100% !important;
    max-width: none !important;
    min-height: 0 !important;
    max-height: 100% !important;
    display: flex !important;
    flex-direction: column !important;
  }

  kc-ui-panel-body {
    min-height: 0 !important;
    overflow: auto !important;
    -webkit-overflow-scrolling: touch !important;
  }

  kc-ui-property-list {
    font-size: 14px !important;
    line-height: 1.3 !important;
    grid-template-columns: minmax(7rem, 42%) minmax(0, 1fr) !important;
  }

  kc-ui-panel-title-with-close {
    min-height: 2.75rem !important;
  }

  kc-ui-button[variant="close"] {
    min-width: 44px !important;
    min-height: 44px !important;
  }

  kc-ui-button[variant="close"]::part(base) {
    min-width: 44px !important;
    min-height: 44px !important;
  }
}
`;

const MOBILE_PROPERTY_ITEM_CSS = `
@media (max-width: 640px) {
  :host {
    font-size: 14px !important;
    line-height: 1.3 !important;
  }

  :host span {
    min-height: 2.25rem !important;
    padding: 0.55rem 0.6rem !important;
    font-size: 14px !important;
    line-height: 1.3 !important;
    white-space: normal !important;
    overflow-wrap: anywhere !important;
    word-break: break-word !important;
    text-overflow: clip !important;
  }

  :host(.label) span:first-of-type {
    grid-column: 1 / -1;
    min-height: 2.5rem !important;
    font-weight: 700 !important;
  }

  :host(.label) span:nth-of-type(2) {
    display: none !important;
  }
}
`;

const panelSheet = new CSSStyleSheet();
panelSheet.replaceSync(`${BASE_PROPERTIES_CSS}${MOBILE_PROPERTIES_CSS}`);
const itemSheet = new CSSStyleSheet();
itemSheet.replaceSync(`${BASE_PROPERTIES_CSS}${BASE_PROPERTY_ITEM_CSS}${MOBILE_PROPERTY_ITEM_CSS}`);

function installStyle(root) {
  if (styledRoots.has(root)) return;
  styledRoots.add(root);
  // Keep the vendor DOM intact, including its first/last-child property-row selectors.
  root.adoptedStyleSheets = [
    ...root.adoptedStyleSheets,
    root.host?.localName === "kc-ui-property-list-item" ? itemSheet : panelSheet,
  ];
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
    if (!observedRoots.has(root)) {
      observedRoots.add(root);
      new MutationObserver(() => {
        if (refreshQueued) return;
        refreshQueued = true;
        requestAnimationFrame(() => {
          refreshQueued = false;
          if (viewer.shadowRoot) visit(viewer.shadowRoot);
        });
      }).observe(root, {
        childList: true,
        subtree: true,
      });
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
