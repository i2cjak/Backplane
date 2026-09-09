import { defineConfig } from "astro/config";

export default defineConfig({
  site: "https://backplane.works",
  server: {
    port: Number(process.env.PORT ?? 4173),
  },
});
