import { execFileSync } from "node:child_process";
import {
  mkdtempSync,
  readFileSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import { homedir, tmpdir } from "node:os";
import { join } from "node:path";

const config = JSON.parse(readFileSync("src-tauri/tauri.conf.json", "utf8"));
const configuredPublicKey = config.plugins?.updater?.pubkey;

if (!configuredPublicKey) {
  throw new Error("The updater public key is missing from tauri.conf.json.");
}

const unwrapMinisignText = (value) => {
  let text = value.trim();

  for (let depth = 0; depth < 2; depth += 1) {
    if (text.startsWith("untrusted comment:")) return text;
    text = Buffer.from(text, "base64").toString("utf8").trim();
  }

  throw new Error("Could not decode updater signing data.");
};

const keyId = (minisignText) => {
  const encodedLine = minisignText
    .split(/\r?\n/)
    .find((line) => /^[A-Za-z0-9+/]+={0,2}$/.test(line.trim()));

  if (!encodedLine) throw new Error("Updater signing data has no key payload.");

  const bytes = Buffer.from(encodedLine.trim(), "base64");
  if (bytes.length < 10) throw new Error("Updater signing data is truncated.");
  return bytes.subarray(2, 10).toString("hex");
};

const signingEnvironment = { ...process.env };
if (!signingEnvironment.TAURI_SIGNING_PRIVATE_KEY) {
  signingEnvironment.TAURI_SIGNING_PRIVATE_KEY_PATH ??= join(
    homedir(),
    ".tauri",
    "zerus-updater.key",
  );
}
signingEnvironment.TAURI_SIGNING_PRIVATE_KEY_PASSWORD ??= "";

const temporaryDirectory = mkdtempSync(join(tmpdir(), "zerus-key-check-"));
const payloadPath = join(temporaryDirectory, "payload");

try {
  writeFileSync(payloadPath, "Zerus updater signing key verification\n");
  execFileSync(
    "pnpm",
    ["exec", "tauri", "signer", "sign", payloadPath],
    {
      env: signingEnvironment,
      stdio: "pipe",
    },
  );

  const signature = unwrapMinisignText(
    readFileSync(`${payloadPath}.sig`, "utf8"),
  );
  const publicKey = unwrapMinisignText(configuredPublicKey);

  if (keyId(signature) !== keyId(publicKey)) {
    throw new Error(
      "The updater private key does not match the public key in tauri.conf.json.",
    );
  }

  console.log("Updater signing private and public keys match.");
} catch (error) {
  if (error instanceof Error && error.message.startsWith("The updater")) {
    throw error;
  }
  throw new Error(
    "Could not create an updater test signature. Check the signing key and password.",
    { cause: error },
  );
} finally {
  rmSync(temporaryDirectory, { recursive: true, force: true });
}
