import assert from "node:assert/strict";
import test from "node:test";
import {
  parseDeveloperIdApplications,
  resolveNotaryCredentials,
  resolveSigningIdentity,
} from "./macos-release-utils.mjs";

const identity = {
  fingerprint: "4533012CE72D14E7C7CEBC748E7CA10AFAEC32F4",
  name: "Developer ID Application: Tiago Honrado Rio Pereira (TX9RYY52XR)",
};

test("parses valid Developer ID Application identities", () => {
  const output = `  1) ${identity.fingerprint} "${identity.name}"\n  2) ABC "Apple Development: Example"`;
  assert.deepEqual(parseDeveloperIdApplications(output), [identity]);
});

test("auto-selects the single Zerus Developer ID identity", () => {
  assert.equal(resolveSigningIdentity(undefined, [identity]), identity.name);
});

test("rejects ad-hoc and ambiguous release identities", () => {
  assert.throws(() => resolveSigningIdentity("-", [identity]), /not allowed/);
  assert.throws(
    () =>
      resolveSigningIdentity(undefined, [
        identity,
        { ...identity, fingerprint: "A".repeat(40) },
      ]),
    /Multiple Zerus/,
  );
});

test("resolves complete API credentials and rejects partial credentials", () => {
  assert.deepEqual(
    resolveNotaryCredentials({
      APPLE_API_ISSUER: "issuer",
      APPLE_API_KEY: "key-id",
      APPLE_API_KEY_PATH: "/tmp/key.p8",
    }),
    {
      kind: "App Store Connect API key",
      args: [
        "--key",
        "/tmp/key.p8",
        "--key-id",
        "key-id",
        "--issuer",
        "issuer",
      ],
    },
  );
  assert.throws(
    () => resolveNotaryCredentials({ APPLE_API_KEY: "key-id" }),
    /APPLE_API_ISSUER, APPLE_API_KEY_PATH/,
  );
});

test("resolves complete Apple ID credentials", () => {
  assert.equal(
    resolveNotaryCredentials({
      APPLE_ID: "developer@example.com",
      APPLE_PASSWORD: "app-password",
      APPLE_TEAM_ID: "TX9RYY52XR",
    }).kind,
    "Apple ID",
  );
});
