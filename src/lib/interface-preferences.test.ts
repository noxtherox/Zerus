import { beforeEach, describe, expect, it, vi } from "vitest";
import { isTauri } from "@tauri-apps/api/core";
import { getCurrentWebview } from "@tauri-apps/api/webview";
import {
  applyInterfaceZoom,
  DEFAULT_INTERFACE_ZOOM,
  loadInterfaceZoom,
  saveInterfaceZoom,
} from "./interface-preferences";

vi.mock("@tauri-apps/api/core", () => ({
  isTauri: vi.fn(() => false),
}));

vi.mock("@tauri-apps/api/webview", () => ({
  getCurrentWebview: vi.fn(),
}));

const mockedIsTauri = vi.mocked(isTauri);
const mockedGetCurrentWebview = vi.mocked(getCurrentWebview);

const values = new Map<string, string>();
const styles = new Map<string, string>();

beforeEach(() => {
  values.clear();
  styles.clear();
  mockedIsTauri.mockReturnValue(false);
  mockedGetCurrentWebview.mockReset();
  vi.stubGlobal("localStorage", {
    getItem: (key: string) => values.get(key) ?? null,
    setItem: (key: string, value: string) => values.set(key, value),
  });
  vi.stubGlobal("document", {
    documentElement: {
      style: {
        setProperty: (key: string, value: string) => styles.set(key, value),
        removeProperty: (key: string) => {
          const value = styles.get(key) ?? "";
          styles.delete(key);
          return value;
        },
        getPropertyValue: (key: string) => styles.get(key) ?? "",
        get fontSize() {
          return styles.get("font-size") ?? "";
        },
        set fontSize(value: string) {
          styles.set("font-size", value);
        },
      },
    },
  });
});

describe("interface zoom preference", () => {
  it("uses 100% when there is no valid saved preference", () => {
    expect(loadInterfaceZoom()).toBe(DEFAULT_INTERFACE_ZOOM);
    values.set("zerus.interfaceZoom", "115");
    expect(loadInterfaceZoom()).toBe(DEFAULT_INTERFACE_ZOOM);
  });

  it("saves and immediately applies a supported zoom", () => {
    saveInterfaceZoom(125);

    expect(loadInterfaceZoom()).toBe(125);
    expect(document.documentElement.style.fontSize).toBe("125%");
    expect(document.documentElement.style.getPropertyValue("zoom")).toBe("");
  });

  it("can apply zoom without persisting it", () => {
    applyInterfaceZoom(90);

    expect(values.has("zerus.interfaceZoom")).toBe(false);
    expect(document.documentElement.style.fontSize).toBe("90%");
  });

  it("removes legacy CSS zoom before applying the reflowing zoom", () => {
    styles.set("zoom", "1.5");

    applyInterfaceZoom(110);

    expect(document.documentElement.style.getPropertyValue("zoom")).toBe("");
    expect(document.documentElement.style.fontSize).toBe("110%");
  });

  it("uses native webview zoom in the desktop app", () => {
    const setZoom = vi.fn(() => Promise.resolve());
    mockedIsTauri.mockReturnValue(true);
    mockedGetCurrentWebview.mockReturnValue({ setZoom } as never);

    applyInterfaceZoom(150);

    expect(setZoom).toHaveBeenCalledWith(1.5);
    expect(document.documentElement.style.fontSize).toBe("");
    expect(document.documentElement.style.getPropertyValue("zoom")).toBe("");
  });
});
