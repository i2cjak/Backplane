export interface ClonePoint {
  readonly x: number;
  readonly y: number;
}
export interface CloneLayout {
  readonly width: number;
  readonly height: number;
  readonly viewportWidth: number;
  readonly viewportHeight: number;
}
export type CloneGestureInput =
  | { readonly type: "down" | "move" | "up"; readonly point: ClonePoint }
  | { readonly type: "click" | "rightClick"; readonly point: ClonePoint }
  | {
      readonly type: "scroll";
      readonly point: ClonePoint;
      readonly deltaX: number;
      readonly deltaY: number;
    };
export interface ClonePresentation {
  readonly zoom: number;
  readonly pan: ClonePoint;
  readonly cursor: ClonePoint;
  readonly trackpad: boolean;
}
const clamp = (n: number, low: number, high: number) => Math.max(low, Math.min(high, n));
const distance = (a: ClonePoint, b: ClonePoint) => Math.hypot(a.x - b.x, a.y - b.y);
const middle = (a: ClonePoint, b: ClonePoint) => ({ x: (a.x + b.x) / 2, y: (a.y + b.y) / 2 });

/** Fit the desktop CSS viewport, then apply phone-only zoom and pan. */
export function cloneImageRect(
  layout: CloneLayout,
  presentation: Pick<ClonePresentation, "zoom" | "pan">,
) {
  const scale =
    Math.min(layout.width / layout.viewportWidth, layout.height / layout.viewportHeight) *
    presentation.zoom;
  const width = layout.viewportWidth * scale;
  const height = layout.viewportHeight * scale;
  return {
    x: (layout.width - width) / 2 + presentation.pan.x,
    y: (layout.height - height) / 2 + presentation.pan.y,
    width,
    height,
    scale,
  };
}

/** One controller per visible viewer; emit input in desktop CSS pixels. */
export function createCloneGestureController(emit: (input: CloneGestureInput) => void) {
  let layout: CloneLayout = { width: 1, height: 1, viewportWidth: 1, viewportHeight: 1 };
  let presentation: ClonePresentation = {
    zoom: 1,
    pan: { x: 0, y: 0 },
    cursor: { x: 0, y: 0 },
    trackpad: false,
  };
  const touches = new Map<number, ClonePoint>();
  let start: ClonePoint | null = null;
  let startedAt = 0;
  let lastTap = -Infinity;
  let moved = false;
  let pressed = false;
  let multiple = false;
  let pairStart: { center: ClonePoint; distance: number; zoom: number; pan: ClonePoint } | null =
    null;
  let pairMode: "pinch" | "scroll" | "pan" | null = null;
  const bounded = (point: ClonePoint) => ({
    x: clamp(point.x, 0, layout.viewportWidth - 1),
    y: clamp(point.y, 0, layout.viewportHeight - 1),
  });
  const toDesktop = (point: ClonePoint, allowOutside = false): ClonePoint | null => {
    const rect = cloneImageRect(layout, presentation);
    if (
      !allowOutside &&
      (point.x < rect.x ||
        point.y < rect.y ||
        point.x > rect.x + rect.width ||
        point.y > rect.y + rect.height)
    )
      return null;
    return bounded({ x: (point.x - rect.x) / rect.scale, y: (point.y - rect.y) / rect.scale });
  };
  const constrainPan = (pan: ClonePoint, zoom = presentation.zoom) => {
    const rect = cloneImageRect(layout, { zoom, pan: { x: 0, y: 0 } });
    return {
      x: clamp(
        pan.x,
        -Math.max(0, (rect.width - layout.width) / 2),
        Math.max(0, (rect.width - layout.width) / 2),
      ),
      y: clamp(
        pan.y,
        -Math.max(0, (rect.height - layout.height) / 2),
        Math.max(0, (rect.height - layout.height) / 2),
      ),
    };
  };
  const release = () => {
    if (pressed) emit({ type: "up", point: presentation.cursor });
    pressed = false;
  };
  const cancel = () => {
    release();
    touches.clear();
    start = null;
    pairStart = null;
    multiple = false;
    lastTap = -Infinity;
  };
  return {
    get presentation() {
      return presentation;
    },
    setLayout(next: CloneLayout) {
      layout = next;
      presentation = {
        ...presentation,
        cursor: bounded(presentation.cursor),
        pan: constrainPan(presentation.pan),
      };
    },
    setTrackpad(trackpad: boolean) {
      cancel();
      presentation = {
        ...presentation,
        trackpad,
        cursor: { x: layout.viewportWidth / 2, y: layout.viewportHeight / 2 },
      };
    },
    recenter() {
      presentation = {
        ...presentation,
        cursor: { x: layout.viewportWidth / 2, y: layout.viewportHeight / 2 },
      };
    },
    resetZoom() {
      presentation = { ...presentation, zoom: 1, pan: { x: 0, y: 0 } };
    },
    cancel,
    down(id: number, point: ClonePoint, now: number) {
      touches.set(id, point);
      if (touches.size === 1) {
        start = point;
        startedAt = now;
        moved = false;
        multiple = false;
        pairMode = null;
        if (presentation.trackpad && now - lastTap < 300) {
          pressed = true;
          emit({ type: "down", point: presentation.cursor });
        }
      } else {
        release();
        multiple = true;
        const [a, b] = [...touches.values()];
        if (a && b)
          pairStart = {
            center: middle(a, b),
            distance: distance(a, b),
            zoom: presentation.zoom,
            pan: presentation.pan,
          };
      }
    },
    move(id: number, point: ClonePoint) {
      const previous = touches.get(id);
      if (!previous) return;
      const oldPair = [...touches.values()];
      touches.set(id, point);
      if (multiple) {
        const [a, b] = [...touches.values()];
        const [oldA, oldB] = oldPair;
        if (!a || !b || !oldA || !oldB || !pairStart) return;
        const center = middle(a, b);
        const separation = distance(a, b);
        if (!pairMode) {
          if (Math.abs(separation - pairStart.distance) > 10) pairMode = "pinch";
          else if (distance(center, pairStart.center) > 5)
            pairMode = presentation.zoom > 1 ? "pan" : "scroll";
        }
        if (!pairMode) return;
        moved = true;
        if (pairMode === "pinch") {
          const zoom = clamp((pairStart.zoom * separation) / Math.max(1, pairStart.distance), 1, 4);
          presentation = { ...presentation, zoom, pan: constrainPan(presentation.pan, zoom) };
        } else if (pairMode === "pan") {
          presentation = {
            ...presentation,
            pan: constrainPan({
              x: pairStart.pan.x + center.x - pairStart.center.x,
              y: pairStart.pan.y + center.y - pairStart.center.y,
            }),
          };
        } else {
          const oldCenter = middle(oldA, oldB);
          const rect = cloneImageRect(layout, presentation);
          emit({
            type: "scroll",
            point: toDesktop(center, true)!,
            deltaX: (oldCenter.x - center.x) / rect.scale,
            deltaY: (oldCenter.y - center.y) / rect.scale,
          });
        }
        return;
      }
      if (!start) return;
      if (distance(start, point) > 5) moved = true;
      if (presentation.trackpad) {
        const scale = cloneImageRect(layout, presentation).scale;
        presentation = {
          ...presentation,
          cursor: bounded({
            x: presentation.cursor.x + (point.x - previous.x) / scale,
            y: presentation.cursor.y + (point.y - previous.y) / scale,
          }),
        };
        emit({ type: "move", point: presentation.cursor });
      } else if (moved) {
        const origin = toDesktop(start);
        if (!origin) return;
        if (!pressed) {
          pressed = true;
          emit({ type: "down", point: origin });
        }
        presentation = { ...presentation, cursor: toDesktop(point, true)! };
        emit({ type: "move", point: presentation.cursor });
      }
    },
    up(id: number, now: number) {
      if (!touches.has(id)) return;
      touches.delete(id);
      if (touches.size) return;
      if (pressed) release();
      else if (!moved && start) {
        const target = presentation.trackpad ? presentation.cursor : toDesktop(start);
        if (target) {
          emit({
            type: multiple || now - startedAt >= 500 ? "rightClick" : "click",
            point: target,
          });
          lastTap = multiple ? -Infinity : now;
        }
      }
      start = null;
      pairStart = null;
    },
    wheel(point: ClonePoint, deltaX: number, deltaY: number) {
      const target = toDesktop(point);
      if (target) emit({ type: "scroll", point: target, deltaX, deltaY });
    },
    rightClick(point: ClonePoint) {
      const target = toDesktop(point);
      if (target) emit({ type: "rightClick", point: target });
    },
  };
}
