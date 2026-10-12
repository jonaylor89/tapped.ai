import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { createRequire } from "node:module";
import test from "node:test";
import ts from "typescript";
import { deploymentArgs } from "../scripts/deploy.mjs";

const read = (path) => readFileSync(new URL(path, import.meta.url), "utf8");
const allowlist = JSON.parse(read("../deployment-allowlist.json"));

test("entrypoint exports exactly the approved HTTP/Auth handlers, never wildcard legacy modules", () => {
  const source = ts.createSourceFile("index.ts", read("../src/index.ts"), ts.ScriptTarget.Latest, true);
  const exports = [];
  for (const statement of source.statements) {
    assert.equal(ts.isExportDeclaration(statement), true, "entrypoint must contain named exports only");
    assert.ok(statement.exportClause && ts.isNamedExports(statement.exportClause), "wildcard exports are forbidden");
    exports.push(...statement.exportClause.elements.map((element) => element.name.text));
  }
  assert.deepEqual(exports.sort(), allowlist);
});

test("compiled exports match the allowlist and expose no Firestore triggers", () => {
  const previous = process.env.FIREBASE_CONFIG;
  const previousProject = process.env.GCLOUD_PROJECT;
  process.env.GCLOUD_PROJECT = "in-the-loop-306520";
  process.env.FIREBASE_CONFIG = JSON.stringify({
    projectId: "in-the-loop-306520",
    storageBucket: "in-the-loop-306520.appspot.com",
  });
  try {
    const handlers = createRequire(import.meta.url)("../lib/index.js");
    assert.deepEqual(Object.keys(handlers).sort(), allowlist);
    for (const [name, handler] of Object.entries(handlers)) {
      assert.ok(handler.__endpoint, name);
      assert.equal(handler.__endpoint.eventTrigger?.eventType.includes("firestore") ?? false, false, name);
    }
  } finally {
    if (previous === undefined) delete process.env.FIREBASE_CONFIG;
    else process.env.FIREBASE_CONFIG = previous;
    if (previousProject === undefined) delete process.env.GCLOUD_PROJECT;
    else process.env.GCLOUD_PROJECT = previousProject;
  }
});

test("selective deploys target the original project without force or blanket functions deployment", () => {
  const args = deploymentArgs(["inboundEmailWebhook", "inboundEmailWebhook", "deleteStreamUser"]);
  assert.equal(args[1], "firebase-tools@14.22.0");
  assert.ok(args.includes("in-the-loop-306520"));
  assert.equal(args.at(-1), "functions:inboundEmailWebhook,functions:deleteStreamUser");
  assert.equal(args.includes("--force"), false);
});

test("deploys reject no names, retired writers, extensions and argument injection", () => {
  for (const names of [
    [],
    ["onUserDeleted"],
    ["createDefaultServicesOnUserCreated"],
    ["setLatestContactRequest"],
    ["ext-auth-chat-createStreamUser"],
    ["*"],
    ["--force"],
    ["inboundEmailWebhook,users"],
  ]) {
    assert.throws(() => deploymentArgs(names));
  }
});

test("functions configuration cannot deploy Firestore rules/indexes or depend on the Flutter directory", () => {
  const config = JSON.parse(read("../firebase.json"));
  assert.deepEqual(Object.keys(config), ["functions"]);
  assert.equal(config.functions[0].source, ".");
  assert.equal(config.functions[0].codebase, "default");
  assert.equal(config.functions[0].runtime, "nodejs22");
  assert.equal(read("../package.json").includes("com.intheloopstudio"), false);
});

test("active webhook bridge contains no Firestore reads, writes or imports", () => {
  const source = read("../src/lib/webhooks.ts");
  assert.doesNotMatch(source, /usersRef|contactVenuesRef|\.collection\(|firebase-admin\/firestore/);
});
