export type GerberPreset = "layer" | "copper" | "front" | "back" | "all";

export type GerberSection = "front" | "back" | "inner" | "board" | "drill" | "other";

export interface GerberLayerInfo {
  path: string;
  label: string;
  section: GerberSection;
  kind: string;
}
const layerSuffix =
  /(?:[-_.](?:F|B|In\d+)[-_.](?:Cu|SilkS|Silkscreen|Mask|Paste|Fab|CrtYd)|[-_.](?:User[_-]?\d+)|[-_.]Edge[-_.]Cuts|[-_.](?:PTH|NPTH))$/i;
export function gerberFamily(path: string): string {
  return path.replace(/\.[^./]+$/, "").replace(layerSuffix, "");
}
export function gerberLayer(path: string): string {
  const name = path.split("/").at(-1) ?? path;
  if (/(?:F[-_.]Cu(?:\.|$)|\.gtl$)/i.test(name)) return "front-copper";
  if (/(?:B[-_.]Cu(?:\.|$)|\.gbl$)/i.test(name)) return "back-copper";
  if (/(?:In\d+[-_.]Cu(?:\.|$)|\.g\d+$)/i.test(name)) return "inner-copper";
  if (/(?:F[-_.](?:SilkS|Silkscreen|Fab)(?:\.|$)|\.gto$)/i.test(name)) return "front-placement";
  if (/(?:B[-_.](?:SilkS|Silkscreen|Fab)(?:\.|$)|\.gbo$)/i.test(name)) return "back-placement";
  if (/(?:F[-_.]Paste(?:\.|$)|\.gtp$)/i.test(name)) return "front-paste";
  if (/(?:B[-_.]Paste(?:\.|$)|\.gbp$)/i.test(name)) return "back-paste";
  if (/(?:F[-_.]Mask(?:\.|$)|\.gts$)/i.test(name)) return "front-mask";
  if (/(?:B[-_.]Mask(?:\.|$)|\.gbs$)/i.test(name)) return "back-mask";
  if (/(?:Edge[-_.]Cuts\.|\.(?:gko|gm1)$)/i.test(name)) return "outline";
  if (/\.(?:drl|xln)$/i.test(name)) return "drill";
  return "other";
}

/** Short layer names keep the panel scannable; callers can use path for the full filename. */
export function gerberLayerInfo(path: string): GerberLayerInfo {
  const name = path.split("/").at(-1) ?? path;
  const layer = gerberLayer(path);
  const innerNumber = name.match(/In[-_.]?(\d+)[-_.]?Cu/i)?.[1] ?? name.match(/\.g(\d+)$/i)?.[1];
  const userNumber = name.match(/User[-_.]?(\d+)/i)?.[1];
  const label =
    layer === "front-copper"
      ? "Front copper"
      : layer === "back-copper"
        ? "Back copper"
        : layer === "inner-copper"
          ? `Inner ${innerNumber ?? ""} copper`.replace("  ", " ")
          : layer === "front-placement"
            ? /fab/i.test(name)
              ? "Front fab"
              : "Front silkscreen"
            : layer === "back-placement"
              ? /fab/i.test(name)
                ? "Back fab"
                : "Back silkscreen"
              : layer === "front-mask"
                ? "Front solder mask"
                : layer === "back-mask"
                  ? "Back solder mask"
                  : layer === "front-paste"
                    ? "Front solder paste"
                    : layer === "back-paste"
                      ? "Back solder paste"
                      : layer === "outline"
                        ? "Edge cuts"
                        : layer === "drill"
                          ? /NPTH/i.test(name)
                            ? "NPTH drills"
                            : "PTH drills"
                          : userNumber
                            ? `User ${userNumber}`
                            : name
                                .replace(/\.[a-z0-9]+$/i, "")
                                .replace(/[-_.]+/g, " ")
                                .trim();
  const section: GerberSection =
    layer === "drill"
      ? "drill"
      : layer === "outline"
        ? "board"
        : layer === "front-copper" ||
            layer === "front-placement" ||
            layer === "front-paste" ||
            layer === "front-mask"
          ? "front"
          : layer === "back-copper" ||
              layer === "back-placement" ||
              layer === "back-paste" ||
              layer === "back-mask"
            ? "back"
            : layer === "inner-copper"
              ? "inner"
              : "other";
  return { path, label: label || name, section, kind: layer };
}
export function gerberPresetPaths(
  paths: string[],
  selected: string,
  preset: GerberPreset,
): string[] {
  if (preset === "layer")
    return [
      selected,
      ...paths.filter(
        (path) =>
          path !== selected &&
          gerberFamily(path) === gerberFamily(selected) &&
          gerberLayer(path) === "outline",
      ),
    ];
  const family = gerberFamily(selected);
  return paths.filter((path) => {
    if (gerberFamily(path) !== family) return false;
    const layer = gerberLayer(path);
    if (preset === "all") return true;
    if (layer === "outline" || layer === "drill") return true;
    if (preset === "copper") return layer.endsWith("copper");
    return layer === `${preset}-placement` || layer === `${preset}-paste`;
  });
}
