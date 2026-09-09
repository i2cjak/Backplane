import { createKiCadState } from "@backplane/client-runtime/state/kicad";

import { connectionAtomRuntime } from "../connection/runtime";

/** Authenticated KiCad project manifest/session queries for the active environment. */
export const kicadState = createKiCadState(connectionAtomRuntime);
