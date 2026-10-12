import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import { runInNewContext } from "node:vm";
import ts from "typescript";
import nextConfig from "../next.config.mjs";

const { outputText } = ts.transpileModule(
  readFileSync(new URL("../src/context/analytics.tsx", import.meta.url), "utf8"),
  { compilerOptions: { module: ts.ModuleKind.CommonJS, jsx: ts.JsxEmit.ReactJSX } },
);

function initializeAnalytics(env, browser) {
  const calls = [];
  const client = { init: (...args) => calls.push(args) };
  runInNewContext(outputText, {
    exports: {},
    process: { env },
    ...(browser ? { window: {} } : {}),
    require: (name) => {
      if (name === "posthog-js") return { default: client };
      if (name === "posthog-js/react" || name === "react/jsx-runtime") return {};
      throw new Error(`Unexpected import: ${name}`);
    },
  });
  return calls;
}

test("Next 16 configuration omits the removed eslint option", () => {
  assert.equal(Object.hasOwn(nextConfig, "eslint"), false);
});

test("optional analytics never initializes without a token or during SSR", () => {
  for (const key of [undefined, "", "   "]) {
    assert.equal(initializeAnalytics({ NEXT_PUBLIC_POSTHOG_KEY: key }, true).length, 0);
  }
  assert.equal(initializeAnalytics({ NEXT_PUBLIC_POSTHOG_KEY: "test-token" }, false).length, 0);
});

test("configured browser analytics still initializes", () => {
  const calls = initializeAnalytics({ NEXT_PUBLIC_POSTHOG_KEY: "test-token", NEXT_PUBLIC_POSTHOG_HOST: "/ingest" }, true);
  assert.equal(calls.length, 1);
  assert.equal(calls[0][0], "test-token");
  assert.equal(calls[0][1].api_host, "/ingest");
  assert.equal(calls[0][1].person_profiles, "identified_only");
});
