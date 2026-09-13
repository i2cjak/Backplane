"use client";

import {
  cloneImageRect,
  createCloneGestureController,
  type CloneGestureInput,
} from "@backplane/client-runtime/browser-clone-gestures";
import type { PreviewAutomationFrame } from "@backplane/contracts";
import {
  Clipboard,
  Keyboard,
  MoreHorizontal,
  MousePointer2,
  LocateFixed,
  Maximize,
  HelpCircle,
  ArrowLeft,
  ArrowRight,
} from "lucide-react";
import { useEffect, useRef, useState, type PointerEvent as ReactPointerEvent } from "react";
import { Button } from "~/components/ui/button";
import {
  Dialog,
  DialogClose,
  DialogDescription,
  DialogPopup,
  DialogTitle,
} from "~/components/ui/dialog";

interface Props {
  readonly frame: PreviewAutomationFrame | null;
  readonly error: string | null;
  readonly onRetry: () => void;
  readonly onGesture: (gesture: CloneGestureInput) => void;
  readonly onText: (text: string) => Promise<void>;
  readonly onKey: (key: string) => Promise<void>;
  readonly onCopy: () => Promise<string>;
  readonly onPaste: (text: string) => Promise<void>;
  readonly onDone: () => void;
  readonly canGoBack: boolean;
  readonly canGoForward: boolean;
  readonly onBack: () => Promise<void>;
  readonly onForward: () => Promise<void>;
}
const HELP = [
  ["Back and Forward", "Move through the desktop browser tab's history."],
  ["Scroll", "Drag with two fingers."],
  ["Click and drag", "Tap to click where you tapped. Drag with one finger."],
  ["Right-click", "Tap with two fingers, or press and hold, then release."],
  ["Zoom", "Pinch to zoom. When zoomed in, two fingers pan instead of scrolling."],
  [
    "Type and clipboard",
    "Use the bottom bar to type, copy the desktop selection, or paste text from your phone.",
  ],
  [
    "Trackpad mode",
    "Turn on in the menu. Move a finger to move the pointer; tap to click. Double-tap and hold to drag. Recenter if it drifts.",
  ],
  ["Done", "Close this view and leave the desktop browser running."],
];

export function BrowserCloneSurface(props: Props) {
  const [dialog, setDialog] = useState<"help" | "typing" | "clipboard" | "menu" | null>(null);
  const [draft, setDraft] = useState("");
  const [actionError, setActionError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [surface, setSurface] = useState({ width: 1, height: 1 });
  const [, redraw] = useState(0);
  const surfaceRef = useRef<HTMLDivElement>(null);
  const callbackRef = useRef(props.onGesture);
  useEffect(() => {
    callbackRef.current = props.onGesture;
  }, [props.onGesture]);
  const [controller] = useState(() =>
    createCloneGestureController((gesture) => callbackRef.current(gesture)),
  );
  const frame = props.frame;
  const viewportWidth = frame?.viewportWidth ?? 1;
  const viewportHeight = frame?.viewportHeight ?? 1;
  useEffect(() => {
    const element = surfaceRef.current;
    if (!element) return;
    const resize = () =>
      setSurface({
        width: Math.max(1, element.clientWidth),
        height: Math.max(1, element.clientHeight),
      });
    const observer = new ResizeObserver(resize);
    observer.observe(element);
    resize();
    return () => observer.disconnect();
  }, []);
  useEffect(() => {
    controller.setLayout({ ...surface, viewportWidth, viewportHeight });
    redraw((n) => n + 1);
  }, [controller, surface, viewportWidth, viewportHeight]);
  useEffect(() => {
    const cancel = () => {
      controller.cancel();
      redraw((n) => n + 1);
    };
    document.addEventListener("visibilitychange", cancel);
    return () => {
      document.removeEventListener("visibilitychange", cancel);
      controller.cancel();
    };
  }, [controller]);
  useEffect(() => {
    if (props.error) controller.cancel();
  }, [controller, props.error]);
  useEffect(() => {
    const element = surfaceRef.current;
    if (!element || !frame || props.error) return;
    const wheel = (event: WheelEvent) => {
      event.preventDefault();
      const rect = element.getBoundingClientRect();
      const multiplier = event.deltaMode === 1 ? 16 : event.deltaMode === 2 ? viewportHeight : 1;
      controller.wheel(
        { x: event.clientX - rect.left, y: event.clientY - rect.top },
        event.deltaX * multiplier,
        event.deltaY * multiplier,
      );
    };
    element.addEventListener("wheel", wheel, { passive: false });
    return () => element.removeEventListener("wheel", wheel);
  }, [controller, Boolean(frame), props.error, viewportHeight]);
  const local = (event: ReactPointerEvent<HTMLDivElement>) => {
    const rect = event.currentTarget.getBoundingClientRect();
    return { x: event.clientX - rect.left, y: event.clientY - rect.top };
  };
  const rect = cloneImageRect(
    { ...surface, viewportWidth, viewportHeight },
    controller.presentation,
  );
  const run = async (action: () => Promise<void>) => {
    setBusy(true);
    setActionError(null);
    try {
      await action();
    } catch (error) {
      setActionError(error instanceof Error ? error.message : "Unable to complete this action.");
    } finally {
      setBusy(false);
    }
  };
  const open = (next: typeof dialog) => {
    controller.cancel();
    setActionError(null);
    setDialog(next);
  };
  return (
    <div className="flex min-h-0 flex-1 flex-col bg-[#111] text-white" data-browser-clone>
      <div
        ref={surfaceRef}
        className="relative min-h-0 flex-1 touch-none select-none overflow-hidden"
        role="application"
        aria-label="Desktop browser clone"
        onPointerDown={(event) => {
          if (!frame || props.error) return;
          if (event.button === 2) {
            controller.rightClick(local(event));
            return;
          }
          event.currentTarget.setPointerCapture(event.pointerId);
          controller.down(event.pointerId, local(event), event.timeStamp);
          redraw((n) => n + 1);
        }}
        onPointerMove={(event) => {
          if (!event.currentTarget.hasPointerCapture(event.pointerId)) return;
          controller.move(event.pointerId, local(event));
          redraw((n) => n + 1);
        }}
        onPointerUp={(event) => {
          controller.up(event.pointerId, event.timeStamp);
          redraw((n) => n + 1);
        }}
        onPointerCancel={() => {
          controller.cancel();
          redraw((n) => n + 1);
        }}
        onContextMenu={(event) => event.preventDefault()}
      >
        {frame ? (
          <img
            className="pointer-events-none absolute max-w-none"
            style={{ left: rect.x, top: rect.y, width: rect.width, height: rect.height }}
            src={`data:${frame.mimeType};base64,${frame.data}`}
            alt="Desktop browser view"
            draggable={false}
          />
        ) : (
          <div className="flex h-full items-center justify-center p-6 text-sm text-white/60">
            Connecting to the desktop browser…
          </div>
        )}
        {frame && controller.presentation.trackpad ? (
          <MousePointer2
            className="pointer-events-none absolute size-6 fill-black stroke-white"
            style={{
              left: rect.x + controller.presentation.cursor.x * rect.scale,
              top: rect.y + controller.presentation.cursor.y * rect.scale,
            }}
          />
        ) : null}
        {props.error ? (
          <div className="absolute inset-0 flex flex-col items-center justify-center gap-4 bg-black/90 p-6 text-center">
            <p role="alert" className="text-sm">
              {props.error}
            </p>
            <Button onClick={props.onRetry}>Reconnect</Button>
          </div>
        ) : null}
      </div>
      <div className="flex shrink-0 items-center justify-around border-t border-white/10 bg-[#171717] py-2 pb-[max(0.5rem,env(safe-area-inset-bottom))]">
        <Button
          variant="ghost"
          size="icon-lg"
          aria-label="Back"
          disabled={!frame || !!props.error || !props.canGoBack}
          onClick={() => void run(props.onBack)}
        >
          <ArrowLeft />
        </Button>
        <Button
          variant="ghost"
          size="icon-lg"
          aria-label="Forward"
          disabled={!frame || !!props.error || !props.canGoForward}
          onClick={() => void run(props.onForward)}
        >
          <ArrowRight />
        </Button>
        <Button
          variant="ghost"
          size="icon-lg"
          aria-label="Keyboard"
          disabled={!frame || !!props.error}
          onClick={() => open("typing")}
        >
          <Keyboard />
        </Button>
        <Button
          variant="ghost"
          size="icon-lg"
          aria-label="Clipboard"
          disabled={!frame || !!props.error}
          onClick={() => open("clipboard")}
        >
          <Clipboard />
        </Button>
        <Button
          variant="ghost"
          size="icon-lg"
          aria-label="Browser controls"
          onClick={() => open("menu")}
        >
          <MoreHorizontal />
        </Button>
        <Button variant="ghost" aria-label="Back to thread" onClick={props.onDone}>
          Done
        </Button>
      </div>
      <Dialog
        open={dialog !== null}
        onOpenChange={(value) => {
          if (!value) setDialog(null);
        }}
      >
        <DialogPopup className="max-h-[85dvh] overflow-y-auto border-white/10 bg-[#171717] text-white">
          <DialogTitle>
            {dialog === "help"
              ? "Using the Computer"
              : dialog === "typing"
                ? "Type into browser"
                : dialog === "clipboard"
                  ? "Clipboard"
                  : "Browser controls"}
          </DialogTitle>
          <DialogDescription className="text-white/60">
            {dialog === "typing"
              ? "Select a field in the desktop page, then send text or a key."
              : dialog === "clipboard"
                ? "Copy the selected page text or paste text into the focused desktop field."
                : "Control the browser running on your desktop."}
          </DialogDescription>
          {dialog === "help" ? (
            <div className="mt-5 space-y-3">
              {HELP.map(([title, detail]) => (
                <div key={title} className="border border-white/10 bg-white/5 p-4">
                  <p className="text-base">{title}</p>
                  <p className="mt-1 text-sm text-white/60">{detail}</p>
                </div>
              ))}
            </div>
          ) : null}
          {dialog === "menu" ? (
            <div className="mt-4 flex flex-col gap-2">
              <Button
                variant="outline"
                aria-pressed={controller.presentation.trackpad}
                onClick={() => {
                  controller.setTrackpad(!controller.presentation.trackpad);
                  redraw((n) => n + 1);
                }}
              >
                <MousePointer2 />
                {controller.presentation.trackpad ? "Turn off trackpad" : "Trackpad mode"}
              </Button>
              <Button
                variant="outline"
                onClick={() => {
                  controller.recenter();
                  redraw((n) => n + 1);
                }}
              >
                <LocateFixed />
                Recenter pointer
              </Button>
              <Button
                variant="outline"
                onClick={() => {
                  controller.resetZoom();
                  redraw((n) => n + 1);
                }}
              >
                <Maximize />
                Fit view
              </Button>
              <Button variant="outline" onClick={() => open("help")}>
                <HelpCircle />
                Gesture help
              </Button>
            </div>
          ) : null}
          {dialog === "typing" ? (
            <div className="mt-4 space-y-3">
              <textarea
                aria-label="Text to send"
                autoFocus
                maxLength={64000}
                value={draft}
                onChange={(event) => setDraft(event.target.value)}
                className="min-h-24 w-full border border-white/20 bg-black p-3 text-base text-white"
              />
              <Button
                disabled={busy || !draft}
                onClick={() =>
                  void run(async () => {
                    await props.onText(draft);
                    setDraft("");
                  })
                }
              >
                Send text
              </Button>
              <div className="flex flex-wrap gap-2">
                {["Enter", "Backspace", "Tab", "Escape"].map((key) => (
                  <Button
                    key={key}
                    variant="outline"
                    disabled={busy}
                    onClick={() => void run(() => props.onKey(key))}
                  >
                    {key}
                  </Button>
                ))}
              </div>
            </div>
          ) : null}
          {dialog === "clipboard" ? (
            <div className="mt-4 flex flex-col gap-2">
              <Button
                disabled={busy}
                onClick={() =>
                  void run(async () => {
                    const text = await props.onCopy();
                    if (!text) throw new Error("Select text in the desktop page first.");
                    await navigator.clipboard.writeText(text);
                  })
                }
              >
                Copy to phone
              </Button>
              <Button
                disabled={busy}
                onClick={() =>
                  void run(async () => {
                    const text = await navigator.clipboard.readText();
                    if (text.length > 64000)
                      throw new Error("Paste up to 64,000 characters at once.");
                    await props.onPaste(text);
                  })
                }
              >
                Paste from phone
              </Button>
            </div>
          ) : null}
          {actionError ? (
            <p role="alert" className="mt-3 text-sm text-red-300">
              {actionError}
            </p>
          ) : null}
          <DialogClose
            render={
              <Button variant="ghost" className="mt-5 w-full">
                Close
              </Button>
            }
          />
        </DialogPopup>
      </Dialog>
    </div>
  );
}
