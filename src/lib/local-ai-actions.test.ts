import { describe, expect, it } from "vitest";
import {
  applyLocalAiNoteAction,
  directLocalAiNoteAction,
  parseLocalAiResponse,
} from "./local-ai-actions";

describe("directLocalAiNoteAction", () => {
  it("extracts exact quoted text from an add-to-note request", () => {
    expect(
      directLocalAiNoteAction(
        'can you add text to this note? "Braskem is a company from Brazil"',
      ),
    ).toEqual({
      type: "append",
      text: "Braskem is a company from Brazil",
    });
  });

  it("supports smart quotes and ignores ambiguous or negated requests", () => {
    expect(
      directLocalAiNoteAction("append “Brazil” at the end of the note"),
    ).toEqual({ type: "append", text: "Brazil" });
    expect(directLocalAiNoteAction('do not add "Brazil" to the note')).toBeNull();
    expect(directLocalAiNoteAction("add a summary to the note")).toBeNull();
  });
});

describe("parseLocalAiResponse", () => {
  it("extracts an append action from the visible response", () => {
    const parsed = parseLocalAiResponse(
      'Added it.\n<zerus_action>{"type":"append","text":"Brazil"}</zerus_action>',
    );

    expect(parsed).toEqual({
      content: "Added it.",
      action: { type: "append", text: "Brazil" },
      actionError: null,
    });
  });

  it("rejects malformed and multiple actions", () => {
    expect(
      parseLocalAiResponse("<zerus_action>not json</zerus_action>")
        .actionError,
    ).toContain("JSON");
    expect(
      parseLocalAiResponse(
        '<zerus_action>{"type":"append","text":"A"}</zerus_action>' +
          '<zerus_action>{"type":"append","text":"B"}</zerus_action>',
      ).actionError,
    ).toContain("more than one");
    expect(
      parseLocalAiResponse(
        'zerus_action>{"type":"replace_body","body":"hallucinated"}',
      ),
    ).toEqual({
      content: "I couldn't prepare a valid note edit.",
      action: null,
      actionError: "Qwen returned a malformed note edit.",
    });
  });
});

describe("applyLocalAiNoteAction", () => {
  it("appends a Markdown paragraph with stable spacing", () => {
    expect(
      applyLocalAiNoteAction("# Braskem\n", {
        type: "append",
        text: "braskem is a company from brazil",
      }),
    ).toBe("# Braskem\n\nbraskem is a company from brazil");
  });

  it("replaces the complete note body", () => {
    expect(
      applyLocalAiNoteAction("old", { type: "replace_body", body: "new" }),
    ).toBe("new");
  });
});
