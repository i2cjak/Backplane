export type PanelizationTheme = {
  background: string;
  foreground: string;
  muted: string;
  accent: string;
  highlight: string;
};

const FALLBACK_THEME: PanelizationTheme = {
  background: "#171918",
  foreground: "#f2f4ef",
  muted: "#9aa29b",
  accent: "#8bc6a1",
  highlight: "#a8dfba",
};

function cssColor(value: string | undefined, fallback: string) {
  const trimmed = value?.trim();
  return trimmed && trimmed !== "transparent" ? trimmed : fallback;
}

/** Read the same semantic colors used by the surrounding Backplane surface. */
export function readPanelizationTheme(
  element: Element = document.documentElement,
): PanelizationTheme {
  const styles = getComputedStyle(element);
  const accent = cssColor(styles.getPropertyValue("--primary"), "");
  return {
    background: cssColor(styles.getPropertyValue("--background"), FALLBACK_THEME.background),
    foreground: cssColor(styles.getPropertyValue("--foreground"), FALLBACK_THEME.foreground),
    muted: cssColor(styles.getPropertyValue("--muted-foreground"), FALLBACK_THEME.muted),
    accent: cssColor(accent || styles.getPropertyValue("--accent"), FALLBACK_THEME.accent),
    highlight: cssColor(
      styles.getPropertyValue("--design-highlight"),
      accent || cssColor(styles.getPropertyValue("--accent"), FALLBACK_THEME.highlight),
    ),
  };
}

/**
 * KiCad's SVG exporter emits a fixed palette. Re-map that palette at the
 * boundary so the image remains readable when Backplane switches themes.
 * The source colors are intentionally explicit: they are stable KiCad plot
 * colors, while arbitrary user artwork colors should remain untouched.
 */
export function themePanelizationSvg(
  svg: string,
  theme: PanelizationTheme = readPanelizationTheme(),
): string {
  const replacements: Record<string, string> = {
    "#000000": theme.foreground,
    "#161616": theme.foreground,
    "#FFFFFF": theme.background,
    "#DCDCDC": theme.muted,
    "#96A0AA": theme.muted,
    "#7EB8DA": theme.accent,
    "#D4A574": theme.accent,
    "#C9A57C": theme.accent,
    "#DCB4AA": theme.accent,
    "#E07A5F": theme.highlight,
  };
  return svg.replace(/#[0-9A-Fa-f]{6}/g, (color) => replacements[color.toUpperCase()] ?? color);
}
