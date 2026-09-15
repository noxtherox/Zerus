import { beforeEach, describe, expect, it, vi } from "vitest";
import { checkForAppUpdate, installAppUpdate, type AppUpdate } from "./app-update";

const mocks = vi.hoisted(() => ({ invoke: vi.fn(), check: vi.fn(), relaunch: vi.fn() }));
vi.mock("@tauri-apps/api/core", () => ({ invoke: mocks.invoke }));
vi.mock("@tauri-apps/plugin-updater", () => ({ check: mocks.check }));
vi.mock("@tauri-apps/plugin-process", () => ({ relaunch: mocks.relaunch }));

beforeEach(() => vi.resetAllMocks());

describe("update channels", () => {
  it("checks the Store without contacting the direct updater", async () => {
    mocks.invoke.mockResolvedValueOnce("noxtherox.Zerus_1.3.24.0_x64__publisher");
    const update = await checkForAppUpdate("ms-store");
    expect(mocks.invoke).toHaveBeenCalledWith("check_store_update");
    expect(mocks.check).not.toHaveBeenCalled();
    expect(update?.source).toBe("ms-store");
    expect(update?.version).toMatch(/^ms-store:/);
    mocks.invoke.mockResolvedValueOnce("canceled");
    expect(await update?.downloadAndInstall(vi.fn())).toBe("canceled");
    expect(mocks.invoke).toHaveBeenLastCalledWith("install_store_update");
  });

  it("does not offer an update when the Store reports none", async () => {
    mocks.invoke.mockResolvedValue(null);
    expect(await checkForAppUpdate("ms-store")).toBeNull();
  });

  it("does not fall back to direct updates when the Store is unavailable", async () => {
    mocks.invoke.mockRejectedValue(new Error("Store unavailable"));
    await expect(checkForAppUpdate("ms-store")).rejects.toThrow("Store unavailable");
    expect(mocks.check).not.toHaveBeenCalled();
  });

  it("preserves direct updater metadata and resource cleanup", async () => {
    const close = vi.fn().mockResolvedValue(undefined);
    const downloadAndInstall = vi.fn().mockResolvedValue(undefined);
    mocks.check.mockResolvedValue({ version: "0.3.25", body: "Release notes", close, downloadAndInstall });
    const update = await checkForAppUpdate(undefined);
    expect(mocks.invoke).not.toHaveBeenCalled();
    expect(update).toMatchObject({ source: "direct", version: "0.3.25", body: "Release notes" });
    const progress = vi.fn();
    await update?.downloadAndInstall(progress);
    expect(downloadAndInstall).toHaveBeenCalledWith(progress);
    await update?.close();
    expect(close).toHaveBeenCalledOnce();
  });
});

describe("saving before installation", () => {
  function update(source: AppUpdate["source"] = "ms-store"): AppUpdate {
    return { source, version: "test", close: vi.fn(), downloadAndInstall: vi.fn().mockResolvedValue("completed") };
  }

  it("waits for pending saves to finish before asking Microsoft to install", async () => {
    let finishSave!: (saved: boolean) => void;
    const save = () => new Promise<boolean>((resolve) => { finishSave = resolve; });
    const pending = update();
    const result = installAppUpdate(pending, save, vi.fn());
    expect(pending.downloadAndInstall).not.toHaveBeenCalled();
    finishSave(true);
    expect(await result).toBe("completed");
    expect(pending.downloadAndInstall).toHaveBeenCalledOnce();
    expect(mocks.relaunch).not.toHaveBeenCalled();
  });

  it("blocks installation when saving fails or conflicts remain", async () => {
    const pending = update();
    await expect(installAppUpdate(pending, async () => false, vi.fn())).rejects.toThrow("could not be saved");
    expect(pending.downloadAndInstall).not.toHaveBeenCalled();
    expect(mocks.relaunch).not.toHaveBeenCalled();
  });

  it("blocks installation if saving throws", async () => {
    const pending = update();
    await expect(installAppUpdate(pending, async () => { throw new Error("Disk full"); }, vi.fn())).rejects.toThrow("Disk full");
    expect(pending.downloadAndInstall).not.toHaveBeenCalled();
  });

  it.each(["canceled", "up-to-date"] as const)("returns %s without restarting the app", async (result) => {
    const pending = update();
    vi.mocked(pending.downloadAndInstall).mockResolvedValue(result);
    expect(await installAppUpdate(pending, async () => true, vi.fn())).toBe(result);
    expect(mocks.relaunch).not.toHaveBeenCalled();
  });

  it("relaunches direct builds only after a successful installation", async () => {
    const pending = update("direct");
    await installAppUpdate(pending, async () => true, vi.fn());
    expect(mocks.relaunch).toHaveBeenCalledOnce();
    expect(vi.mocked(pending.downloadAndInstall).mock.invocationCallOrder[0]).toBeLessThan(mocks.relaunch.mock.invocationCallOrder[0]);
  });
});
