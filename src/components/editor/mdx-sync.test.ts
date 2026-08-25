import { describe, expect, it } from "vitest";
import {
  consumeLocalMarkdownEcho,
  recordLocalMarkdownEcho,
} from "./mdx-sync";

describe("MDX editor prop synchronization", () => {
  it("does not reload intermediate autosave echoes during rapid typing", () => {
    const pending: string[] = [];
    recordLocalMarkdownEcho(pending, "H");
    recordLocalMarkdownEcho(pending, "He");
    recordLocalMarkdownEcho(pending, "Hel");

    expect(consumeLocalMarkdownEcho(pending, "H")).toBe(true);
    expect(pending).toEqual(["He", "Hel"]);
    expect(consumeLocalMarkdownEcho(pending, "Hel")).toBe(true);
    expect(pending).toEqual([]);
  });

  it("leaves genuine external changes for the editor to apply", () => {
    const pending = ["local edit"];

    expect(consumeLocalMarkdownEcho(pending, "changed on disk")).toBe(false);
    expect(pending).toEqual(["local edit"]);
  });
});
