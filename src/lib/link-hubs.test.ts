import { describe, expect, it } from "vitest";
import {
  getLinkHubReference,
  linkDisplayName,
  setLinkHubReference,
} from "./link-hubs";

describe("link hubs", () => {
  it("stores and reads a normalized web URL", () => {
    const content = setLinkHubReference("# Example\n", {
      id: "link-1",
      url: "https://example.com/path",
    });

    expect(getLinkHubReference(content)).toEqual({
      id: "link-1",
      url: "https://example.com/path",
    });
  });

  it("rejects unsafe or incomplete link metadata", () => {
    expect(
      getLinkHubReference("---\nzerus-link-id: link-1\nzerus-link-url: javascript:alert(1)\n---\n"),
    ).toBeNull();
    expect(getLinkHubReference("---\nzerus-link-url: example.com\n---\n")).toBeNull();
  });

  it("uses a readable hostname as the default display name", () => {
    expect(linkDisplayName("https://www.example.com/path")).toBe("example.com");
  });
});
