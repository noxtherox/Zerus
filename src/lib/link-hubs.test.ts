import { describe, expect, it } from "vitest";
import {
  getLinkHubReference,
  linkDisplayName,
  linkMarkdown,
  setLinkHubReference,
  withLinkMarkdown,
} from "./link-hubs";
import { filterNotes } from "./filters";
import { buildTypeTree, type Note } from "./note-utils";

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

  it("puts the canonical URL beneath the editable note title", () => {
    expect(linkMarkdown("https://example.com/path?q=one")).toBe(
      "<https://example.com/path?q=one>",
    );
  });

  it("shows the URL beneath existing link-note titles without duplicating it", () => {
    const body = withLinkMarkdown(
      "# Renamed link\n\nSome context\n",
      "https://example.com/path",
    );
    expect(body).toBe(
      "# Renamed link\n\n<https://example.com/path>\n\nSome context\n",
    );
    expect(withLinkMarkdown(body, "https://example.com/path")).toBe(body);
  });

  it("keeps saved links out of All Notes and the type tree", () => {
    const link: Note = {
      id: "link-1",
      path: "inbox/example.md",
      content: setLinkHubReference("# example.com\n", {
        id: "link-1",
        url: "https://example.com",
      }),
      pinned: false,
      updatedAt: "2026-08-13T12:00:00.000Z",
    };

    expect(filterNotes([link], { kind: "all" }, "")).toEqual([]);
    expect(filterNotes([link], { kind: "links" }, "")).toEqual([link]);
    expect(buildTypeTree([link])).toEqual([]);
  });
});
