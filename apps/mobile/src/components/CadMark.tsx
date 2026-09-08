import Svg, { Path } from "react-native-svg";
import { withUniwind } from "uniwind";

const ThemedPath = withUniwind(Path);

/** Decorative CAD signature shared by the app icon and workspace headers. */
export function CadMark({ size = 12 }: { readonly size?: number }) {
  return (
    <Svg width={size} height={size} viewBox="0 0 24 24" accessible={false}>
      <ThemedPath
        d="M12 2 21 7v10l-9 5-9-5V7l9-5ZM3 7l9 5 9-5M12 12v10"
        fill="none"
        stroke="currentColor"
        colorClassName="text-foreground-muted"
        strokeWidth={1.6}
        strokeLinejoin="round"
        opacity={0.6}
      />
    </Svg>
  );
}
