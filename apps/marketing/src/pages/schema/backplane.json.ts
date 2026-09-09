import type { APIRoute } from "astro";

import { buildBackplaneProjectFileJsonSchema } from "@backplane/shared/backplaneProjectFile";

// Rendered at build time; published at https://backplane.works/schema/backplane.json so
// backplane.json files can reference it via "$schema" for editor/LSP support.
export const GET: APIRoute = () =>
  new Response(`${JSON.stringify(buildBackplaneProjectFileJsonSchema(), null, 2)}\n`, {
    headers: { "Content-Type": "application/json" },
  });
