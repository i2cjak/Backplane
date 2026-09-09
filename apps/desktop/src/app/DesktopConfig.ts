import * as Config from "effect/Config";
import * as ConfigProvider from "effect/ConfigProvider";
import * as Option from "effect/Option";

const trimNonEmptyOption = (value: string): Option.Option<string> => {
  const trimmed = value.trim();
  return trimmed.length > 0 ? Option.some(trimmed) : Option.none();
};

const trimmedString = (name: string) =>
  Config.string(name).pipe(Config.option, Config.map(Option.flatMap(trimNonEmptyOption)));

const optionalBoolean = (name: string) =>
  Config.boolean(name).pipe(Config.option, Config.map(Option.getOrElse(() => false)));

const commaSeparatedStrings = (name: string) =>
  trimmedString(name).pipe(
    Config.map(
      Option.match({
        onNone: () => [],
        onSome: (value) =>
          value
            .split(",")
            .map((entry) => entry.trim())
            .filter((entry) => entry.length > 0),
      }),
    ),
  );

const compactEnv = (env: Readonly<Record<string, string | undefined>>): Record<string, string> =>
  Object.fromEntries(
    Object.entries(env).filter((entry): entry is [string, string] => entry[1] !== undefined),
  );

export const DesktopConfig = Config.all({
  appDataDirectory: trimmedString("APPDATA"),
  xdgConfigHome: trimmedString("XDG_CONFIG_HOME"),
  xdgDataHome: trimmedString("XDG_DATA_HOME"),
  backplaneHome: trimmedString("BACKPLANE_HOME"),
  devServerUrl: Config.url("VITE_DEV_SERVER_URL").pipe(Config.option),
  appUserModelIdOverride: trimmedString("BACKPLANE_DESKTOP_APP_USER_MODEL_ID"),
  devRemoteBackplaneServerEntryPath: trimmedString(
    "BACKPLANE_DEV_REMOTE_BACKPLANE_SERVER_ENTRY_PATH",
  ),
  configuredBackendPort: Config.port("BACKPLANE_PORT").pipe(Config.option),
  commitHashOverride: trimmedString("BACKPLANE_COMMIT_HASH"),
  desktopLanHostOverride: trimmedString("BACKPLANE_DESKTOP_LAN_HOST"),
  desktopHttpsEndpointUrls: commaSeparatedStrings("BACKPLANE_DESKTOP_HTTPS_ENDPOINTS"),
  otlpTracesUrl: trimmedString("BACKPLANE_OTLP_TRACES_URL"),
  otlpExportIntervalMs: Config.int("BACKPLANE_OTLP_EXPORT_INTERVAL_MS").pipe(
    Config.withDefault(10_000),
  ),
  appImagePath: trimmedString("APPIMAGE"),
  disableAutoUpdate: optionalBoolean("BACKPLANE_DISABLE_AUTO_UPDATE"),
  mockUpdates: optionalBoolean("BACKPLANE_DESKTOP_MOCK_UPDATES"),
  mockUpdateServerPort: Config.port("BACKPLANE_DESKTOP_MOCK_UPDATE_SERVER_PORT").pipe(
    Config.withDefault(3000),
  ),
});

export const layerTest = (env: Readonly<Record<string, string | undefined>>) =>
  ConfigProvider.layer(ConfigProvider.fromEnv({ env: compactEnv(env) }));
