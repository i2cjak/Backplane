import * as Exit from "effect/Exit";
import * as Schema from "effect/Schema";

import { BackplaneProjectFile, BACKPLANE_PROJECT_FILE_SCHEMA_URL } from "@backplane/contracts";

import { fromLenientJson } from "./schemaJson.ts";

/**
 * Codec between the raw `backplane.json` file contents (lenient JSONC string) and the
 * decoded {@link BackplaneProjectFile}.
 */
export const BackplaneProjectFileFromJson = fromLenientJson(BackplaneProjectFile);

const decodeBackplaneProjectFile = Schema.decodeExit(BackplaneProjectFileFromJson);

/**
 * Decode raw `backplane.json` contents, treating invalid or malformed files as
 * absent. Clients use this to read optional defaults (scripts, thread env
 * mode) without surfacing decode errors to the user.
 */
export function parseBackplaneProjectFile(contents: string): BackplaneProjectFile | null {
  const decoded = decodeBackplaneProjectFile(contents);
  return Exit.isSuccess(decoded) ? decoded.value : null;
}

/**
 * Build the publishable JSON Schema document for `backplane.json` (draft 2020-12).
 *
 * Served from the marketing site at {@link BACKPLANE_PROJECT_FILE_SCHEMA_URL} so
 * editors get LSP support via a `$schema` reference.
 */
export function buildBackplaneProjectFileJsonSchema(): Record<string, unknown> {
  const document = Schema.toJsonSchemaDocument(BackplaneProjectFile);
  const jsonSchema: Record<string, unknown> = {
    $schema: "https://json-schema.org/draft/2020-12/schema",
    $id: BACKPLANE_PROJECT_FILE_SCHEMA_URL,
    ...document.schema,
  };
  if (document.definitions && Object.keys(document.definitions).length > 0) {
    jsonSchema.$defs = document.definitions;
  }
  return jsonSchema;
}
