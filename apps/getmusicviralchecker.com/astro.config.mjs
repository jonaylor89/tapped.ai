import vercel from "@astrojs/vercel";
import tailwindcss from "@tailwindcss/vite";
import { defineConfig } from "astro/config";

export default defineConfig({
	output: "server",
	adapter: vercel(),
	vite: {
		plugins: [
			tailwindcss(),
			{
				name: "resolve-node-builtins",
				enforce: "pre",
				resolveId(id) {
					if (id === "fs") return { id: "node:fs", external: true };
				},
			},
		],
	},
});
