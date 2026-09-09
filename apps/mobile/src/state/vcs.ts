import {
  createVcsActionManager,
  createVcsEnvironmentAtoms,
} from "@backplane/client-runtime/state/vcs";

import { connectionAtomRuntime } from "../connection/runtime";

export const vcsEnvironment = createVcsEnvironmentAtoms(connectionAtomRuntime);
export const vcsActionManager = createVcsActionManager(connectionAtomRuntime);
