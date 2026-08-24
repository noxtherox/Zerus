const DESKTOP_VAULTS_KEY = "zerus.desktopVaults.v1";

export interface DesktopVaultEntry {
  name: string;
  path: string;
}

/** Returns a useful display name for POSIX and Windows vault paths. */
export function vaultNameFromPath(path: string): string {
  const trimmed = path.replace(/[\\/]+$/, "");
  return trimmed.split(/[\\/]/).filter(Boolean).pop() ?? path;
}

function uniquePaths(paths: unknown[]): string[] {
  const seen = new Set<string>();
  const result: string[] = [];
  for (const value of paths) {
    if (typeof value !== "string") continue;
    const path = value.trim();
    if (!path || seen.has(path)) continue;
    seen.add(path);
    result.push(path);
  }
  return result;
}

/** Loads the locally remembered desktop vaults, migrating the active vault. */
export function loadDesktopVaults(activePath?: string | null): DesktopVaultEntry[] {
  let paths: unknown[] = [];
  try {
    const saved = JSON.parse(localStorage.getItem(DESKTOP_VAULTS_KEY) ?? "[]");
    if (Array.isArray(saved)) paths = saved;
  } catch {
    // A damaged optional registry should not prevent the active vault opening.
  }
  const vaultPaths = uniquePaths(activePath ? [activePath, ...paths] : paths);
  return vaultPaths.map((path) => ({ name: vaultNameFromPath(path), path }));
}

/** Remembers a desktop vault and returns the updated registry. */
export function rememberDesktopVault(path: string): DesktopVaultEntry[] {
  const entries = loadDesktopVaults(path);
  try {
    localStorage.setItem(
      DESKTOP_VAULTS_KEY,
      JSON.stringify(entries.map((entry) => entry.path)),
    );
  } catch {
    // The vault can still be used for this session when persistence is blocked.
  }
  return entries;
}

/** Forgets a desktop vault without changing anything in its folder. */
export function forgetDesktopVault(path: string): DesktopVaultEntry[] {
  const entries = loadDesktopVaults().filter((entry) => entry.path !== path);
  try {
    localStorage.setItem(
      DESKTOP_VAULTS_KEY,
      JSON.stringify(entries.map((entry) => entry.path)),
    );
  } catch {
    // Keep the in-memory result useful when persistence is blocked.
  }
  return entries;
}
