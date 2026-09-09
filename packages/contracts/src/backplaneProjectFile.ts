import * as Schema from "effect/Schema";
import * as SchemaTransformation from "effect/SchemaTransformation";

import { ThreadEnvMode } from "./environment.ts";
import { ProjectScriptIcon } from "./orchestration.ts";

/** File name of the checked-in Backplane project file, resolved at the workspace root. */
export const BACKPLANE_PROJECT_FILE_NAME = "backplane.json";

/** Public URL of the published JSON Schema for {@link BackplaneProjectFile}. */
export const BACKPLANE_PROJECT_FILE_SCHEMA_URL = "https://backplane.works/schema/backplane.json";

const BACKPLANE_PROJECT_FILE_PATH_MAX_LENGTH = 512;
const BACKPLANE_PROJECT_FILE_MAX_SCRIPTS = 50;

// Annotations go on the encoded (string) side so they survive into the
// published JSON Schema; decoding still trims and re-validates non-emptiness.
const trimmedNonEmpty = (annotations: { readonly description: string }, maxLength?: number) => {
  const annotated = Schema.String.annotate(annotations);
  const encoded =
    maxLength === undefined
      ? annotated.check(Schema.isNonEmpty())
      : annotated.check(Schema.isNonEmpty(), Schema.isMaxLength(maxLength));
  return encoded.pipe(Schema.decodeTo(encoded, SchemaTransformation.trim()));
};

export const BackplaneProjectFileScript = Schema.Struct({
  name: trimmedNonEmpty({
    description: "Display name for the script, shown in the Backplane scripts menu.",
  }),
  command: trimmedNonEmpty({
    description: "Shell command executed in a Backplane terminal at the project root.",
  }),
  icon: Schema.optionalKey(
    ProjectScriptIcon.annotate({
      description: 'Icon shown next to the script in the scripts menu. Defaults to "play".',
    }),
  ),
  runOnWorktreeCreate: Schema.optionalKey(
    Schema.Boolean.annotate({
      description:
        "When true, the script runs automatically after a worktree is created for a new thread.",
    }),
  ),
  previewUrl: Schema.optionalKey(
    trimmedNonEmpty({
      description:
        "URL opened in the in-app browser preview when this script runs. Only honored on the desktop build.",
    }),
  ),
  autoOpenPreview: Schema.optionalKey(
    Schema.Boolean.annotate({
      description:
        "When true, automatically open the preview panel at `previewUrl` the moment the script starts.",
    }),
  ),
}).annotate({
  description: "A project script that team members can import into Backplane.",
});
export type BackplaneProjectFileScript = typeof BackplaneProjectFileScript.Type;

export const BackplaneProjectFile = Schema.Struct({
  $schema: Schema.optionalKey(
    Schema.String.annotate({
      description: `URL of the JSON Schema for this file, typically "${BACKPLANE_PROJECT_FILE_SCHEMA_URL}".`,
    }),
  ),
  iconPath: Schema.optionalKey(
    trimmedNonEmpty(
      {
        description:
          'Workspace-relative path to the project icon (e.g. "assets/logo.svg"). Checked before Backplane\'s built-in icon locations.',
      },
      BACKPLANE_PROJECT_FILE_PATH_MAX_LENGTH,
    ),
  ),
  defaultThreadEnvMode: Schema.optionalKey(
    ThreadEnvMode.annotate({
      description:
        'Where new threads start for this repository: "worktree" for a fresh git worktree, "local" for the current checkout. A per-project setting in Backplane overrides this; when neither is set, the global default applies.',
    }),
  ),
  scripts: Schema.optionalKey(
    Schema.Array(BackplaneProjectFileScript)
      .annotate({
        description: "Project scripts shared with everyone who opens this repository in Backplane.",
      })
      .check(Schema.isMaxLength(BACKPLANE_PROJECT_FILE_MAX_SCRIPTS)),
  ),
}).annotate({
  title: "Backplane project file",
  description:
    "Checked-in project configuration for Backplane (backplane.json at the repository root). See https://backplane.works for documentation.",
});
export type BackplaneProjectFile = typeof BackplaneProjectFile.Type;
