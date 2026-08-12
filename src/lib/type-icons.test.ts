import { describe, expect, it } from "vitest";
import {
  isEmojiValue,
  isTypeIconValue,
  suggestIconForType,
  tablerIconName,
  tablerIconValue,
} from "./type-icons";

describe("type icon values", () => {
  it("round-trips namespaced Tabler icon names", () => {
    const value = tablerIconValue("Book2");
    expect(value).toBe("tabler:Book2");
    expect(tablerIconName(value)).toBe("Book2");
    expect(isTypeIconValue(value)).toBe(true);
  });

  it("keeps native emoji values for backwards compatibility", () => {
    expect(isEmojiValue("📚")).toBe(true);
    expect(isTypeIconValue("📚")).toBe(true);
  });

  it("rejects obsolete and malformed icon names", () => {
    expect(isTypeIconValue("Briefcase")).toBe(false);
    expect(tablerIconName("tabler:../../Book")).toBeNull();
    expect(isEmojiValue("tabler:Book")).toBe(false);
  });
});

describe("type icon suggestions", () => {
  it("suggests namespaced Tabler icons for known concepts", async () => {
    await expect(suggestIconForType("Recipes")).resolves.toBe("tabler:ChefHat");
    await expect(suggestIconForType("Work projects")).resolves.toBe("tabler:Briefcase");
  });

  it("leaves unknown concepts on the default folder", async () => {
    await expect(suggestIconForType("zyxwvu")).resolves.toBeNull();
  });
});
