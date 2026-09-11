import { useEffect, useState } from "react";
import { preparePanelizationDetail } from "./panelizationDetail";

type Camera = { scale: number; x: number; y: number };
type Size = { width: number; height: number };

/** Only the visible region gets a new vector render; the overview handles motion. */
export function PanelizationDetailLayer({
  svg,
  camera,
  viewport,
  image,
  fit,
  minScale = 4,
}: {
  svg: string;
  camera: Camera;
  viewport: Size;
  image: Size;
  fit: number;
  minScale?: number;
}) {
  const [index, setIndex] = useState<ReturnType<typeof preparePanelizationDetail>>();
  const [detail, setDetail] = useState<{ key: string; url: string }>();
  const key = JSON.stringify([camera, viewport, image, fit]);
  useEffect(() => {
    try {
      setIndex(preparePanelizationDetail(svg));
    } catch {
      setIndex(undefined);
    }
  }, [svg]);
  useEffect(() => {
    if (!index || viewport.width <= 1 || viewport.height <= 1 || camera.scale < minScale) return;
    let alive = true;
    let url: string | undefined;
    const timer = setTimeout(() => {
      const box = index.viewBox;
      const scale =
        Math.min(image.width / box.width, image.height / box.height) * fit * camera.scale;
      const rect = {
        x: box.x + box.width / 2 - (viewport.width / 2 + camera.x) / scale,
        y: box.y + box.height / 2 - (viewport.height / 2 + camera.y) / scale,
        width: viewport.width / scale,
        height: viewport.height / scale,
      };
      const dpr = Math.min(window.devicePixelRatio || 1, 3);
      const crop = index.crop(rect, {
        width: Math.ceil(viewport.width * dpr),
        height: Math.ceil(viewport.height * dpr),
      });
      url = URL.createObjectURL(new Blob([crop], { type: "image/svg+xml" }));
      const next = new Image();
      next.src = url;
      void next.decode().then(
        () => {
          if (alive) setDetail({ key, url: url! });
        },
        () => {
          /* The overview remains available if detail decoding fails. */
        },
      );
    }, 180);
    return () => {
      alive = false;
      clearTimeout(timer);
      if (url) URL.revokeObjectURL(url);
    };
  }, [index, key, camera, viewport, image, fit, minScale]);
  if (camera.scale < minScale || !detail || detail.key !== key) return null;
  return (
    <img
      className="panelization-detail"
      src={detail.url}
      alt=""
      aria-hidden="true"
      draggable={false}
      style={{
        position: "absolute",
        inset: 0,
        width: viewport.width,
        height: viewport.height,
        pointerEvents: "none",
        background: "var(--background)",
      }}
    />
  );
}
