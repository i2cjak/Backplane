import {
  BACKPLANE_PROJECT_FILE_NAME,
  type EnvironmentId,
  type ThreadEnvMode,
} from "@backplane/contracts";
import { parseBackplaneProjectFile } from "@backplane/shared/backplaneProjectFile";
import { executeAtomQuery } from "@backplane/client-runtime/state/runtime";

import {
  getProjectFileQueryAtom,
  resolveProjectFileQueryData,
} from "~/components/files/projectFilesQueryState";
import { appAtomRegistry } from "~/rpc/atomRegistry";

/**
 * Read `defaultThreadEnvMode` from the project's checked-in `backplane.json`.
 *
 * Imperative counterpart to `useBackplaneProjectFileScripts` for the new-thread
 * path, which resolves defaults at call time rather than render time. The
 * file query atom caches per (environment, cwd), so repeat calls don't
 * re-fetch. Optimistic in-app writes overlay the query result, matching what
 * `useProjectFileQuery` renders. Missing, truncated, or invalid files
 * resolve to null.
 */
export async function readBackplaneProjectFileDefaultThreadEnvMode(
  environmentId: EnvironmentId,
  workspaceRoot: string,
): Promise<ThreadEnvMode | null> {
  const result = await executeAtomQuery(
    appAtomRegistry,
    getProjectFileQueryAtom(environmentId, workspaceRoot, BACKPLANE_PROJECT_FILE_NAME),
    { reportDefect: false, reportFailure: false },
  );
  const data = resolveProjectFileQueryData(
    environmentId,
    workspaceRoot,
    BACKPLANE_PROJECT_FILE_NAME,
    result._tag === "Success" ? result.value : null,
  );
  if (data === null || data.truncated) return null;
  return parseBackplaneProjectFile(data.contents)?.defaultThreadEnvMode ?? null;
}
