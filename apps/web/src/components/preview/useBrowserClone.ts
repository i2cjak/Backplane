"use client";

import type {
  PreviewAutomationFrame,
  PreviewCloneInput,
  ScopedThreadRef,
} from "@backplane/contracts";
import { squashAtomCommandFailure } from "@backplane/client-runtime/state/runtime";
import { createBrowserCloneSession } from "@backplane/client-runtime/browser-clone-session";
import type { CloneGestureInput } from "@backplane/client-runtime/browser-clone-gestures";
import { useCallback, useEffect, useRef, useState } from "react";
import { previewEnvironment } from "~/state/preview";
import { useAtomCommand } from "~/state/use-atom-command";
import { createPreviewAutomationClientId } from "./previewAutomationClientId";

export function useBrowserClone(
  threadRef: ScopedThreadRef,
  tabId: string | null,
  visible: boolean,
) {
  const invoke = useAtomCommand(previewEnvironment.cloneInvoke, { reportFailure: false });
  const [generation, setGeneration] = useState(0);
  const [frame, setFrame] = useState<PreviewAutomationFrame | null>(null);
  const [error, setError] = useState<string | null>(null);
  const sessionRef = useRef<ReturnType<typeof createBrowserCloneSession> | null>(null);
  const failedRef = useRef(false);
  const { environmentId, threadId } = threadRef;
  useEffect(() => {
    setFrame(null);
    setError(null);
    failedRef.current = false;
    if (!visible || !tabId) return;
    const session = createBrowserCloneSession(
      { environmentId, threadId, tabId, cloneId: createPreviewAutomationClientId() },
      async (input) => {
        const result = await invoke({ environmentId, input });
        if (result._tag === "Failure") throw squashAtomCommandFailure(result);
        return result.value;
      },
    );
    sessionRef.current = session;
    let stopped = false;
    let fetching = false;
    let timer: ReturnType<typeof setTimeout> | undefined;
    const poll = async () => {
      if (stopped || fetching || failedRef.current || document.visibilityState !== "visible")
        return;
      fetching = true;
      try {
        const next = await session.capture();
        if (!stopped && next) setFrame(next);
      } catch {
        if (!stopped) {
          failedRef.current = true;
          setError("The desktop browser is unavailable. Keep its tab open and reconnect.");
        }
      } finally {
        fetching = false;
        if (!stopped && !failedRef.current && document.visibilityState === "visible")
          timer = setTimeout(() => void poll(), 250);
      }
    };
    const visibility = () => {
      clearTimeout(timer);
      if (document.visibilityState === "visible") void poll();
    };
    document.addEventListener("visibilitychange", visibility);
    void poll();
    return () => {
      stopped = true;
      clearTimeout(timer);
      document.removeEventListener("visibilitychange", visibility);
      session.dispose();
      if (sessionRef.current === session) sessionRef.current = null;
    };
  }, [environmentId, threadId, tabId, visible, generation, invoke]);
  const fail = useCallback((session: ReturnType<typeof createBrowserCloneSession>) => {
    if (sessionRef.current === session) {
      failedRef.current = true;
      setError("Browser input failed. Reconnect before continuing.");
    }
  }, []);
  const gesture = useCallback(
    (input: CloneGestureInput) => {
      const session = sessionRef.current;
      if (session && !failedRef.current) void session.gesture(input).catch(() => fail(session));
    },
    [fail],
  );
  const send = useCallback(
    async (input: PreviewCloneInput) => {
      const session = sessionRef.current;
      if (!session || failedRef.current) return null;
      try {
        return await session.send(input);
      } catch {
        fail(session);
        return null;
      }
    },
    [fail],
  );
  const retry = useCallback(() => setGeneration((value) => value + 1), []);
  return { frame, error, gesture, send, retry };
}
