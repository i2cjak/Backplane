import { createKiCadState } from "@backplane/client-runtime/state/kicad";
import { connectionAtomRuntime } from "../connection/runtime";

export const kicadState = createKiCadState(connectionAtomRuntime);
