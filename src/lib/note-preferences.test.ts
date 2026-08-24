import { beforeEach, describe, expect, it, vi } from "vitest";
import {
  applyNoteAlignment,
  applyNoteWidth,
  DEFAULT_NOTE_ALIGNMENT,
  DEFAULT_NOTE_WIDTH,
  DEFAULT_EDITOR_MODE,
  DEFAULT_MARKDOWN_TYPING_ENABLED,
  loadEditorMode,
  loadMarkdownTypingEnabled,
  loadDefaultNoteType,
  loadFileHubExpandedSection,
  loadHtmlPreviewMode,
  loadHtmlPreviewPreference,
  loadHideSubtypeNotes,
  loadNoteAlignment,
  loadNoteWidth,
  loadNoteTypeOrder,
  saveDefaultNoteType,
  saveEditorMode,
  saveMarkdownTypingEnabled,
  saveFileHubExpandedSection,
  saveHtmlPreviewMode,
  saveHideSubtypeNotes,
  saveNoteAlignment,
  saveNoteWidth,
  saveNoteTypeOrder,
} from "./note-preferences";

const values = new Map<string, string>();
const styles = new Map<string, string>();

beforeEach(() => {
  values.clear();
  styles.clear();
  vi.stubGlobal("localStorage", {
    getItem: (key: string) => values.get(key) ?? null,
    setItem: (key: string, value: string) => values.set(key, value),
  });
  vi.stubGlobal("document", {
    documentElement: {
      style: {
        setProperty: (key: string, value: string) => styles.set(key, value),
        getPropertyValue: (key: string) => styles.get(key) ?? "",
      },
    },
  });
});

describe("note type order preference", () => {
  it("saves an order independently for each vault", () => {
    saveNoteTypeOrder("/vault/one", ["work", "inbox", "work/projects"]);

    expect(loadNoteTypeOrder("/vault/one")).toEqual([
      "work",
      "inbox",
      "work/projects",
    ]);
    expect(loadNoteTypeOrder("/vault/two")).toEqual([]);
  });

  it("ignores invalid entries and removes duplicates", () => {
    values.set(
      "zerus.noteTypeOrder./vault/one",
      JSON.stringify(["work", 42, "work", "../inbox"]),
    );

    expect(loadNoteTypeOrder("/vault/one")).toEqual(["work", "inbox"]);
  });
});

describe("default note type preference", () => {
  it("uses Inbox when a vault has no preference", () => {
    expect(loadDefaultNoteType("/vault/one")).toEqual(["inbox"]);
  });

  it("saves a case-sensitive type separately for each vault", () => {
    saveDefaultNoteType("/vault/one", ["Work", "Client-Projects"]);

    expect(loadDefaultNoteType("/vault/one")).toEqual([
      "Work",
      "Client-Projects",
    ]);
    expect(loadDefaultNoteType("/vault/two")).toEqual(["inbox"]);
  });
});

describe("file hub expansion preference", () => {
  it("saves preview and Markdown expansion independently for each file hub", () => {
    saveFileHubExpandedSection("file-a", "preview");
    saveFileHubExpandedSection("file-b", "markdown");

    expect(loadFileHubExpandedSection("file-a")).toBe("preview");
    expect(loadFileHubExpandedSection("file-b")).toBe("markdown");
  });

  it("clears a saved expansion without affecting other file hubs", () => {
    saveFileHubExpandedSection("file-a", "preview");
    saveFileHubExpandedSection("file-b", "markdown");
    saveFileHubExpandedSection("file-a", null);

    expect(loadFileHubExpandedSection("file-a")).toBeNull();
    expect(loadFileHubExpandedSection("file-b")).toBe("markdown");
  });
});

describe("HTML preview preference", () => {
  it("remembers a separate preview mode for each HTML file hub", () => {
    saveHtmlPreviewMode("file-a", "safe");
    saveHtmlPreviewMode("file-b", "full");
    saveHtmlPreviewMode("file-c", "link");

    expect(loadHtmlPreviewMode("file-a")).toBe("safe");
    expect(loadHtmlPreviewMode("file-b")).toBe("full");
    expect(loadHtmlPreviewMode("file-c")).toBe("link");
    expect(loadHtmlPreviewMode("unknown")).toBeNull();
  });

  it("binds full-preview approval to the approved file fingerprint", () => {
    saveHtmlPreviewMode("file-a", "full", "sha256-value");

    expect(loadHtmlPreviewPreference("file-a")).toEqual({
      mode: "full",
      fingerprint: "sha256-value",
    });
  });
});

describe("hide sub-type notes preference", () => {
  it("defaults to showing nested notes and saves independently per vault", () => {
    expect(loadHideSubtypeNotes("/vault/one")).toBe(false);

    saveHideSubtypeNotes("/vault/one", true);

    expect(loadHideSubtypeNotes("/vault/one")).toBe(true);
    expect(loadHideSubtypeNotes("/vault/two")).toBe(false);
  });
});

describe("note width preference", () => {
  it("uses 75% when there is no valid saved preference", () => {
    expect(loadNoteWidth()).toBe(DEFAULT_NOTE_WIDTH);
    values.set("zerus.noteWidth", "46");
    expect(loadNoteWidth()).toBe(DEFAULT_NOTE_WIDTH);
  });

  it("saves and immediately applies a supported width", () => {
    saveNoteWidth(85);

    expect(loadNoteWidth()).toBe(85);
    expect(
      document.documentElement.style.getPropertyValue("--zerus-note-width"),
    ).toBe("85%");
  });

  it("can apply a width without persisting it", () => {
    applyNoteWidth(60);

    expect(values.has("zerus.noteWidth")).toBe(false);
    expect(
      document.documentElement.style.getPropertyValue("--zerus-note-width"),
    ).toBe("60%");
  });
});

describe("note alignment preference", () => {
  it("uses center when there is no valid saved preference", () => {
    expect(loadNoteAlignment()).toBe(DEFAULT_NOTE_ALIGNMENT);
    values.set("zerus.noteAlignment", "right");
    expect(loadNoteAlignment()).toBe(DEFAULT_NOTE_ALIGNMENT);
  });

  it("saves and immediately applies left alignment", () => {
    saveNoteAlignment("left");

    expect(loadNoteAlignment()).toBe("left");
    expect(
      document.documentElement.style.getPropertyValue(
        "--zerus-note-margin-inline",
      ),
    ).toBe("0 auto");
  });

  it("can apply center alignment without persisting it", () => {
    applyNoteAlignment("center");

    expect(values.has("zerus.noteAlignment")).toBe(false);
    expect(
      document.documentElement.style.getPropertyValue(
        "--zerus-note-margin-inline",
      ),
    ).toBe("auto");
  });
});

describe("editor mode preference", () => {
  it("uses clean mode by default and ignores invalid values", () => {
    expect(loadEditorMode()).toBe(DEFAULT_EDITOR_MODE);
    values.set("zerus.editorMode", "source");
    expect(loadEditorMode()).toBe(DEFAULT_EDITOR_MODE);
  });

  it("persists Markdown-aware mode", () => {
    saveEditorMode("markdown-aware");

    expect(loadEditorMode()).toBe("markdown-aware");
  });
});

describe("Markdown typing preference", () => {
  it("enables Markdown formatting while typing by default", () => {
    expect(loadMarkdownTypingEnabled()).toBe(
      DEFAULT_MARKDOWN_TYPING_ENABLED,
    );
    values.set("zerus.markdownTypingEnabled", "invalid");
    expect(loadMarkdownTypingEnabled()).toBe(
      DEFAULT_MARKDOWN_TYPING_ENABLED,
    );
  });

  it("persists literal Markdown symbol typing globally", () => {
    saveMarkdownTypingEnabled(false);

    expect(loadMarkdownTypingEnabled()).toBe(false);
    expect(values.get("zerus.markdownTypingEnabled")).toBe("false");
  });
});
