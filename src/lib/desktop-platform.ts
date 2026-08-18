export type DesktopPlatform = "macos" | "windows" | "linux";

export function detectDesktopPlatform(
  userAgent = typeof navigator === "undefined" ? "" : navigator.userAgent,
): DesktopPlatform {
  if (/windows/i.test(userAgent)) return "windows";
  if (/macintosh|mac os x/i.test(userAgent)) return "macos";
  return "linux";
}

export const desktopPlatform = detectDesktopPlatform();
export const primaryModifierLabel =
  desktopPlatform === "macos" ? "⌘" : "Ctrl";
export const fileManagerName =
  desktopPlatform === "windows"
    ? "File Explorer"
    : desktopPlatform === "macos"
      ? "Finder"
      : "file manager";

export function quoteTerminalArgument(
  value: string,
  platform = desktopPlatform,
): string {
  if (platform === "windows") {
    return `"${value.replace(/"/g, '""')}"`;
  }
  return `'${value.replace(/'/g, `'\\''`)}'`;
}
