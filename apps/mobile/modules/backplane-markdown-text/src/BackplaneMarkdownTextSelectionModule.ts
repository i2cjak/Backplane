import { requireOptionalNativeModule } from "expo";

interface BackplaneMarkdownTextSelectionNativeModule {
  readonly installCopySanitizer: (reactTag: number) => void;
}

const nativeModule = requireOptionalNativeModule<BackplaneMarkdownTextSelectionNativeModule>(
  "BackplaneMarkdownTextSelection",
);

export function installMarkdownCopySanitizer(reactTag: number): void {
  nativeModule?.installCopySanitizer(reactTag);
}
