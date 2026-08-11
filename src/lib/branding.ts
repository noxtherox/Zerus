export type LogoStyle = "graphite" | "white";

const LOGO_SOURCES: Record<LogoStyle, string> = {
  graphite: "/zerus-logo.svg",
  white: "/zerus-logo-white.svg",
};

export function getLogoSrc(style: LogoStyle): string {
  return LOGO_SOURCES[style];
}

function relativeLuminance(hex: string): number {
  const value = hex.trim().replace(/^#/, "");
  const normalized =
    value.length === 3
      ? [...value].map((character) => character + character).join("")
      : value;
  if (!/^[0-9a-fA-F]{6}$/.test(normalized)) return 0;

  const channels = [0, 2, 4].map((offset) => {
    const channel = parseInt(normalized.slice(offset, offset + 2), 16) / 255;
    return channel <= 0.04045
      ? channel / 12.92
      : ((channel + 0.055) / 1.055) ** 2.4;
  });

  return 0.2126 * channels[0] + 0.7152 * channels[1] + 0.0722 * channels[2];
}

export function applyLogoForSidebar(sidebarBackground: string): void {
  const style: LogoStyle =
    relativeLuminance(sidebarBackground) < 0.4 ? "white" : "graphite";
  document.documentElement.dataset.grimSidebarTone =
    style === "white" ? "dark" : "light";
}
