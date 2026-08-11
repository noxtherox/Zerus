import { describe, expect, it } from "vitest";
import { icons } from "@tabler/icons-react";
import {
  isTypeIconValue,
  suggestedTablerIconNames,
  suggestIconForType,
  tablerIconName,
  tablerIconValue,
} from "./type-icons";

describe("type icon values", () => {
  it("round-trips namespaced Tabler icon names", () => {
    expect(tablerIconValue("Briefcase")).toBe("tabler:Briefcase");
    expect(tablerIconName("tabler:Briefcase")).toBe("Briefcase");
    expect(isTypeIconValue("tabler:Briefcase")).toBe(true);
  });

  it("rejects emoji, obsolete Lucide names, and malformed values", () => {
    expect(isTypeIconValue("📚")).toBe(false);
    expect(isTypeIconValue("Briefcase")).toBe(false);
    expect(tablerIconName("tabler:../../Book")).toBeNull();
  });
});

describe("type icon suggestions", () => {
  it("suggests Tabler icons for known concepts", async () => {
    await expect(suggestIconForType("Recipes")).resolves.toBe("tabler:ChefHat");
    await expect(suggestIconForType("Work projects")).resolves.toBe("tabler:Briefcase");
  });

  it("leaves unknown concepts on the default folder", async () => {
    await expect(suggestIconForType("zyxwvu")).resolves.toBeNull();
  });

  it("keeps every curated suggestion available in Tabler", () => {
    for (const name of suggestedTablerIconNames) {
      expect(icons[`Icon${name}`]).toBeDefined();
    }
  });
});
