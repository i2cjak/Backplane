import * as Option from "effect/Option";

export type JoinPath = (first: string, ...segments: string[]) => string;

function normalizeConfiguredBaseDir(backplaneHome: Option.Option<string>): Option.Option<string> {
  if (Option.isNone(backplaneHome)) {
    return Option.none();
  }
  const trimmed = backplaneHome.value.trim();
  return trimmed.length > 0 ? Option.some(trimmed) : Option.none();
}

export function resolveDesktopBaseDir(input: {
  readonly homeDirectory: string;
  readonly joinPath: JoinPath;
  readonly backplaneHome: Option.Option<string>;
}): string {
  return Option.getOrElse(normalizeConfiguredBaseDir(input.backplaneHome), () =>
    input.joinPath(input.homeDirectory, ".backplane"),
  );
}

export function resolveDesktopStateDir(input: {
  readonly baseDir: string;
  readonly isDevelopment: boolean;
  readonly joinPath: JoinPath;
  readonly backplaneHome: Option.Option<string>;
}): string {
  const useDevSubdir =
    input.isDevelopment && Option.isNone(normalizeConfiguredBaseDir(input.backplaneHome));
  return input.joinPath(input.baseDir, useDevSubdir ? "dev" : "userdata");
}
