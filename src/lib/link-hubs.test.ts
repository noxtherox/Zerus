import { describe, expect, it } from "vitest";
import {
  getLinkHubReference,
  linkDisplayName,
  linkMarkdown,
  setLinkHubReference,
  withoutLinkMarkdown,
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

  it("collapses editor-serialized and repeated copies of a saved URL", () => {
    const url = "https://claude.ai/design/p/0d3f7a78-c165-4509-9597-ec3933dc08d0?via=share&file=Live+View+Prototype.dc.html";
    const body = [
      "# Renamed link",
      "",
      `[${url}](${url})`,
      "",
      `<${url}>`,
      "",
      "Some context",
      "",
    ].join("\n");

    expect(withLinkMarkdown(body, url)).toBe(
      `# Renamed link\n\n[${url}](${url})\n\nSome context\n`,
    );
  });

  it("preserves a single editor-serialized saved URL byte-for-byte", () => {
    const url = "https://reddit.com/";
    const body = `# reddit.com\n\n[https://reddit.com/](https://reddit.com/)\n`;

    expect(withLinkMarkdown(body, url)).toBe(body);
  });

  it("removes the managed URL from the editable saved-link body", () => {
    const url = "https://reddit.com/";
    expect(
      withoutLinkMarkdown(
        `# Renamed link\n\n[https://reddit.com/](https://reddit.com/)\n\nNotes\n`,
        url,
      ),
    ).toBe("# Renamed link\n\nNotes\n");
  });

  it("does not remove the saved URL when it appears within prose", () => {
    const url = "https://example.com/path";
    expect(withLinkMarkdown(`# Link\n\nSee [the source](${url}) for details.\n`, url)).toBe(
      `# Link\n\n<${url}>\n\nSee [the source](${url}) for details.\n`,
    );
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
