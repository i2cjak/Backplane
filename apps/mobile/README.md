# Backplane Mobile

> [!WARNING]
> Backplane Mobile is currently in development. The `testflight` profile carries the existing
> App Store bundle identity; delivery credentials and project ownership remain external.

## Quickstart

> [!NOTE]
> Uses native modules so using Expo Go is not supported. You need to use the Expo Dev Client.

This app has four variants:

- `development`: Expo dev client, installable side-by-side as `Backplane Dev`
- `preview`: persistent internal preview build, installable side-by-side as `Backplane Preview`
- `production`: generic store/release build as `Backplane`
- `testflight`: App Store Connect build using the existing `com.i2cjak.k3eda` iOS identity

`APP_VARIANT=k3eda` remains a compatibility alias for `testflight`.

Run commands from `apps/mobile`.

Backplane Connect is optional and disabled in a fresh clone. Public configuration belongs in the
repository-root `.env` or `.env.local`, not an `apps/mobile/.env` file. See
[`../../.env.example`](../../.env.example).

## Development

Start Metro for the dev client:

```bash
vp run dev:client
```

Metro keeps its transform cache between ordinary starts. If the cache itself is causing stale or
invalid output, clear it for one development-client start:

```bash
vp run dev:client:reset
```

Run that reset once after installing or changing the Uniwind dependency patch. Cached transforms
can otherwise reference its previous pnpm package path. Ordinary Metro starts still keep the cache.

Component edits use Fast Refresh. See [mobile development lifecycle](../../docs/internals/mobile-development.md)
before changing runtime ownership or refresh behavior.

Build and run the local iOS dev client:

```bash
vp run ios:dev
```

After changing a native dependency patch, rerun CocoaPods before rebuilding an existing iOS
project. pnpm gives each patch hash a new package path; Pods can otherwise keep compiling the
previous directory.

If your Xcode account only has a Personal Team, use a bundle identifier you control and opt into the
reduced-capability local build. Personal Team builds omit the widget and share extensions, push
entitlement, and native Sign in with Apple entitlement; builds without this opt-in are unchanged.

```bash
BACKPLANE_IOS_PERSONAL_TEAM=1 \
BACKPLANE_IOS_PERSONAL_TEAM_BUNDLE_ID=com.example.backplane.dev \
vp run ios:dev
```

Build and install a self-contained Release app that does not need Metro:

```bash
vp run ios:release
```

The Personal Team equivalent also needs a unique bundle identifier:

```bash
BACKPLANE_IOS_PERSONAL_TEAM=1 \
BACKPLANE_IOS_PERSONAL_TEAM_BUNDLE_ID=com.example.backplane \
vp run ios:release
```

Build and run the local iOS preview app:

```bash
vp run ios:preview
```

Force the review diff highlighter engine:

```bash
EXPO_PUBLIC_REVIEW_HIGHLIGHTER_ENGINE=javascript vp run ios:dev
```

`javascript` is the default and recommended setting for the review diff screen. Set `EXPO_PUBLIC_REVIEW_HIGHLIGHTER_ENGINE=native` only when you explicitly want to test the native Shiki engine.

Inspect the resolved Expo config for a variant:

```bash
vp run config:dev
vp run config:preview
vp run config:k3eda
```

Run static checks for mobile native code:

```bash
node ../../scripts/mobile-native-static-check.ts
```

The native lint task runs SwiftLint for Swift plus ktlint and detekt for Kotlin. Missing native tools are reported as warnings and skipped locally. CI installs the default toolset from `apps/mobile/Brewfile` before running the native checks.

## EAS Builds

Preview and production variants use Expo fingerprinting so OTA updates only reach binaries with matching native dependencies, config plugins, and patches. CI uses the `preview:dev` profile to reuse a compatible native build when possible.

The development variant uses `appVersion` to avoid recalculating the native fingerprint for each Metro launch manifest. `MOBILE_VERSION_POLICY` can override either default. If you distribute a custom Release build with the development identity and publish OTA updates to it, set `MOBILE_VERSION_POLICY=fingerprint` for both its build and updates. Changing the runtime policy requires a native rebuild for OTA matching; an existing dev client can still load local Metro bundles.

For preview or production EAS environments, set `EXPO_PUBLIC_CLERK_PUBLISHABLE_KEY`,
`EXPO_PUBLIC_CLERK_JWT_TEMPLATE`, and `BACKPLANE_RELAY_URL`
as EAS environment variables. Expo config maps the canonical values into the mobile build.

The `testflight` profile uses the existing `com.i2cjak.k3eda` bundle identity and App Store
Connect app ID `6809006324`. Set `BACKPLANE_APPLE_TEAM_ID` in the EAS environment used for
signing; the config does not embed an Apple team ID.

Create a PR preview dev-client build manually:

```bash
vp run eas:ios:preview:dev
```

Create a cloud dev-client build:

```bash
vp run eas:ios:dev
```

Create a persistent preview build:

```bash
vp run eas:ios:preview
```

Create the existing iOS TestFlight build:

```bash
vp run eas:ios:testflight
```

Manual Xcode releases must preserve the app and extension entitlements. Prefer a normally
signed archive with `-allowProvisioningUpdates`. An archive produced with
`CODE_SIGNING_ALLOWED=NO` can export and upload successfully while silently losing push and
App Group entitlements. When cloud signing requires an unsigned archive, first ad hoc sign
both extensions and then the app, using each target's generated entitlements:

```bash
codesign --force --sign - --entitlements ios/ExpoWidgetsTarget/ExpoWidgetsTarget.entitlements \
  "$ARCHIVE_PATH/Products/Applications/Backplane.app/PlugIns/ExpoWidgetsTarget.appex"
codesign --force --sign - --entitlements ios/expo-sharing-extension/expo-sharing-extension.entitlements \
  "$ARCHIVE_PATH/Products/Applications/Backplane.app/PlugIns/expo-sharing-extension.appex"
codesign --force --sign - --entitlements ios/Backplane/Backplane.entitlements \
  "$ARCHIVE_PATH/Products/Applications/Backplane.app"
```

These are intermediate signatures. Export through Xcode with Apple distribution signing,
then inspect the actual IPA before uploading:

```bash
ios_export_check=$(mktemp -d)
ditto -x -k /path/to/Backplane.ipa "$ios_export_check"
codesign --verify --deep --strict "$ios_export_check/Payload/Backplane.app"
codesign -dvv --entitlements :- "$ios_export_check/Payload/Backplane.app"
```

Require an Apple signing authority, `aps-environment=production`, and
`com.apple.security.application-groups` containing `group.com.i2cjak.k3eda`.
Inspect both bundles under `PlugIns` for Apple signatures and the same App Group. Also check
that the app and both extensions carry the intended version and build number; generated
Info.plist values can override command-line build settings.

Android equivalents:

```bash
vp run eas:android:dev
vp run eas:android:preview:dev
vp run eas:android:preview
```

Build a standalone Android APK for an ARM64 phone with the local Android SDK and Java 17:

```bash
vp run android:release
```

The signed local APK is written to `android/app/build/outputs/apk/release/app-release.apk` and
uses the `works.backplane.app` application ID with the local development signing key.
