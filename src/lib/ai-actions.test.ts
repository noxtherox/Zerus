import { describe, expect, it } from "vitest";
import {
  applyAiNoteAction,
  directAiNoteAction,
  parseAiResponse,
} from "./ai-actions";

describe("directAiNoteAction", () => {
  it("extracts exact quoted text from an add-to-note request", () => {
    expect(
      directAiNoteAction(
        'can you add text to this note? "Braskem is a company from Brazil"',
      ),
    ).toEqual({
      type: "append",
      text: "Braskem is a company from Brazil",
    });
  });

  it("supports smart quotes and ignores ambiguous or negated requests", () => {
    expect(
      directAiNoteAction("append “Brazil” at the end of the note"),
    ).toEqual({ type: "append", text: "Brazil" });
    expect(directAiNoteAction('do not add "Brazil" to the note')).toBeNull();
    expect(directAiNoteAction("add a summary to the note")).toBeNull();
  });
});

describe("parseAiResponse", () => {
  it("extracts an append action from the visible response", () => {
    const parsed = parseAiResponse(
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
      parseAiResponse("<zerus_action>not json</zerus_action>")
        .actionError,
    ).toContain("JSON");
    expect(
      parseAiResponse(
        '<zerus_action>{"type":"append","text":"A"}</zerus_action>' +
          '<zerus_action>{"type":"append","text":"B"}</zerus_action>',
      ).actionError,
    ).toContain("more than one");
    expect(
      parseAiResponse(
        'zerus_action>{"type":"replace_body","body":"hallucinated"}',
      ),
    ).toEqual({
      content: "I couldn't prepare a valid note edit.",
      action: null,
      actionError: "The AI provider returned a malformed note edit.",
    });
  });
});

describe("applyAiNoteAction", () => {
  it("appends a Markdown paragraph with stable spacing", () => {
    expect(
      applyAiNoteAction("# Braskem\n", {
        type: "append",
        text: "braskem is a company from brazil",
      }),
    ).toBe("# Braskem\n\nbraskem is a company from brazil");
  });

  it("replaces the complete note body", () => {
    expect(
      applyAiNoteAction("old", { type: "replace_body", body: "new" }),
    ).toBe("new");
  });

  it("strips echoed frontmatter from replacement and append edits", () => {
    const echoed = "---\nzerus-id: private-id\nstatus: draft\n---\n# Clean note\n\nRewritten";

    expect(
      applyAiNoteAction("# Old", { type: "replace_body", body: echoed }),
    ).toBe("# Clean note\n\nRewritten");
    expect(
      applyAiNoteAction("# Existing", { type: "append", text: echoed }),
    ).toBe("# Existing\n\n# Clean note\n\nRewritten");
  });
});
