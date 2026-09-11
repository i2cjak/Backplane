import "@vitejs/plugin-react/preamble";
import { showBootError } from "../lib/bootError";

// Keep the KiCad viewer's React graph behind the preamble. Bundled dev can
// preload shared chunks for a direct HTML entry before that entry executes.
void import("./standalone").catch(showBootError);
