import assert from "node:assert/strict";
import test from "node:test";
import { manifest, msixVersion, storeIdentity } from "./windows-msix.mjs";

test("release packaging requires a complete real Store identity", () => {
  assert.throws(() => storeIdentity({}), /Missing Partner Center/);
  assert.throws(() => storeIdentity({ MS_STORE_IDENTITY_NAME: "Zerus" }, true), /all three/);
  assert.equal(storeIdentity({}, true).name, "Zerus.Development");
});

test("Store version reserves revision zero and rejects unsupported versions", () => {
  assert.equal(msixVersion("0.3.17"), "1.3.17.0");
  assert.equal(msixVersion("1.0.0"), "2.0.0.0");
  for (const version of ["1.0.0-beta.1", "1.2.3.4", "65536.0.0", "01.2.3", "65535.0.0"]) {
    assert.throws(() => msixVersion(version));
  }
});

test("manifest escapes Partner Center identity and declares desktop execution", () => {
  const identity = storeIdentity({
    MS_STORE_IDENTITY_NAME: "12345.Zerus",
    MS_STORE_PUBLISHER: 'CN=Example, O="Notes & Files"',
    MS_STORE_PUBLISHER_DISPLAY_NAME: "Notes & Files",
  });
  const result = manifest("1.2.3", identity);
  assert.match(result, /Publisher="CN=Example, O=&quot;Notes &amp; Files&quot;"/);
  assert.match(result, /<PublisherDisplayName>Notes &amp; Files<\/PublisherDisplayName>/);
  assert.match(result, /Version="2.2.3.0" ProcessorArchitecture="x64"/);
  assert.match(result, /Executable="Zerus.exe" EntryPoint="Windows.FullTrustApplication"/);
  assert.match(result, /Name="runFullTrust"/);
  assert.throws(() => storeIdentity({
    MS_STORE_IDENTITY_NAME: "bad/name",
    MS_STORE_PUBLISHER: "CN=Example",
    MS_STORE_PUBLISHER_DISPLAY_NAME: "Example",
  }), /Invalid/);
});
