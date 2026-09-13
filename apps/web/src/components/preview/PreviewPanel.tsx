"use client";

import { useAtomValue } from "@effect/atom-react";
import { AsyncResult } from "effect/unstable/reactivity";
import type { PreviewAnnotationPayload, ScopedThreadRef } from "@backplane/contracts";
import type { ComposerImageAttachment } from "~/composerDraftStore";
import { isPreviewSupportedInRuntime, useThreadPreviewState } from "~/previewStateStore";
import { useRightPanelStore } from "~/rightPanelStore";
import { previewEnvironment } from "~/state/preview";
import { PreviewPanelShell, type PreviewPanelMode } from "./PreviewPanelShell";
import { PreviewView } from "./PreviewView";
import { BrowserCloneSurface } from "./BrowserCloneSurface";
import { useBrowserClone } from "./useBrowserClone";
import { usePreviewSession } from "./usePreviewSession";
import { Button } from "~/components/ui/button";

interface Props {
  mode: PreviewPanelMode;
  threadRef: ScopedThreadRef;
  tabId?: string | null;
  configuredUrls?: ReadonlyArray<string> | undefined;
  visible: boolean;
  onSendAnnotation?: (
    annotation: PreviewAnnotationPayload,
    image: ComposerImageAttachment | null,
  ) => void;
}

function RemoteBrowserPanel({ threadRef, tabId: requestedTabId, visible }: Props) {
  usePreviewSession(threadRef);
  const state = useThreadPreviewState(threadRef);
  const list = useAtomValue(
    previewEnvironment.list({
      environmentId: threadRef.environmentId,
      input: { threadId: threadRef.threadId },
    }),
  );
  const tabs = Object.values(state.sessions);
  const tabId =
    requestedTabId && state.sessions[requestedTabId] ? requestedTabId : (tabs[0]?.tabId ?? null);
  const clone = useBrowserClone(threadRef, tabId, visible);
  const close = () => useRightPanelStore.getState().close(threadRef);
  if (!tabId)
    return (
      <div className="flex min-h-0 flex-1 flex-col items-center justify-center gap-4 p-6 text-center">
        <p className="text-sm text-muted-foreground">
          {AsyncResult.isFailure(list)
            ? "Unable to list desktop browser tabs. Check your environment connection."
            : AsyncResult.isInitial(list)
              ? "Loading desktop browser tabs…"
              : "Open a browser tab in this thread on the desktop, then select it here."}
        </p>
        <Button variant="outline" onClick={close}>
          Done
        </Button>
      </div>
    );
  return (
    <div className="flex min-h-0 flex-1 flex-col">
      <select
        aria-label="Desktop browser tab"
        className="w-full shrink-0 border-b bg-background px-3 py-2 text-sm"
        value={tabId}
        onChange={(event) =>
          useRightPanelStore.getState().openBrowser(threadRef, event.target.value)
        }
      >
        {tabs.map((tab) => (
          <option key={tab.tabId} value={tab.tabId}>
            {tab.navStatus._tag === "Idle" ? "New tab" : tab.navStatus.title || tab.navStatus.url}
          </option>
        ))}
      </select>
      <BrowserCloneSurface
        key={`${threadRef.environmentId}:${threadRef.threadId}:${tabId}`}
        frame={clone.frame}
        error={clone.error}
        onRetry={clone.retry}
        onGesture={clone.gesture}
        onDone={close}
        onText={async (text) => {
          await clone.send({ tabId, action: "text", text });
        }}
        onKey={async (key) => {
          await clone.send({ tabId, action: "key", key });
        }}
        onCopy={async () => {
          const result = await clone.send({ tabId, action: "clipboardCopy" });
          if (result && "clipboard" in result) return result.clipboard;
          throw new Error("Unable to copy the desktop selection.");
        }}
        onPaste={async (text) => {
          await clone.send({ tabId, action: "clipboardPaste", text });
        }}
      />
    </div>
  );
}

export function PreviewPanel(props: Props) {
  return (
    <PreviewPanelShell mode={props.mode}>
      {isPreviewSupportedInRuntime() ? (
        <PreviewView
          threadRef={props.threadRef}
          {...(props.tabId !== undefined ? { tabId: props.tabId } : {})}
          configuredUrls={props.configuredUrls}
          visible={props.visible}
          {...(props.onSendAnnotation ? { onSendAnnotation: props.onSendAnnotation } : {})}
        />
      ) : (
        <RemoteBrowserPanel {...props} />
      )}
    </PreviewPanelShell>
  );
}
