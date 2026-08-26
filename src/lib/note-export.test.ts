import { describe, expect, it } from "vitest";
import {
  createNoteExport,
  parseNoteForExport,
  type NoteExportFormat,
} from "./note-export";
import type { Note } from "./note-utils";

function fixture(content: string): Note {
  return {
    id: "export-note",
    path: "work/Export example.md",
    content,
    pinned: false,
    updatedAt: "2026-08-26T00:00:00.000Z",
  };
}

const CONTENT = `---
status: draft
zerus-id: hidden-id
---
# Export example

Hello **world**. See [[Project Atlas|the project]].

- [x] Parsed Markdown
- [ ] Exported file

| Format | Ready |
| --- | --- |
| HTML | Yes |
`;

describe("note export parsing", () => {
  it("removes frontmatter nodes and converts wikilinks to semantic links", () => {
    const tree = parseNoteForExport(fixture(CONTENT));
    expect(tree.children.some((child) => child.type === "yaml")).toBe(false);
    expect(JSON.stringify(tree)).toContain("zerus-note:Project%20Atlas");
    expect(JSON.stringify(tree)).toContain("the project");
  });

  it("keeps wikilinks from the older escaped typing behavior active", () => {
    const tree = parseNoteForExport(fixture("# Note\n\nOpen \\[[Legacy note]]"));
    expect(JSON.stringify(tree)).toContain("zerus-note:Legacy%20note");
  });
});

describe("note export renderers", () => {
  it("creates self-contained, sanitized HTML with visible properties", async () => {
    const artifact = await createNoteExport(
      fixture(`${CONTENT}\n<script>alert('no')</script>`),
      "html",
      { includeProperties: true },
      async () => null,
    );
    const html = await artifact.blob.text();
    expect(artifact.fileName).toBe("Export example.html");
    expect(html).toContain("<!doctype html>");
    expect(html).toContain("status");
    expect(html).toContain("draft");
    expect(html).not.toContain("hidden-id");
    expect(html).not.toContain("<script>");
    expect(html).toContain("the project");
    expect(html).not.toContain("zerus-note:");
  });

  it("embeds local HTML images and keeps their Zerus display width", async () => {
    const artifact = await createNoteExport(
      fixture("# Images\n\n![Diagram|320](assets/diagram.png)"),
      "html",
      { includeProperties: false },
      async () => new Uint8Array([137, 80, 78, 71]),
    );
    const html = await artifact.blob.text();
    expect(html).toContain('src="data:image/png;base64,');
    expect(html).toContain('alt="Diagram"');
    expect(html).toContain('style="width:320px;max-width:100%"');
  });

  it.each<NoteExportFormat>(["docx", "pdf"])(
    "creates a non-empty %s document",
    async (format) => {
      const artifact = await createNoteExport(
        fixture(CONTENT),
        format,
        { includeProperties: true },
        async () => null,
      );
      expect(artifact.fileName).toBe(`Export example.${format}`);
      expect(artifact.blob.size).toBeGreaterThan(1_000);
    },
    20_000,
  );

  it("writes plain-text PDF outline labels for Firefox", async () => {
    const artifact = await createNoteExport(
      fixture("# Project Polaris\n\n## Launch **readiness**\n\nStatus update."),
      "pdf",
      { includeProperties: false },
      async () => null,
    );
    const { getDocument } = await import("pdfjs-dist/legacy/build/pdf.mjs");
    const loadingTask = getDocument({
      data: new Uint8Array(await artifact.blob.arrayBuffer()),
    });
    const document = await loadingTask.promise;

    try {
      const outline = await document.getOutline();
      expect(outline?.map((item) => item.title)).toEqual([
        "Project Polaris",
        "Launch readiness",
      ]);
    } finally {
      await loadingTask.destroy();
    }
  }, 20_000);
});
