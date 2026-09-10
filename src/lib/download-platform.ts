export type DownloadPlatform = "windows" | "macos" | "other";

type DeviceInfo = {
  userAgent?: string;
  platform?: string;
  maxTouchPoints?: number;
  userAgentData?: { platform?: string };
};

export function detectDownloadPlatform(device: DeviceInfo): DownloadPlatform {
  const userAgent = device.userAgent ?? "";
  const platform = device.userAgentData?.platform ?? device.platform ?? "";

  // iPadOS can advertise itself as a Mac when requesting desktop websites.
  if (/android|iphone|ipad|ipod/i.test(userAgent) ||
      (/mac/i.test(platform + userAgent) && (device.maxTouchPoints ?? 0) > 1)) {
    return "other";
  }
  if (/windows|win32|win64/i.test(platform + userAgent)) return "windows";
  if (/mac/i.test(platform + userAgent)) return "macos";
  return "other";
}

export function getDownloadOption(platform: DownloadPlatform) {
  if (platform === "other") {
    return {
      href: "https://github.com/noxtherox/zerus/releases/latest",
      label: "View downloads",
      detail: "Available for macOS and Windows",
    };
  }
  return {
    href: `/api/download?platform=${platform}`,
    label: `Download for ${platform === "windows" ? "Windows" : "macOS"}`,
    detail: platform === "windows" ? "Windows 10/11" : "macOS · Apple silicon",
  };
}
