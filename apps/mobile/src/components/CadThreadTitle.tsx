import { View } from "react-native";

import { AppText as Text } from "./AppText";
import { CadMark } from "./CadMark";

/** Keeps the workspace signature quiet and leaves the thread title readable. */
export function CadThreadTitle(props: { readonly title: string; readonly subtitle?: string }) {
  return (
    <View className="min-w-0 items-center">
      <View className="min-w-0 flex-row items-center gap-1.5">
        <CadMark />
        <Text numberOfLines={1} className="shrink text-[17px] font-t3-bold text-foreground">
          {props.title}
        </Text>
      </View>
      {props.subtitle ? (
        <Text numberOfLines={1} className="text-xs font-t3-medium text-foreground-muted">
          {props.subtitle}
        </Text>
      ) : null}
    </View>
  );
}
