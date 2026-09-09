/**
 * BackplaneProjectFileLoader - Effect service that loads the checked-in `backplane.json`
 * project file from a workspace root.
 *
 * Loading is best-effort: a missing file resolves to `Option.none`, and
 * unreadable or invalid files are logged and treated as absent so callers
 * can fall back to their defaults.
 *
 * @module BackplaneProjectFileLoader
 */
import * as Context from "effect/Context";
import * as Effect from "effect/Effect";
import * as FileSystem from "effect/FileSystem";
import * as Layer from "effect/Layer";
import * as Option from "effect/Option";
import * as Path from "effect/Path";
import * as Schema from "effect/Schema";

import { BACKPLANE_PROJECT_FILE_NAME, type BackplaneProjectFile } from "@backplane/contracts";
import { BackplaneProjectFileFromJson } from "@backplane/shared/backplaneProjectFile";

const decodeBackplaneProjectFileJson = Schema.decodeEffect(BackplaneProjectFileFromJson);

export class BackplaneProjectFileLoadError extends Schema.TaggedErrorClass<BackplaneProjectFileLoadError>()(
  "BackplaneProjectFileLoadError",
  {
    operation: Schema.Literals(["read", "decode"]),
    workspaceRoot: Schema.String,
    filePath: Schema.String,
    cause: Schema.Defect(),
  },
) {
  override get message(): string {
    return `Failed to ${this.operation} ${BACKPLANE_PROJECT_FILE_NAME} at ${this.filePath}.`;
  }
}

/** Service tag for backplane.json project file loading. */
export class BackplaneProjectFileLoader extends Context.Service<
  BackplaneProjectFileLoader,
  {
    /**
     * Load and decode `backplane.json` at the workspace root.
     *
     * Never fails: missing, unreadable, or invalid files resolve to
     * `Option.none` (invalid files are logged as warnings).
     */
    readonly load: (workspaceRoot: string) => Effect.Effect<Option.Option<BackplaneProjectFile>>;
  }
>()("@backplane/cli/project/BackplaneProjectFileLoader") {}

const logBackplaneProjectFileLoadError = (error: BackplaneProjectFileLoadError) =>
  Effect.logWarning(error).pipe(
    Effect.annotateLogs({
      operation: error.operation,
      workspaceRoot: error.workspaceRoot,
      filePath: error.filePath,
      errorTag: error._tag,
    }),
  );

export const make = Effect.gen(function* () {
  const fileSystem = yield* FileSystem.FileSystem;
  const path = yield* Path.Path;

  const load: BackplaneProjectFileLoader["Service"]["load"] = Effect.fn(
    "BackplaneProjectFileLoader.load",
  )(function* (workspaceRoot) {
    const filePath = path.join(workspaceRoot, BACKPLANE_PROJECT_FILE_NAME);
    const raw = yield* fileSystem.readFileString(filePath).pipe(
      Effect.map(Option.some),
      Effect.catchTags({
        PlatformError: (error) =>
          error.reason._tag === "NotFound"
            ? Effect.succeed(Option.none<string>())
            : logBackplaneProjectFileLoadError(
                new BackplaneProjectFileLoadError({
                  operation: "read",
                  workspaceRoot,
                  filePath,
                  cause: error,
                }),
              ).pipe(Effect.as(Option.none<string>())),
      }),
    );
    if (Option.isNone(raw)) {
      return Option.none<BackplaneProjectFile>();
    }
    return yield* decodeBackplaneProjectFileJson(raw.value).pipe(
      Effect.map(Option.some),
      Effect.catchTags({
        SchemaError: (error) =>
          logBackplaneProjectFileLoadError(
            new BackplaneProjectFileLoadError({
              operation: "decode",
              workspaceRoot,
              filePath,
              cause: error,
            }),
          ).pipe(Effect.as(Option.none<BackplaneProjectFile>())),
      }),
    );
  });

  return BackplaneProjectFileLoader.of({ load });
});

export const layer = Layer.effect(BackplaneProjectFileLoader, make);
