import { spawnSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { fileURLToPath, pathToFileURL } from "node:url";

const root = fileURLToPath(new URL("../", import.meta.url));
const allowlist = JSON.parse(readFileSync(new URL("../deployment-allowlist.json", import.meta.url), "utf8"));

export function deploymentArgs(names) {
  if (!names.length || names.some((name) => !allowlist.includes(name))) {
    throw new Error(
      "Specify approved function names only; blanket, extension and retired-function deploys are blocked.",
    );
  }
  return [
    "--yes",
    "firebase-tools@14.22.0",
    "deploy",
    "--project",
    "in-the-loop-306520",
    "--config",
    "firebase.json",
    // Firebase requires confirmation to enable retry policies. The allowlist contains
    // only the two Auth transports; blanket/HTTP/extension deploys stay blocked.
    "--force",
    "--only",
    [...new Set(names)].map((name) => `functions:${name}`).join(","),
  ];
}

if (process.argv[1] && pathToFileURL(process.argv[1]).href === import.meta.url) {
  let args;
  try {
    args = deploymentArgs(process.argv.slice(2));
  } catch (cause) {
    console.error(cause.message);
    process.exit(1);
  }
  const validation = spawnSync("npm", ["run", "lint"], { cwd: root, stdio: "inherit" });
  if (validation.status !== 0) process.exit(validation.status ?? 1);
  const build = spawnSync("npm", ["run", "build"], { cwd: root, stdio: "inherit" });
  if (build.status !== 0) process.exit(build.status ?? 1);
  const result = spawnSync("npx", args, { cwd: root, stdio: "inherit" });
  process.exit(result.status ?? 1);
}
