import {
  BACKPLANE_PROJECT_FILE_NAME,
  type EnvironmentId,
  type BackplaneProjectFile,
  type BackplaneProjectFileScript,
} from "@backplane/contracts";
import { parseBackplaneProjectFile } from "@backplane/shared/backplaneProjectFile";
import { useMemo } from "react";

import { useProjectFileQuery } from "~/components/files/projectFilesQueryState";

const NO_SCRIPTS: ReadonlyArray<BackplaneProjectFileScript> = [];

export interface BackplaneProjectFileState {
  /**
   * - `valid`: backplane.json exists and decoded.
   * - `invalid`: backplane.json exists but fails to decode (the server then ignores
   *   the whole file, including `iconPath` and every script).
   * - `missing`: no readable backplane.json at the workspace root.
   * - `loading`: the file query has not settled yet.
   */
  status: "loading" | "missing" | "invalid" | "valid";
  /** The decoded file when status is `valid`, null otherwise. */
  file: BackplaneProjectFile | null;
  scripts: ReadonlyArray<BackplaneProjectFileScript>;
}

/**
 * Decoded state of the project's checked-in `backplane.json`, including whether the
 * file exists but is broken — which the runtime otherwise swallows silently.
 */
export function useBackplaneProjectFileState(
  environmentId: EnvironmentId,
  cwd: string | null,
): BackplaneProjectFileState {
  const query = useProjectFileQuery(
    environmentId,
    cwd ?? "",
    BACKPLANE_PROJECT_FILE_NAME,
    cwd !== null,
  );
  const contents = query.data && !query.data.truncated ? query.data.contents : null;
  const isPending = query.isPending;
  return useMemo(() => {
    if (contents === null) {
      return {
        status: isPending ? "loading" : "missing",
        file: null,
        scripts: NO_SCRIPTS,
      } as const;
    }
    const file = parseBackplaneProjectFile(contents);
    if (file === null) {
      return { status: "invalid", file: null, scripts: NO_SCRIPTS } as const;
    }
    return { status: "valid", file, scripts: file.scripts ?? NO_SCRIPTS } as const;
  }, [contents, isPending]);
}

/**
 * Scripts declared in the project's checked-in `backplane.json`, offered in the
 * scripts menu for import. Missing, truncated, or invalid files resolve to
 * an empty list.
 */
export function useBackplaneProjectFileScripts(
  environmentId: EnvironmentId,
  cwd: string | null,
): ReadonlyArray<BackplaneProjectFileScript> {
  return useBackplaneProjectFileState(environmentId, cwd).scripts;
}
