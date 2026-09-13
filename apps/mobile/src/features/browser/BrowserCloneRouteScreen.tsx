import { useAtomRefresh, useAtomValue } from "@effect/atom-react";
import { AsyncResult } from "effect/unstable/reactivity";
import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { AppState, Pressable, ScrollView, StatusBar, View } from "react-native";
import { useSafeAreaInsets } from "react-native-safe-area-context";
import { useIsFocused, useNavigation, type StaticScreenProps } from "@react-navigation/native";
import { StackActions } from "@react-navigation/native";
import {
  EnvironmentId,
  ThreadId,
  type PreviewAutomationFrame,
  type PreviewCloneInput,
} from "@backplane/contracts";
import { createBrowserCloneSession } from "@backplane/client-runtime/browser-clone-session";
import { squashAtomCommandFailure } from "@backplane/client-runtime/state/runtime";
import { BrowserCloneViewer, type BrowserCloneTransport } from "./BrowserCloneViewer";
import { previewEnvironment } from "../../state/preview";
import { AppText } from "../../components/AppText";
import { useAtomCommand } from "../../state/use-atom-command";

type Props = StaticScreenProps<{ readonly environmentId: string; readonly threadId: string }>;

export function BrowserCloneRouteScreen({ route }: Props) {
  const insets = useSafeAreaInsets();
  const navigation = useNavigation();
  const focused = useIsFocused();
  const environmentId = EnvironmentId.make(route.params.environmentId);
  const threadId = ThreadId.make(route.params.threadId);
  const listAtom = previewEnvironment.list({ environmentId, input: { threadId } });
  const list = useAtomValue(listAtom);
  const refreshList = useAtomRefresh(listAtom);
  const event = useAtomValue(previewEnvironment.events({ environmentId, input: {} }));
  useEffect(() => {
    if (focused) refreshList();
  }, [focused, refreshList]);
  useEffect(() => {
    if (AsyncResult.isSuccess(event) && event.value.threadId === threadId) refreshList();
  }, [event, threadId, refreshList]);
  const invoke = useAtomCommand(previewEnvironment.cloneInvoke, { reportFailure: false });
  const [selectedTab, setSelectedTab] = useState<string | null>(null);
  const [frame, setFrame] = useState<PreviewAutomationFrame | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [active, setActive] = useState(AppState.currentState !== "background");
  const [generation, setGeneration] = useState(0);
  const sessionRef = useRef<ReturnType<typeof createBrowserCloneSession> | null>(null);
  const failedRef = useRef(false);
  const tabs = AsyncResult.isSuccess(list) ? list.value.sessions : [];
  const backToThread = useCallback(
    () =>
      navigation.dispatch(
        StackActions.popTo("Thread", {
          environmentId: String(environmentId),
          threadId: String(threadId),
        }),
      ),
    [environmentId, navigation, threadId],
  );
  const tabId = tabs.some((tab) => tab.tabId === selectedTab)
    ? selectedTab
    : (tabs[0]?.tabId ?? null);
  useEffect(() => {
    const subscription = AppState.addEventListener("change", (state) =>
      // iOS permission prompts are inactive, but their pending clipboard action
      // still needs this session when the prompt returns.
      setActive(state !== "background"),
    );
    return () => subscription.remove();
  }, []);
  useEffect(() => {
    setFrame(null);
    setError(null);
    failedRef.current = false;
    if (!tabId || !active || !focused) return;
    const session = createBrowserCloneSession(
      {
        environmentId,
        threadId,
        tabId,
        cloneId: `mobile-${Date.now()}-${Math.random().toString(36).slice(2)}`,
      },
      async (input) => {
        const result = await invoke({ environmentId, input });
        if (result._tag === "Failure") throw squashAtomCommandFailure(result);
        return result.value;
      },
    );
    sessionRef.current = session;
    let stopped = false;
    let timer: ReturnType<typeof setTimeout> | undefined;
    const capture = async () => {
      if (stopped || failedRef.current) return;
      try {
        const next = await session.capture();
        if (!stopped && next) setFrame(next);
      } catch {
        if (!stopped) {
          failedRef.current = true;
          setError("The desktop browser is unavailable. Keep its tab open and reconnect.");
        }
      }
      if (!stopped && !failedRef.current) timer = setTimeout(() => void capture(), 250);
    };
    void capture();
    return () => {
      stopped = true;
      clearTimeout(timer);
      session.dispose();
      if (sessionRef.current === session) sessionRef.current = null;
    };
  }, [active, focused, environmentId, threadId, tabId, generation, invoke]);
  const failed = useCallback((session: ReturnType<typeof createBrowserCloneSession>) => {
    if (sessionRef.current === session) {
      failedRef.current = true;
      setError("Browser input failed. Reconnect before continuing.");
    }
  }, []);
  const send = useCallback(
    async (input: PreviewCloneInput) => {
      const session = sessionRef.current;
      if (!session || failedRef.current) return null;
      try {
        return await session.send(input);
      } catch {
        failed(session);
        return null;
      }
    },
    [failed],
  );
  const transport = useMemo<BrowserCloneTransport>(
    () => ({
      gesture: (input) => {
        const session = sessionRef.current;
        if (session && !failedRef.current) void session.gesture(input).catch(() => failed(session));
      },
      text: async (text) => {
        if (tabId) await send({ tabId, action: "text", text });
      },
      key: async (key) => {
        if (tabId) await send({ tabId, action: "key", key });
      },
      copy: async () => {
        if (tabId) {
          const result = await send({ tabId, action: "clipboardCopy" });
          if (result && "clipboard" in result) return result.clipboard;
        }
        throw new Error("Unable to copy the desktop selection.");
      },
      paste: async (text) => {
        if (tabId) await send({ tabId, action: "clipboardPaste", text });
      },
      back: async () => {
        if (tabId) await send({ tabId, action: "back" });
      },
      forward: async () => {
        if (tabId) await send({ tabId, action: "forward" });
      },
    }),
    [failed, send, tabId],
  );
  const retry = () => {
    refreshList();
    setGeneration((value) => value + 1);
  };
  if (!tabId || error || AsyncResult.isFailure(list))
    return (
      <View className="flex-1 items-center justify-center gap-4 bg-screen px-8">
        <AppText className="text-center text-base text-foreground">
          {error ??
            (AsyncResult.isFailure(list)
              ? "Unable to list desktop browser tabs."
              : AsyncResult.isInitial(list)
                ? "Loading desktop browser tabs…"
                : "Open a browser tab in this thread on the desktop, then return here.")}
        </AppText>
        <Pressable
          accessibilityRole="button"
          onPress={retry}
          className="border border-border px-5 py-3"
        >
          <AppText className="text-foreground">Reconnect</AppText>
        </Pressable>
        <Pressable
          accessibilityRole="button"
          accessibilityLabel="Back to thread"
          onPress={backToThread}
          className="border border-border px-5 py-3"
        >
          <AppText className="text-foreground">Back to thread</AppText>
        </Pressable>
      </View>
    );
  return (
    <View
      style={{
        flex: 1,
        backgroundColor: "#111",
        paddingTop: insets.top,
        paddingLeft: insets.left,
        paddingRight: insets.right,
      }}
    >
      <StatusBar barStyle="light-content" />
      <View className="shrink-0 border-b border-white/10">
        <View className="flex-row items-center justify-between px-2 pt-2">
          <Pressable
            accessibilityRole="button"
            accessibilityLabel="Back to thread"
            onPress={backToThread}
            className="min-h-11 justify-center px-3"
          >
            <AppText className="text-white">Back to thread</AppText>
          </Pressable>
        </View>
        <ScrollView
          horizontal
          style={{ flexGrow: 0 }}
          showsHorizontalScrollIndicator={false}
          contentContainerStyle={{ padding: 8, gap: 8 }}
        >
          {tabs.map((tab) => (
            <Pressable
              key={tab.tabId}
              accessibilityRole="tab"
              accessibilityState={{ selected: tab.tabId === tabId }}
              onPress={() => setSelectedTab(tab.tabId)}
              className={`max-w-64 border px-3 py-2 ${tab.tabId === tabId ? "border-white/50 bg-white/10" : "border-white/10"}`}
            >
              <AppText numberOfLines={1} className="text-white">
                {tab.navStatus._tag === "Idle"
                  ? "New tab"
                  : tab.navStatus.title || tab.navStatus.url}
              </AppText>
            </Pressable>
          ))}
        </ScrollView>
      </View>
      <BrowserCloneViewer
        key={`${tabId}:${generation}`}
        frame={frame}
        transport={transport}
        canGoBack={frame?.canGoBack ?? tabs.find((tab) => tab.tabId === tabId)?.canGoBack ?? false}
        canGoForward={
          frame?.canGoForward ?? tabs.find((tab) => tab.tabId === tabId)?.canGoForward ?? false
        }
        onDone={backToThread}
      />
    </View>
  );
}
