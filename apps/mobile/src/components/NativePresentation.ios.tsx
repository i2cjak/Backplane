import { requireNativeView } from "expo";
import type { ComponentType } from "react";
import type { PresentationSourceProps } from "./NativePresentation";

const NativeSource: ComponentType<PresentationSourceProps> = requireNativeView(
  "BackplaneNativeControls",
  "PresentationSource",
);

export function PresentationSource(props: PresentationSourceProps) {
  return <NativeSource {...props} collapsableChildren={false} />;
}
