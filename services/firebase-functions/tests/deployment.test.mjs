import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { createRequire } from "node:module";
import test from "node:test";
import ts from "typescript";
import { deploymentArgs } from "../scripts/deploy.mjs";

const read = (path) => readFileSync(new URL(path, import.meta.url), "utf8");
const allowlist = JSON.parse(read("../deployment-allowlist.json"));

test("entrypoint exports exactly the two Auth transports, never legacy modules", () => {
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
      assert.equal(
        handler.__endpoint.eventTrigger?.eventType,
        `providers/firebase.auth/eventTypes/user.${name === "onUserCreate" ? "create" : "delete"}`,
        name,
      );
      assert.equal(handler.__endpoint.eventTrigger.retry, true, name);
      assert.equal(handler.__endpoint.httpsTrigger, undefined, name);
    }
  } finally {
    if (previous === undefined) delete process.env.FIREBASE_CONFIG;
    else process.env.FIREBASE_CONFIG = previous;
    if (previousProject === undefined) delete process.env.GCLOUD_PROJECT;
    else process.env.GCLOUD_PROJECT = previousProject;
  }
});

test("selective Auth deploys confirm retry policy without allowing blanket deployment", () => {
  const args = deploymentArgs(["onUserCreate", "onUserCreate", "onUserDelete"]);
  assert.equal(args[1], "firebase-tools@14.22.0");
  assert.ok(args.includes("in-the-loop-306520"));
  assert.equal(args.at(-1), "functions:onUserCreate,functions:onUserDelete");
  assert.equal(args.includes("--force"), true);
});

test("deploys reject no names, retired writers, extensions and argument injection", () => {
  for (const names of [
    [],
    ["onUserDeleted"],
    ["deleteStreamUser"],
    ["notifyFoundersOnSignUp"],
    ["notifyFoundersOnUserDelete"],
    ["sendWelcomeEmailOnUserCreated"],
    ["inboundEmailWebhook"],
    ["streamBeforeMessageWebhook"],
    ["getArtistBySpotifyId"],
    ["getTopTracksByArtistId"],
    ["spotifyRedirect"],
    ["spotifyAuthorizeCodeGrant"],
    ["spotifyRefreshToken"],
    ["addUserToMailchimpOnCreated"],
    ["createDefaultServicesOnUserCreated"],
    ["setLatestContactRequest"],
    ["ext-auth-chat-createStreamUser"],
    ["createConnectedAccount"],
    ["createPaymentIntent"],
    ["getAccountById"],
    ["sendEmailOnSubscriptionPurchase"],
    ["sendEmailOnSubscriptionExpiration"],
    ["ext-firestore-stripe-payments-handleWebhookEvents"],
    ["ext-firestore-bigquery-export-fsexportbigquery"],
    ["ext-firestore-bigquery-export-73n7-syncBigQuery"],
    ["ext-firestore-bigquery-export-d85k-fsimportexistingdocs"],
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

test("Auth hooks contain only signed API forwarding and retry on failure", () => {
  const source = read("../src/lib/auth_hooks.ts");
  assert.doesNotMatch(
    source,
    /usersRef|\.collection\(|firebase-admin\/firestore|StreamChat|slackNotification|sendEmail/,
  );
  assert.match(source, /failurePolicy: true/);
  assert.match(source, /AUTH_WEBHOOK_SECRET/);
  assert.match(source, /\/webhooks\/firebase\/auth/);
  const entrypoint = read("../src/index.ts");
  assert.doesNotMatch(entrypoint, /from "\.\/lib\/(signups|email_triggers|stream)"/);
});

test("active webhook bridge contains no Firestore reads, writes or imports", () => {
  const source = read("../src/lib/webhooks.ts");
  assert.doesNotMatch(source, /usersRef|contactVenuesRef|\.collection\(|firebase-admin\/firestore/);
});
