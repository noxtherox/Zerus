export const ZERUS_APPLE_TEAM_ID = "TX9RYY52XR";

const apiCredentialNames = [
  "APPLE_API_ISSUER",
  "APPLE_API_KEY",
  "APPLE_API_KEY_PATH",
];
const appleIdCredentialNames = [
  "APPLE_ID",
  "APPLE_PASSWORD",
  "APPLE_TEAM_ID",
];

export function parseDeveloperIdApplications(output) {
  return output
    .split("\n")
    .map((line) =>
      line.match(
        /^\s*\d+\)\s+([0-9A-F]{40})\s+"(Developer ID Application: [^"]+)"/,
      ),
    )
    .filter(Boolean)
    .map((match) => ({ fingerprint: match[1], name: match[2] }));
}

export function resolveSigningIdentity(requestedIdentity, identities) {
  if (requestedIdentity === "-") {
    throw new Error(
      "APPLE_SIGNING_IDENTITY=- is not allowed for a release build. Use pnpm desktop:build:local for an explicit ad-hoc build.",
    );
  }

  const teamIdentities = identities.filter((identity) =>
    identity.name.endsWith(`(${ZERUS_APPLE_TEAM_ID})`),
  );

  if (requestedIdentity) {
    const match = teamIdentities.find(
      (identity) =>
        identity.name === requestedIdentity ||
        identity.fingerprint === requestedIdentity,
    );
    if (!match) {
      throw new Error(
        `APPLE_SIGNING_IDENTITY does not identify an installed Zerus Developer ID Application certificate for team ${ZERUS_APPLE_TEAM_ID}.`,
      );
    }
    return requestedIdentity;
  }

  if (teamIdentities.length === 0) {
    throw new Error(
      `No valid Developer ID Application certificate is installed for Zerus team ${ZERUS_APPLE_TEAM_ID}.`,
    );
  }
  if (teamIdentities.length > 1) {
    const choices = teamIdentities
      .map((identity) => `${identity.fingerprint} (${identity.name})`)
      .join(", ");
    throw new Error(
      `Multiple Zerus Developer ID Application certificates are installed: ${choices}. Set APPLE_SIGNING_IDENTITY to the intended certificate fingerprint.`,
    );
  }

  return teamIdentities[0].name;
}

function presentCredentialNames(environment, names) {
  return names.filter((name) => Boolean(environment[name]?.trim()));
}

export function resolveNotaryCredentials(environment) {
  const presentApi = presentCredentialNames(environment, apiCredentialNames);
  const presentAppleId = presentCredentialNames(
    environment,
    appleIdCredentialNames,
  );

  if (presentApi.length === apiCredentialNames.length) {
    return {
      kind: "App Store Connect API key",
      args: [
        "--key",
        environment.APPLE_API_KEY_PATH,
        "--key-id",
        environment.APPLE_API_KEY,
        "--issuer",
        environment.APPLE_API_ISSUER,
      ],
    };
  }
  if (presentApi.length > 0) {
    const missing = apiCredentialNames.filter(
      (name) => !presentApi.includes(name),
    );
    throw new Error(
      `Incomplete App Store Connect notarization credentials. Missing: ${missing.join(", ")}.`,
    );
  }

  if (presentAppleId.length === appleIdCredentialNames.length) {
    return {
      kind: "Apple ID",
      args: [
        "--apple-id",
        environment.APPLE_ID,
        "--password",
        environment.APPLE_PASSWORD,
        "--team-id",
        environment.APPLE_TEAM_ID,
      ],
    };
  }
  if (presentAppleId.length > 0) {
    const missing = appleIdCredentialNames.filter(
      (name) => !presentAppleId.includes(name),
    );
    throw new Error(
      `Incomplete Apple ID notarization credentials. Missing: ${missing.join(", ")}.`,
    );
  }

  throw new Error(
    `Notarization credentials are required. Set ${apiCredentialNames.join(", ")} or ${appleIdCredentialNames.join(", ")}.`,
  );
}
