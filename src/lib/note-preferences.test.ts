import { beforeEach, describe, expect, it, vi } from "vitest";
import {
  applyNoteAlignment,
  applyNoteWidth,
  DEFAULT_NOTE_ALIGNMENT,
  DEFAULT_NOTE_WIDTH,
  loadDefaultNoteType,
  loadHideSubtypeNotes,
  loadNoteAlignment,
  loadNoteWidth,
  loadNoteTypeOrder,
  saveDefaultNoteType,
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
