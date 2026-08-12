const STORAGE_KEY = "grimoire.mobileDiagnostics.v1";
const MAX_ENTRIES = 160;

interface DiagnosticEntry {
  at: string;
  event: string;
  detail?: Record<string, unknown>;
}

function redact(value: unknown): unknown {
  if (typeof value === "string") {
    return value
      .replace(/file:\/\/[^\n\r"']+/gi, "file://…")
      .replace(/\/(?:private\/)?var\/mobile\/[^\s"']+/gi, "/var/mobile/…");
  }
  if (value instanceof Error) {
    return { name: value.name, message: redact(value.message) };
  }
  if (Array.isArray(value)) return value.map(redact);
  if (value && typeof value === "object") {
    return Object.fromEntries(
      Object.entries(value).map(([key, item]) => [key, redact(item)]),
    );
  }
  return value;
}

function readEntries(): DiagnosticEntry[] {
  if (typeof localStorage === "undefined") return [];
  try {
    const parsed = JSON.parse(localStorage.getItem(STORAGE_KEY) ?? "[]") as unknown;
    return Array.isArray(parsed) ? (parsed as DiagnosticEntry[]) : [];
  } catch {
    return [];
  }
}

export function mobileDiagnostic(
  event: string,
  detail?: Record<string, unknown>,
): void {
  const entry: DiagnosticEntry = {
    at: new Date().toISOString(),
    event,
    ...(detail ? { detail: redact(detail) as Record<string, unknown> } : {}),
  };
  console.info("Grimoire mobile diagnostic", entry);
  if (typeof localStorage === "undefined") return;
  try {
    const entries = [...readEntries(), entry].slice(-MAX_ENTRIES);
    localStorage.setItem(STORAGE_KEY, JSON.stringify(entries));
  } catch {
    // Diagnostics must never interfere with opening the vault.
  }
}

export function clearMobileDiagnostics(): void {
  if (typeof localStorage !== "undefined") localStorage.removeItem(STORAGE_KEY);
}

export function getMobileDiagnostics(): string {
  const header = [
    "Grimoire mobile diagnostics",
    `Generated: ${new Date().toISOString()}`,
    `User agent: ${typeof navigator === "undefined" ? "unavailable" : navigator.userAgent}`,
    "Privacy: note contents and device file paths are not included.",
    "",
  ];
  const lines = readEntries().map((entry) => {
    const detail = entry.detail ? ` ${JSON.stringify(entry.detail)}` : "";
    return `${entry.at} ${entry.event}${detail}`;
  });
  return [...header, ...(lines.length ? lines : ["No diagnostic events yet."])].join("\n");
}
