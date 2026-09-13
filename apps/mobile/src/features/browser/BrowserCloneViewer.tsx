import * as Clipboard from "expo-clipboard";
import { useEffect, useMemo, useRef, useState } from "react";
import {
  Image,
  KeyboardAvoidingView,
  Modal,
  PanResponder,
  Platform,
  Pressable,
  ScrollView,
  TextInput,
  View,
  type GestureResponderEvent,
} from "react-native";
import { useSafeAreaInsets } from "react-native-safe-area-context";
import type { PreviewAutomationFrame } from "@backplane/contracts";
import { normalizePreviewUrl } from "@backplane/shared/preview";
import {
  cloneImageRect,
  createCloneGestureController,
  type CloneGestureInput,
} from "@backplane/client-runtime/browser-clone-gestures";
import { AppText } from "../../components/AppText";
import { SymbolView, type AppSymbolName } from "../../components/AppSymbol";

export interface BrowserCloneTransport {
  readonly gesture: (input: CloneGestureInput) => void;
  readonly text: (text: string) => Promise<void>;
  readonly key: (key: string) => Promise<void>;
  readonly copy: () => Promise<string>;
  readonly paste: (text: string) => Promise<void>;
  readonly back: () => Promise<void>;
  readonly forward: () => Promise<void>;
  readonly navigate: (url: string) => Promise<void>;
  readonly reload: () => Promise<void>;
}
interface Props {
  readonly frame: PreviewAutomationFrame | null;
  readonly transport: BrowserCloneTransport;
  readonly onDone: () => void;
  readonly canGoBack: boolean;
  readonly canGoForward: boolean;
}
const HELP = [
  ["Browser history", "Back and Forward", "Move through the desktop browser tab's history."],
  ["Moving around", "Scroll", "Drag with two fingers."],
  ["", "Click and drag", "Tap to click where you tapped. Drag with one finger."],
  ["", "Right-click", "Tap with two fingers, or press and hold, then release."],
  ["", "Zoom in", "Pinch to zoom. When zoomed in, two fingers pan instead of scrolling."],
  ["Typing and the clipboard", "Type", "Tap the keyboard button in the bottom bar."],
  ["", "Copy and paste", "Use the clipboard button for Copy to Phone and Paste from Phone."],
  [
    "When a pointer is easier",
    "Trackpad mode",
    "Turn on from the menu. Move a finger to move the pointer; tap to click. Double-tap and hold to drag. Recenter if it drifts.",
  ],
  ["Handing it back", "Done", "Close this view and leave the desktop browser running."],
];
function Action({
  label,
  onPress,
  disabled = false,
}: {
  label: string;
  onPress: () => void;
  disabled?: boolean;
}) {
  return (
    <Pressable
      accessibilityRole="button"
      disabled={disabled}
      onPress={onPress}
      className={`min-h-11 items-center justify-center border border-white/15 px-4 py-3 ${disabled ? "opacity-40" : ""}`}
    >
      <AppText className="text-white">{label}</AppText>
    </Pressable>
  );
}
function Tool({
  label,
  icon,
  onPress,
  disabled = false,
}: {
  label: string;
  icon: AppSymbolName;
  onPress: () => void;
  disabled?: boolean;
}) {
  return (
    <Pressable
      accessibilityRole="button"
      accessibilityLabel={label}
      disabled={disabled}
      onPress={onPress}
      className={`size-12 items-center justify-center ${disabled ? "opacity-40" : ""}`}
    >
      <SymbolView name={icon} size={24} tintColor="white" />
    </Pressable>
  );
}

export function BrowserCloneViewer({ frame, transport, onDone, canGoBack, canGoForward }: Props) {
  const insets = useSafeAreaInsets();
  const [dialog, setDialog] = useState<"help" | "keyboard" | "clipboard" | "menu" | null>(null);
  const [draft, setDraft] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [address, setAddress] = useState("");
  const editingAddress = useRef(false);
  const [surface, setSurface] = useState({ width: 1, height: 1 });
  const [, redraw] = useState(0);
  const transportRef = useRef(transport);
  const readyRef = useRef(false);
  useEffect(() => {
    transportRef.current = transport;
  }, [transport]);
  useEffect(() => {
    readyRef.current = frame !== null;
    if (!editingAddress.current) setAddress(frame?.url ?? "");
  }, [frame]);
  const touches = useRef(new Set<number>());
  const [controller] = useState(() =>
    createCloneGestureController((input) => transportRef.current.gesture(input)),
  );
  const viewportWidth = frame?.viewportWidth ?? 1;
  const viewportHeight = frame?.viewportHeight ?? 1;
  useEffect(() => {
    controller.setLayout({ ...surface, viewportWidth, viewportHeight });
    redraw((n) => n + 1);
  }, [controller, surface, viewportWidth, viewportHeight]);
  useEffect(() => {
    if (!frame) {
      controller.cancel();
      touches.current.clear();
    }
  }, [controller, Boolean(frame)]);
  useEffect(() => () => controller.cancel(), [controller]);
  const responder = useMemo(() => {
    const sync = (event: GestureResponderEvent) => {
      if (!readyRef.current) return;
      const next = new Set<number>();
      for (const touch of event.nativeEvent.touches) {
        const id = Number(touch.identifier);
        next.add(id);
        const point = { x: touch.locationX, y: touch.locationY };
        if (touches.current.has(id)) controller.move(id, point);
        else controller.down(id, point, event.nativeEvent.timestamp);
      }
      for (const id of touches.current)
        if (!next.has(id)) controller.up(id, event.nativeEvent.timestamp);
      touches.current = next;
      redraw((n) => n + 1);
    };
    const cancel = () => {
      controller.cancel();
      touches.current.clear();
      redraw((n) => n + 1);
    };
    return PanResponder.create({
      onStartShouldSetPanResponder: () => readyRef.current,
      onMoveShouldSetPanResponder: () => readyRef.current,
      onPanResponderGrant: sync,
      onPanResponderStart: sync,
      onPanResponderMove: sync,
      onPanResponderEnd: sync,
      onPanResponderRelease: sync,
      onPanResponderTerminate: cancel,
      onPanResponderTerminationRequest: () => true,
    });
  }, [controller]);
  const rect = cloneImageRect(
    { ...surface, viewportWidth, viewportHeight },
    controller.presentation,
  );
  const open = (next: typeof dialog) => {
    controller.cancel();
    touches.current.clear();
    setError(null);
    setDialog(next);
  };
  const run = async (action: () => Promise<void>) => {
    setBusy(true);
    setError(null);
    try {
      await action();
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : "Unable to complete this action.");
    } finally {
      setBusy(false);
    }
  };
  return (
    <View style={{ flex: 1, minHeight: 0, backgroundColor: "#111" }}>
      <View className="flex-row items-center gap-1 px-2 py-1">
        <TextInput
          accessibilityLabel="Browser address"
          value={address}
          onFocus={() => (editingAddress.current = true)}
          onBlur={() => {
            editingAddress.current = false;
            setAddress(frame?.url ?? "");
          }}
          onChangeText={setAddress}
          onSubmitEditing={(event) => {
            const submitted = event.nativeEvent.text;
            editingAddress.current = false;
            void run(() => transportRef.current.navigate(normalizePreviewUrl(submitted)));
          }}
          returnKeyType="go"
          keyboardType="url"
          selectTextOnFocus
          placeholder="Enter URL"
          placeholderTextColor="#888"
          editable={frame !== null}
          autoCapitalize="none"
          autoCorrect={false}
          className="min-h-11 flex-1 border border-white/20 bg-black px-3 text-sm text-white"
        />
        <Tool
          label="Reload"
          icon="arrow.clockwise"
          disabled={!frame}
          onPress={() => void run(() => transportRef.current.reload())}
        />
      </View>
      {error ? (
        <AppText accessibilityRole="alert" className="bg-red-950 px-3 py-1 text-xs text-red-200">
          {error}
        </AppText>
      ) : null}
      <View
        style={{ flex: 1, overflow: "hidden" }}
        onLayout={(event) =>
          setSurface({
            width: Math.max(1, event.nativeEvent.layout.width),
            height: Math.max(1, event.nativeEvent.layout.height),
          })
        }
        {...responder.panHandlers}
      >
        {frame ? (
          <View
            pointerEvents="none"
            style={{
              position: "absolute",
              left: rect.x,
              top: rect.y,
              width: rect.width,
              height: rect.height,
            }}
          >
            <Image
              source={{ uri: `data:${frame.mimeType};base64,${frame.data}` }}
              accessibilityLabel="Desktop browser view"
              style={{ width: "100%", height: "100%" }}
              resizeMode="stretch"
            />
          </View>
        ) : (
          <View className="flex-1 items-center justify-center">
            <AppText className="text-white/60">Connecting to the desktop browser…</AppText>
          </View>
        )}
        {frame && controller.presentation.trackpad ? (
          <View
            pointerEvents="none"
            style={{
              position: "absolute",
              left: rect.x + controller.presentation.cursor.x * rect.scale - 6,
              top: rect.y + controller.presentation.cursor.y * rect.scale - 6,
              width: 12,
              height: 12,
              borderWidth: 2,
              borderColor: "white",
              backgroundColor: "black",
            }}
          />
        ) : null}
      </View>
      <View
        className="flex-row items-center justify-around border-t border-white/10 bg-[#171717] pt-1"
        style={{ flexShrink: 0, paddingBottom: Math.max(8, insets.bottom) }}
      >
        <Tool
          label="Back"
          icon={{ ios: "chevron.left", android: "chevron_left" }}
          disabled={!frame || !canGoBack}
          onPress={() => void run(() => transportRef.current.back())}
        />
        <Tool
          label="Forward"
          icon={{ ios: "chevron.right", android: "chevron_right" }}
          disabled={!frame || !canGoForward}
          onPress={() => void run(() => transportRef.current.forward())}
        />
        <Tool
          label="Keyboard"
          icon={{ ios: "keyboard", android: "keyboard" }}
          disabled={!frame}
          onPress={() => open("keyboard")}
        />
        <Tool
          label="Clipboard"
          icon="doc.on.doc"
          disabled={!frame}
          onPress={() => open("clipboard")}
        />
        <Tool label="Browser controls" icon="ellipsis" onPress={() => open("menu")} />
        <Pressable
          accessibilityRole="button"
          onPress={onDone}
          className="min-h-12 justify-center px-4"
        >
          <AppText className="text-white">Done</AppText>
        </Pressable>
      </View>
      <Modal
        visible={dialog !== null}
        animationType="fade"
        transparent
        onRequestClose={() => setDialog(null)}
      >
        <View
          style={{
            flex: 1,
            backgroundColor: "rgba(0, 0, 0, 0.9)",
            paddingTop: insets.top,
            paddingBottom: insets.bottom,
            paddingLeft: insets.left,
            paddingRight: insets.right,
          }}
        >
          <KeyboardAvoidingView
            behavior={Platform.OS === "ios" ? "padding" : "height"}
            className="flex-1"
          >
            <View className="flex-1 bg-[#171717] px-5">
              <View className="flex-row items-center justify-between py-4">
                <AppText className="flex-1 text-xl text-white">
                  {dialog === "help"
                    ? "Using the Computer"
                    : dialog === "keyboard"
                      ? "Type into browser"
                      : dialog === "clipboard"
                        ? "Clipboard"
                        : "Browser controls"}
                </AppText>
                <Tool label="Close controls" icon="xmark" onPress={() => setDialog(null)} />
              </View>
              <ScrollView
                keyboardShouldPersistTaps="handled"
                contentContainerStyle={{ paddingBottom: 24, gap: 12 }}
              >
                {dialog === "help"
                  ? HELP.map(([section, title, detail]) => (
                      <View key={title}>
                        {section ? (
                          <AppText className="mb-3 mt-4 text-base text-white/45">{section}</AppText>
                        ) : null}
                        <View className="border border-white/10 bg-white/5 p-4">
                          <AppText className="text-xl text-white">{title}</AppText>
                          <AppText className="mt-2 text-base leading-6 text-white/60">
                            {detail}
                          </AppText>
                        </View>
                      </View>
                    ))
                  : null}
                {dialog === "menu" ? (
                  <>
                    <Action
                      label={
                        controller.presentation.trackpad ? "Turn off trackpad" : "Trackpad mode"
                      }
                      onPress={() => {
                        controller.setTrackpad(!controller.presentation.trackpad);
                        redraw((n) => n + 1);
                      }}
                    />
                    <Action
                      label="Recenter pointer"
                      onPress={() => {
                        controller.recenter();
                        redraw((n) => n + 1);
                      }}
                    />
                    <Action
                      label="Fit view"
                      onPress={() => {
                        controller.resetZoom();
                        redraw((n) => n + 1);
                      }}
                    />
                    <Action label="Gesture help" onPress={() => open("help")} />
                  </>
                ) : null}
                {dialog === "keyboard" ? (
                  <>
                    <AppText className="text-white/60">
                      Select a field in the desktop page, then send text or a key.
                    </AppText>
                    <TextInput
                      autoFocus
                      multiline
                      maxLength={64000}
                      accessibilityLabel="Text to send"
                      value={draft}
                      onChangeText={setDraft}
                      className="min-h-28 border border-white/20 bg-black p-3 text-base text-white"
                    />
                    <Action
                      label="Send text"
                      disabled={busy || !draft}
                      onPress={() =>
                        void run(async () => {
                          await transportRef.current.text(draft);
                          setDraft("");
                        })
                      }
                    />
                    {["Enter", "Backspace", "Tab", "Escape"].map((key) => (
                      <Action
                        key={key}
                        label={key}
                        disabled={busy}
                        onPress={() => void run(() => transportRef.current.key(key))}
                      />
                    ))}
                  </>
                ) : null}
                {dialog === "clipboard" ? (
                  <>
                    <AppText className="text-white/60">
                      Copy selected page text or paste into the focused desktop field.
                    </AppText>
                    <Action
                      label="Copy to phone"
                      disabled={busy}
                      onPress={() =>
                        void run(async () => {
                          const text = await transportRef.current.copy();
                          if (!text) throw new Error("Select text in the desktop page first.");
                          await Clipboard.setStringAsync(text);
                        })
                      }
                    />
                    <Action
                      label="Paste from phone"
                      disabled={busy}
                      onPress={() =>
                        void run(async () => {
                          const text = await Clipboard.getStringAsync();
                          if (text.length > 64000)
                            throw new Error("Paste up to 64,000 characters at once.");
                          await transportRef.current.paste(text);
                        })
                      }
                    />
                  </>
                ) : null}
                {error ? (
                  <AppText accessibilityRole="alert" className="text-red-300">
                    {error}
                  </AppText>
                ) : null}
              </ScrollView>
            </View>
          </KeyboardAvoidingView>
        </View>
      </Modal>
    </View>
  );
}
