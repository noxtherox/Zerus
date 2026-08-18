import {
  getNoteProperties,
  setContentProperty,
  type PropertyValue,
} from "@/lib/frontmatter";
import { normalizeFsPath, type Note } from "@/lib/note-utils";

export const FILE_HUB_KEYS = {
  id: "zerus-file-id",
  name: "zerus-file-name",
  kind: "zerus-file-kind",
  location: "zerus-file-location",
  path: "zerus-file-path",
  managed: "zerus-file-managed",
} as const;

export const FILE_HUB_PROPERTY_KEYS = new Set<string>(
  Object.values(FILE_HUB_KEYS).map((key) => key.toLowerCase()),
);

export type FileHubKind = "vault" | "location" | "local";

export interface FileHubReference {
  id: string;
  name: string;
  kind: FileHubKind;
  /** Vault- or base-location-relative path, always using forward slashes. */
  path?: string;
  locationId?: string;
  /** True only for a file Zerus explicitly copied into the vault. */
  managed: boolean;
}

export interface FileLocationDefinition {
  id: string;
  name: string;
}

export interface FileLocationsDocument {
  version: 1;
  locations: FileLocationDefinition[];
}

export interface ResolvedFileHub {
  reference: FileHubReference;
  absolutePath: string | null;
  location: FileLocationDefinition | null;
  missingMapping: boolean;
}

function scalarString(value: PropertyValue | undefined): string | undefined {
  if (typeof value !== "string") return undefined;
  const trimmed = value.trim();
  return trimmed || undefined;
}

export function normalizeRelativeFilePath(path: string): string | null {
  const normalized = path.replace(/\\/g, "/").replace(/^\.\//, "");
  if (
    !normalized ||
    normalized.startsWith("/") ||
    /^[a-z]:\//i.test(normalized) ||
    normalized.split("/").some((segment) => !segment || segment === "." || segment === "..") ||
    normalized.includes("\0")
  ) {
    return null;
  }
  return normalized;
}

export function fileNameFromPath(path: string): string {
  return path.split(/[\\/]/).filter(Boolean).pop() || "Document";
}

export function fileExtension(name: string): string {
  const match = name.toLowerCase().match(/\.([a-z0-9]+)$/);
  return match?.[1] ?? "";
}

export function isMarkdownFilePath(path: string): boolean {
  return ["md", "markdown"].includes(fileExtension(path));
}

export function getFileHubReference(
  noteOrContent: Note | string,
): FileHubReference | null {
  const content = typeof noteOrContent === "string" ? noteOrContent : noteOrContent.content;
  const props = getNoteProperties(content);
  const id = scalarString(props[FILE_HUB_KEYS.id]);
  const name = scalarString(props[FILE_HUB_KEYS.name]);
  const kind = scalarString(props[FILE_HUB_KEYS.kind]);
  if (!id || !name || (kind !== "vault" && kind !== "location" && kind !== "local")) {
    return null;
  }
  const path = scalarString(props[FILE_HUB_KEYS.path]);
  const locationId = scalarString(props[FILE_HUB_KEYS.location]);
  if ((kind === "vault" || kind === "location") && !normalizeRelativeFilePath(path ?? "")) {
    return null;
  }
  if (kind === "location" && !locationId) return null;
  return {
    id,
    name,
    kind,
    path: path ? normalizeRelativeFilePath(path) ?? undefined : undefined,
    locationId,
    managed: props[FILE_HUB_KEYS.managed] === true,
  };
}

export function setFileHubReference(
  content: string,
  reference: FileHubReference,
): string {
  let next = content;
  const entries: Array<[string, PropertyValue | null]> = [
    [FILE_HUB_KEYS.id, reference.id],
    [FILE_HUB_KEYS.name, reference.name],
    [FILE_HUB_KEYS.kind, reference.kind],
    [FILE_HUB_KEYS.location, reference.locationId ?? null],
    [FILE_HUB_KEYS.path, reference.path ?? null],
    [FILE_HUB_KEYS.managed, reference.managed || null],
  ];
  for (const [key, value] of entries) next = setContentProperty(next, key, value);
  return next;
}

export function removeFileHubReference(content: string): string {
  let next = content;
  for (const key of Object.values(FILE_HUB_KEYS)) {
    next = setContentProperty(next, key, null);
  }
  return next;
}

export function pathInsideRoot(root: string, absolutePath: string): string | null {
  const normalizedRoot = normalizeFsPath(root).replace(/\/$/, "");
  const normalizedPath = normalizeFsPath(absolutePath);
  const prefix = `${normalizedRoot}/`;
  if (!normalizedPath.startsWith(prefix)) return null;
  return normalizeRelativeFilePath(normalizedPath.slice(prefix.length));
}

export function mostSpecificLocation(
  absolutePath: string,
  locations: FileLocationDefinition[],
  mappings: Record<string, string>,
): { location: FileLocationDefinition; path: string } | null {
  const candidates = locations
    .map((location) => {
      const root = mappings[location.id];
      const path = root ? pathInsideRoot(root, absolutePath) : null;
      return path ? { location, path, rootLength: normalizeFsPath(root).length } : null;
    })
    .filter((candidate): candidate is NonNullable<typeof candidate> => candidate !== null)
    .sort((a, b) => b.rootLength - a.rootLength);
  const match = candidates[0];
  return match ? { location: match.location, path: match.path } : null;
}

export function resolveFileHubReference(
  reference: FileHubReference,
  vaultRoot: string | null,
  locations: FileLocationDefinition[],
  locationMappings: Record<string, string>,
  fileMappings: Record<string, string>,
): ResolvedFileHub {
  const location =
    reference.kind === "location"
      ? locations.find((candidate) => candidate.id === reference.locationId) ?? null
      : null;
  const override = fileMappings[reference.id];
  if (override) {
    return { reference, absolutePath: override, location, missingMapping: false };
  }
  if (reference.kind === "local") {
    return { reference, absolutePath: null, location: null, missingMapping: true };
  }
  const root =
    reference.kind === "vault"
      ? vaultRoot
      : reference.locationId
        ? locationMappings[reference.locationId]
        : null;
  return {
    reference,
    absolutePath: root && reference.path ? `${root.replace(/[\\/]$/, "")}/${reference.path}` : null,
    location,
    missingMapping: !root,
  };
}

export function parseFileLocations(raw: string): FileLocationDefinition[] {
  try {
    const parsed = JSON.parse(raw) as Partial<FileLocationsDocument>;
    if (parsed.version !== 1 || !Array.isArray(parsed.locations)) return [];
    const seen = new Set<string>();
    return parsed.locations.filter((location): location is FileLocationDefinition => {
      if (!location || typeof location.id !== "string" || typeof location.name !== "string") return false;
      const valid = !!location.id && !!location.name.trim() && !seen.has(location.id);
      if (valid) seen.add(location.id);
      return valid;
    });
  } catch {
    return [];
  }
}

export function serializeFileLocations(locations: FileLocationDefinition[]): string {
  return JSON.stringify({ version: 1, locations } satisfies FileLocationsDocument, null, 2);
}
