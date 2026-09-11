type Rect = { x: number; y: number; width: number; height: number };
type Node = {
  open: string;
  close: string;
  children: Node[];
  bounds?: Rect | undefined;
  raw?: string;
};
const numbers = (text: string) =>
  (text.match(/[-+]?(?:\d*\.)?\d+(?:e[-+]?\d+)?/gi) ?? []).map(Number);
const attribute = (tag: string, name: string) =>
  tag.match(new RegExp(`\\b${name}\\s*=\\s*["']([^"']*)["']`, "i"))?.[1];

function bounds(tag: string, name: string): Rect | undefined {
  if (attribute(tag, "transform")) return;
  if (name === "path") {
    const d = attribute(tag, "d") ?? "";
    // Curves, arcs and relative coordinates are retained conservatively.
    if (/[^MLZ\d\s.,+-]/.test(d)) return;
    const n = numbers(d);
    if (n.length < 2 || n.length % 2) return;
    let left = Infinity,
      top = Infinity,
      right = -Infinity,
      bottom = -Infinity;
    for (let i = 0; i < n.length; i += 2) {
      left = Math.min(left, n[i]!);
      right = Math.max(right, n[i]!);
      top = Math.min(top, n[i + 1]!);
      bottom = Math.max(bottom, n[i + 1]!);
    }
    return { x: left, y: top, width: right - left, height: bottom - top };
  }
  if (name === "circle") {
    const x = Number(attribute(tag, "cx") ?? 0),
      y = Number(attribute(tag, "cy") ?? 0),
      r = Number(attribute(tag, "r") ?? 0);
    return { x: x - r, y: y - r, width: 2 * r, height: 2 * r };
  }
}

/** Index KiCad's groups once. Retain inherited styles/transforms and cull only known geometry. */
export function preparePanelizationDetail(svg: string) {
  const root = svg.match(/<svg\b[^>]*>/i);
  const box = numbers(attribute(root?.[0] ?? "", "viewBox") ?? "");
  if (!root || box.length !== 4 || !box.every(Number.isFinite) || box[2]! <= 0 || box[3]! <= 0)
    throw new Error("Panelization SVG is missing a valid viewBox");
  const viewBox = { x: box[0]!, y: box[1]!, width: box[2]!, height: box[3]! };
  const tree: Node = { open: "", close: "", children: [] };
  const stack: { node: Node; start: number; transformed: boolean; name: string }[] = [
    { node: tree, start: 0, transformed: false, name: "root" },
  ];
  const body = svg.slice((root.index ?? 0) + root[0].length, svg.lastIndexOf("</svg>"));
  for (const match of body.matchAll(/<(\/?)([\w:.-]+)\b[^>]*>/g)) {
    const tag = match[0],
      name = match[2]!,
      closing = match[1] === "/";
    if (closing) {
      if (stack.length <= 1) continue;
      const entry = stack.pop()!;
      entry.node.close = tag;
      if (entry.name !== "g") entry.node.raw = body.slice(entry.start, match.index! + tag.length);
      if (
        ["title", "desc"].includes(entry.name) ||
        (entry.name === "text" && attribute(entry.node.open, "opacity") === "0")
      )
        entry.node.raw = "";
      continue;
    }
    const parent = stack[stack.length - 1]!;
    const transformed =
      parent.transformed ||
      Boolean(
        attribute(tag, "transform")
          ?.replace(/translate\(0 0\)\s*scale\(1 1\)/, "")
          .trim(),
      );
    const node: Node = {
      open: tag,
      close: "",
      children: [],
      bounds: transformed ? undefined : bounds(tag, name),
    };
    parent.node.children.push(node);
    if (!tag.endsWith("/>")) stack.push({ node, start: match.index!, transformed, name });
  }
  const render = (node: Node, rect: Rect): string => {
    const b = node.bounds;
    // Include a generous stroke margin; paths on the viewport boundary must survive.
    if (
      b &&
      (b.x > rect.x + rect.width + 2 ||
        b.x + b.width < rect.x - 2 ||
        b.y > rect.y + rect.height + 2 ||
        b.y + b.height < rect.y - 2)
    )
      return "";
    if (node.raw !== undefined) return node.raw;
    if (!node.children.length) return node.open + node.close;
    const children = node.children.map((child) => render(child, rect)).join("");
    return children ? node.open + children + node.close : "";
  };
  return {
    viewBox,
    crop(rect: Rect, pixels: { width: number; height: number }) {
      const attributes = root[0]
        .replace(/\s(?:viewBox|width|height)\s*=\s*(?:"[^"]*"|'[^']*')/gi, "")
        .slice(0, -1);
      const opening = `${attributes} width="${Math.max(1, Math.ceil(pixels.width))}" height="${Math.max(1, Math.ceil(pixels.height))}" viewBox="${rect.x} ${rect.y} ${rect.width} ${rect.height}">`;
      return opening + tree.children.map((node) => render(node, rect)).join("") + "</svg>";
    },
  };
}
