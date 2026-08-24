import { EditorSelection, EditorState } from "@codemirror/state";
import { markdown, markdownLanguage } from "@codemirror/lang-markdown";
import { GFM } from "@lezer/markdown";
import { describe, expect, it, vi } from "vitest";
import {
  autoformatCancellationAt,
  cancelRecentAutoformat,
  deleteCleanSelection,
  externalLinkAt,
  handleInlineMarkupBoundaryBackspace,
  handleInlineMarkupBoundaryEnter,
  handleInlineMarkupBoundarySpace,
  inlineMarkupBoundaryAt,
  isConfirmedFencedCode,
  isSpaceConfirmedStructuralMark,
  listItemIndentEm,
  listItemPrefixOffsetEm,
  livePreviewExtension,
  moveCursorBeforeEscapedMarkdownSymbol,
  moveCursorBeforeOpeningMarkup,
  moveCursorPastClosingMarkup,
  openingInlineMarkupFrom,
  shouldRenderTablePreview,
  shouldOpenExternalLink,
} from "./live-preview";

function createState(doc: string, cursor?: number) {
  return EditorState.create({
    doc,
    selection: cursor == null ? undefined : { anchor: cursor },
    extensions: [
      markdown({ base: markdownLanguage, extensions: GFM }),
      livePreviewExtension(),
    ],
  });
}

describe("clean mode autoformat cancellation", () => {
  it("is disabled when Markdown typing is off", () => {
    const state = createState("**Hello**", 9);
    const view = { state } as unknown as import("@codemirror/view").EditorView;

    expect(cancelRecentAutoformat(view, false)).toBe(false);
  });

  it.each([
    ["# ", [0]],
    ["  - ", [2]],
    ["- [ ] ", [0]],
    ["> ", [0]],
    ["12. ", [2]],
    ["**bold**", [0, 1]],
    ["*italic*", [0]],
    ["~~struck~~", [0, 1]],
    ["`code`", [0]],
    ["[label](https://example.com)", [0]],
  ])("describes the literal escape for %s", (doc, escapeAt) => {
    expect(autoformatCancellationAt(createState(doc, doc.length))).toEqual({
      escapeAt,
      cursor: doc.length,
    });
  });

  it("ignores incomplete Markdown and non-collapsed selections", () => {
    for (const doc of [
      "#",
      "*",
      "*italic",
      "**bold",
      "~~struck",
      "`code",
      "[label](https://example.com",
    ]) {
      expect(autoformatCancellationAt(createState(doc, doc.length))).toBeNull();
    }
    const state = createState("**bold**");
    const selected = state.update({ selection: { anchor: 2, head: 6 } }).state;
    expect(autoformatCancellationAt(selected)).toBeNull();
  });
});

describe("structural Markdown confirmation", () => {
  it.each([
    ["#", 1, false],
    ["# ", 1, true],
    ["## ", 2, true],
    ["*", 1, false],
    ["* ", 1, true],
    ["12.", 3, false],
    ["12. ", 3, true],
    [">", 1, false],
    ["> ", 1, true],
  ])("requires a literal Space in %s", (doc, markTo, expected) => {
    expect(isSpaceConfirmedStructuralMark(createState(doc), markTo)).toBe(
      expected,
    );
  });
});

describe("complex Markdown presentation", () => {
  it("keeps an opening code fence literal until Enter creates another line", () => {
    expect(isConfirmedFencedCode(createState("```"), 0, 3)).toBe(false);
    expect(
      isConfirmedFencedCode(createState("```\n\n```"), 0, 7),
    ).toBe(true);
  });

  it("renders tables in clean mode", () => {
    const doc = "| Name |\n| --- |\n| Zerus |";
    const state = createState(doc, 2);
    expect(shouldRenderTablePreview(state, 0, doc.length)).toBe(true);
  });

  it("exposes an active table in Markdown-aware mode", () => {
    const doc = "| Name |\n| --- |\n| Zerus |\n\nAfter";
    const state = EditorState.create({
      doc,
      selection: { anchor: 2 },
      extensions: [
        markdown({ base: markdownLanguage, extensions: GFM }),
        livePreviewExtension({
          initialMode: "markdown-aware",
          onOpen: () => undefined,
        }),
      ],
    });
    expect(shouldRenderTablePreview(state, 0, doc.indexOf("\n\n"))).toBe(
      false,
    );
  });

  it("keeps inactive tables rendered in Markdown-aware mode", () => {
    const doc = "| Name |\n| --- |\n| Zerus |\n\nAfter";
    const tableTo = doc.indexOf("\n\n");
    const state = EditorState.create({
      doc,
      selection: { anchor: doc.length },
      extensions: [
        markdown({ base: markdownLanguage, extensions: GFM }),
        livePreviewExtension({
          initialMode: "markdown-aware",
          onOpen: () => undefined,
        }),
      ],
    });
    expect(shouldRenderTablePreview(state, 0, tableTo)).toBe(true);
  });
});

describe("live preview cursor placement", () => {
  it("deletes a visible selection together with every hidden escape", () => {
    let state = createState("\\*\\*literal\\*\\*");
    state = state.update({
      selection: EditorSelection.range(1, state.doc.length),
    }).state;
    const view = {
      get state() {
        return state;
      },
      dispatch(spec: Parameters<EditorState["update"]>[0]) {
        state = state.update(spec).state;
      },
    } as unknown as import("@codemirror/view").EditorView;

    expect(deleteCleanSelection(view, "backward")).toBe(true);
    expect(state.doc.toString()).toBe("");
    expect(state.selection.main.head).toBe(0);
  });

  it.each([
    ["Hello\\*", 6, 5],
    ["Hello\\_", 6, 5],
    ["Hello\\#", 6, 5],
  ])(
    "moves a caret out of the hidden escape in %s",
    (doc, cursor, expected) => {
      const state = createState(doc);
      expect(
        moveCursorBeforeEscapedMarkdownSymbol(
          state,
          EditorSelection.single(cursor),
        ).main.head,
      ).toBe(expected);
    },
  );

  it("normalizes pointer placement at a hidden escape boundary", () => {
    const state = createState("Hello\\*", 0);
    const transaction = state.update({
      selection: { anchor: 6 },
      userEvent: "select.pointer",
    });

    expect(transaction.state.selection.main.head).toBe(5);
  });

  it.each(["*", "_", "#"])(
    "moves ArrowRight and ArrowLeft across the hidden escape for %s",
    (symbol) => {
      const doc = `\\${symbol}Hello`;
      const before = createState(doc, 0);
      const right = before.update({
        selection: { anchor: 1 },
        userEvent: "select",
      });
      const after = createState(doc, 2);
      const left = after.update({
        selection: { anchor: 1 },
        userEvent: "select",
      });

      expect(right.state.selection.main.head).toBe(2);
      expect(left.state.selection.main.head).toBe(0);
    },
  );

  it("keeps the visible backslash in an even escape run separately editable", () => {
    const doc = "\\\\*Hello";
    const before = createState(doc, 0);
    const right = before.update({
      selection: { anchor: 1 },
      userEvent: "select",
    });
    const after = createState(doc, 3);
    const left = after.update({
      selection: { anchor: 2 },
      userEvent: "select",
    });

    expect(right.state.selection.main.head).toBe(2);
    expect(left.state.selection.main.head).toBe(2);
  });

  it("extends keyboard selections by visible escaped characters", () => {
    const forward = createState("\\*\\*text", 0).update({
      selection: { anchor: 0, head: 1 },
      userEvent: "select",
    });
    const backwardState = createState("\\*\\*text", 4).update({
      selection: { anchor: 4, head: 2 },
    }).state;
    const backward = backwardState.update({
      selection: { anchor: 4, head: 1 },
      userEvent: "select",
    });

    expect(forward.state.selection.main).toMatchObject({ from: 0, to: 2 });
    expect(backward.state.selection.main).toMatchObject({ from: 0, to: 4 });
  });

  it.each([
    ["**bold**", 2, 0],
    ["*italic*", 1, 0],
    ["~~struck~~", 2, 0],
    ["`code`", 1, 0],
    ["[label](https://example.com)", 1, 0],
    ["***both***", 3, 0],
    ["before **bold**", 9, 7],
  ])(
    "moves a cursor after opening syntax in %s before the construct",
    (doc, cursor, expected) => {
      const state = createState(doc);
      const selection = EditorSelection.single(cursor);

      expect(moveCursorBeforeOpeningMarkup(state, selection).main.head).toBe(
        expected,
      );
    },
  );

  it("lets ArrowRight stop after the last italic character before closing markup", () => {
    const beforeLastCharacter = createState("*Hello*", 5);
    const beforeClosingMark = beforeLastCharacter.update({
      selection: { anchor: 6 },
      userEvent: "select",
    }).state;
    const outsideFormatting = beforeClosingMark.update({
      selection: { anchor: 7 },
      userEvent: "select",
    }).state;

    expect(beforeClosingMark.selection.main.head).toBe(6);
    expect(outsideFormatting.selection.main.head).toBe(7);
  });

  it.each([
    ["**bold**", 6, 8],
    ["*italic*", 7, 8],
    ["~~struck~~", 8, 10],
    ["`code`", 5, 6],
    ["[label](https://example.com)", 6, 28],
    ["***both***", 7, 10],
    ["[**label**](https://example.com)", 8, 32],
  ])(
    "moves a cursor before the closing syntax in %s past the construct",
    (doc, cursor, expected) => {
      const state = createState(doc);
      const selection = EditorSelection.single(cursor);

      expect(moveCursorPastClosingMarkup(state, selection).main.head).toBe(
        expected,
      );
    },
  );

  it("does not change a text selection ending at the closing marker", () => {
    const state = createState("**bold**");
    const selection = EditorSelection.create([EditorSelection.range(2, 6)]);

    expect(moveCursorPastClosingMarkup(state, selection)).toBe(selection);
  });

  it("does not move a cursor within ordinary text", () => {
    const state = createState("plain text");
    const selection = EditorSelection.single(5);

    expect(moveCursorPastClosingMarkup(state, selection)).toBe(selection);
  });

  it("does not treat a Markdown destination without http(s) as a live link", () => {
    const state = createState("[label](example.com)");
    const selection = EditorSelection.single(6);

    expect(moveCursorPastClosingMarkup(state, selection)).toBe(selection);
  });

  it("applies the correction to editor selection transactions", () => {
    const state = createState("**bold**");
    const transaction = state.update({ selection: { anchor: 6 } });

    expect(transaction.state.selection.main.head).toBe(8);
  });

  it.each([
    ["**bold**", 8, 6, 5],
    ["*italic*", 8, 7, 6],
    ["~~struck~~", 10, 8, 7],
    ["`code`", 6, 5, 4],
  ])(
    "lets ArrowLeft enter formatted text in %s",
    (doc, outside, visualEnd, inside) => {
      const state = createState(doc, outside);
      const atVisualEnd = state.update({
        selection: { anchor: visualEnd },
        userEvent: "select",
      }).state;
      const withinText = atVisualEnd.update({
        selection: { anchor: inside },
        userEvent: "select",
      }).state;

      expect(atVisualEnd.selection.main.head).toBe(visualEnd);
      expect(withinText.selection.main.head).toBe(inside);
    },
  );

  it.each([
    ["**bold**", 0, 2, 3],
    ["*italic*", 0, 1, 2],
    ["~~struck~~", 0, 2, 3],
    ["`code`", 0, 1, 2],
  ])(
    "lets ArrowRight enter formatted text in %s",
    (doc, outside, visualStart, inside) => {
      const state = createState(doc, outside);
      const atVisualStart = state.update({
        selection: { anchor: visualStart },
        userEvent: "select",
      }).state;
      const withinText = atVisualStart.update({
        selection: { anchor: inside },
        userEvent: "select",
      }).state;

      expect(atVisualStart.selection.main.head).toBe(visualStart);
      expect(withinText.selection.main.head).toBe(inside);
    },
  );
});

describe("live preview Backspace boundaries", () => {
  it.each([
    ["before **bold**", 9, 7],
    ["before **bold**", 8, 7],
    ["before *italic*", 8, 7],
    ["before ~~struck~~", 9, 7],
    ["before `code`", 8, 7],
    ["before [label](https://example.com)", 8, 7],
    ["before ***both***", 10, 7],
  ])(
    "finds all opening syntax at the visual left edge in %s",
    (doc, cursor, expected) => {
      expect(openingInlineMarkupFrom(createState(doc, cursor), cursor)).toBe(
        expected,
      );
    },
  );

  it.each([
    ["# **Hello**", 4, "opening"],
    ["# **Hello** ", 11, "closing"],
    ["***Hello***", 3, "opening"],
    ["***Hello***", 11, "closing"],
  ] as const)("finds the %s boundary at %i", (doc, cursor, side) => {
    expect(inlineMarkupBoundaryAt(createState(doc, cursor), cursor)).toMatchObject({
      side,
    });
  });

  it("deletes before opening syntax without consuming the bold markers", () => {
    let state = createState("# **Hello**", 4);
    const view = {
      get state() {
        return state;
      },
      dispatch(spec: Parameters<EditorState["update"]>[0]) {
        state = state.update(spec).state;
      },
    } as unknown as import("@codemirror/view").EditorView;

    expect(handleInlineMarkupBoundaryBackspace(view)).toBe(true);
    expect(state.doc.toString()).toBe("#**Hello**");
    expect(state.selection.main.head).toBe(1);
  });

  it("moves a bold construct onto the previous line from its visual left edge", () => {
    let state = createState("Above\n**Hello**", 8);
    const view = {
      get state() {
        return state;
      },
      dispatch(spec: Parameters<EditorState["update"]>[0]) {
        state = state.update(spec).state;
      },
    } as unknown as import("@codemirror/view").EditorView;

    expect(handleInlineMarkupBoundaryBackspace(view)).toBe(true);
    expect(state.doc.toString()).toBe("Above**Hello**");
    expect(state.selection.main.head).toBe(5);
  });

  it("moves a bold construct when the visual caret maps inside its opening mark", () => {
    let state = createState("*Hello*\n**Hello**", 9);
    const view = {
      get state() {
        return state;
      },
      dispatch(spec: Parameters<EditorState["update"]>[0]) {
        state = state.update(spec).state;
      },
    } as unknown as import("@codemirror/view").EditorView;

    expect(handleInlineMarkupBoundaryBackspace(view)).toBe(true);
    expect(state.doc.toString()).toBe("*Hello***Hello**");
    expect(state.selection.main.head).toBe(7);
  });

  it.each([
    ["\\#**Hello**", 4, "**Hello**", 0],
    ["\\\\#**Hello**", 5, "\\\\**Hello**", 2],
  ])(
    "removes only the former heading marker at the bold boundary in %s",
    (doc, cursor, expected, expectedCursor) => {
      let state = createState(doc, cursor);
      const view = {
        get state() {
          return state;
        },
        dispatch(spec: Parameters<EditorState["update"]>[0]) {
          state = state.update(spec).state;
        },
      } as unknown as import("@codemirror/view").EditorView;

      expect(handleInlineMarkupBoundaryBackspace(view)).toBe(true);
      expect(state.doc.toString()).toBe(expected);
      expect(state.selection.main.head).toBe(expectedCursor);
    },
  );

  it("does not delete hidden opening syntax at the start of the document", () => {
    const state = createState("**Hello**", 2);
    const dispatch = vi.fn();
    const view = {
      get state() {
        return state;
      },
      dispatch,
    } as unknown as import("@codemirror/view").EditorView;

    expect(handleInlineMarkupBoundaryBackspace(view)).toBe(true);
    expect(state.doc.toString()).toBe("**Hello**");
    expect(dispatch).not.toHaveBeenCalled();
  });

  it("removes formatting at the closing boundary and preserves trailing space", () => {
    let state = createState("# **Hello** ", 11);
    const view = {
      get state() {
        return state;
      },
      dispatch(spec: Parameters<EditorState["update"]>[0]) {
        state = state.update(spec).state;
      },
    } as unknown as import("@codemirror/view").EditorView;

    expect(handleInlineMarkupBoundaryBackspace(view)).toBe(true);
    expect(state.doc.toString()).toBe("# Hello ");
    expect(state.selection.main.head).toBe(7);
  });

  it("removes every marker from combined bold and italic", () => {
    let state = createState("***Hello***", 11);
    const view = {
      get state() {
        return state;
      },
      dispatch(spec: Parameters<EditorState["update"]>[0]) {
        state = state.update(spec).state;
      },
    } as unknown as import("@codemirror/view").EditorView;

    expect(handleInlineMarkupBoundaryBackspace(view)).toBe(true);
    expect(state.doc.toString()).toBe("Hello");
    expect(state.selection.main.head).toBe(5);
  });

  it("does not treat a right edge as an opening or intercept Markdown-aware mode", () => {
    const clean = createState("**Hello**", 9);
    expect(openingInlineMarkupFrom(clean, 9)).toBeNull();

    const aware = EditorState.create({
      doc: "**Hello**",
      selection: { anchor: 2 },
      extensions: [
        markdown({ base: markdownLanguage, extensions: GFM }),
        livePreviewExtension({
          initialMode: "markdown-aware",
          onOpen: () => undefined,
        }),
      ],
    });
    const view = { state: aware } as unknown as import("@codemirror/view").EditorView;
    expect(handleInlineMarkupBoundaryBackspace(view)).toBe(false);
  });
});

describe("live preview Enter boundaries", () => {
  it.each(["*", "_", "#"])(
    "inserts Enter before the hidden escape for %s",
    (symbol) => {
      const doc = `\\${symbol}Hello`;
      let state = createState(doc, 1);
      const view = {
        get state() {
          return state;
        },
        dispatch(spec: Parameters<EditorState["update"]>[0]) {
          state = state.update(spec).state;
        },
      } as unknown as import("@codemirror/view").EditorView;

      expect(handleInlineMarkupBoundaryEnter(view)).toBe(true);
      expect(state.doc.toString()).toBe(`\n\\${symbol}Hello`);
      expect(state.selection.main.head).toBe(1);
    },
  );

  it("moves the complete bold construct to the next line", () => {
    let state = createState("Above **Hello**", 8);
    const view = {
      get state() {
        return state;
      },
      dispatch(spec: Parameters<EditorState["update"]>[0]) {
        state = state.update(spec).state;
      },
    } as unknown as import("@codemirror/view").EditorView;

    expect(handleInlineMarkupBoundaryEnter(view)).toBe(true);
    expect(state.doc.toString()).toBe("Above \n**Hello**");
    expect(state.selection.main.head).toBe(7);
  });

  it("does not split toolbar-created bold after a literal typed heading", () => {
    let state = createState("\\# **Hello**", 5);
    const view = {
      get state() {
        return state;
      },
      dispatch(spec: Parameters<EditorState["update"]>[0]) {
        state = state.update(spec).state;
      },
    } as unknown as import("@codemirror/view").EditorView;

    expect(handleInlineMarkupBoundaryEnter(view)).toBe(true);
    expect(state.doc.toString()).toBe("\\# \n**Hello**");
    expect(state.selection.main.head).toBe(4);
  });
});

describe("live preview Space boundaries", () => {
  it.each(["*", "_", "#"])(
    "inserts Space before the hidden escape for %s",
    (symbol) => {
      const doc = `\\${symbol}Hello`;
      let state = createState(doc, 1);
      const view = {
        get state() {
          return state;
        },
        dispatch(spec: Parameters<EditorState["update"]>[0]) {
          state = state.update(spec).state;
        },
      } as unknown as import("@codemirror/view").EditorView;

      expect(handleInlineMarkupBoundarySpace(view)).toBe(true);
      expect(state.doc.toString()).toBe(` \\${symbol}Hello`);
      expect(state.selection.main.head).toBe(1);
    },
  );

  it.each([
    ["*Hello*", 6, "*Hello* "],
    ["**Hello**", 7, "**Hello** "],
    ["~~Hello~~", 7, "~~Hello~~ "],
    ["`Hello`", 6, "`Hello` "],
  ])(
    "inserts Space after the closing markup in %s",
    (doc, cursor, expected) => {
      let state = createState(doc, cursor);
      const view = {
        get state() {
          return state;
        },
        dispatch(spec: Parameters<EditorState["update"]>[0]) {
          state = state.update(spec).state;
        },
      } as unknown as import("@codemirror/view").EditorView;

      expect(handleInlineMarkupBoundarySpace(view)).toBe(true);
      expect(state.doc.toString()).toBe(expected);
      expect(state.selection.main.head).toBe(expected.length);
    },
  );

  it("does not intercept Space within ordinary text", () => {
    const state = createState("Hello", 3);
    const view = { state } as unknown as import("@codemirror/view").EditorView;

    expect(handleInlineMarkupBoundarySpace(view)).toBe(false);
  });
});

describe("external links", () => {
  it("opens with a modifier click or double click", () => {
    expect(
      shouldOpenExternalLink({
        button: 0,
        metaKey: true,
        ctrlKey: false,
        detail: 1,
      }),
    ).toBe(true);
    expect(
      shouldOpenExternalLink({
        button: 0,
        metaKey: false,
        ctrlKey: false,
        detail: 2,
      }),
    ).toBe(true);
  });

  it("keeps a single unmodified click for the link popover", () => {
    expect(
      shouldOpenExternalLink({
        button: 0,
        metaKey: false,
        ctrlKey: false,
        detail: 1,
      }),
    ).toBe(false);
  });

  it.each([
    [
      "Read [standards](https://weldnote.com) today",
      8,
      "https://weldnote.com/",
    ],
    ["Visit https://example.com/docs today", 12, "https://example.com/docs"],
    ["Visit http://example.com/docs today", 12, "http://example.com/docs"],
  ])("finds a link in %s", (doc, pos, expected) => {
    expect(externalLinkAt(createState(doc), pos)?.url).toBe(expected);
  });

  it("returns editable source ranges for a Markdown link", () => {
    const doc = "Read [standards](https://weldnote.com) today";
    const link = externalLinkAt(createState(doc), 8);

    expect(link?.kind).toBe("markdown");
    expect(doc.slice(link?.labelFrom, link?.labelTo)).toBe("standards");
    expect(doc.slice(link?.urlFrom, link?.urlTo)).toBe(
      "https://weldnote.com",
    );
    expect(doc.slice(link?.from, link?.to)).toBe(
      "[standards](https://weldnote.com)",
    );
  });

  it("returns the same label and destination ranges for a bare URL", () => {
    const doc = "Visit https://example.com/docs today";
    const link = externalLinkAt(createState(doc), 12);

    expect(link?.kind).toBe("bare");
    expect(doc.slice(link?.labelFrom, link?.labelTo)).toBe(
      "https://example.com/docs",
    );
    expect(link?.labelFrom).toBe(link?.urlFrom);
    expect(link?.labelTo).toBe(link?.urlTo);
  });

  it.each([
    ["Visit weldnote.com today", 10],
    ["Visit www.weldnote.com today", 12],
    ["Read [standards](weldnote.com) today", 8],
  ])("does not infer a link without http(s) in %s", (doc, pos) => {
    expect(externalLinkAt(createState(doc), pos)).toBeNull();
  });

  it.each([
    "![logo](https://example.com/logo.png)",
    "![Apple Notes image](assets/apple-notes/p33/002.jpg)",
  ])("does not treat any part of image Markdown as a link in %s", (doc) => {
    const state = createState(doc);

    for (let pos = 0; pos <= doc.length; pos += 1) {
      expect(externalLinkAt(state, pos)).toBeNull();
    }
  });

  it("does not auto-link a bare domain used as the note title", () => {
    const state = createState("# start.gg\n\nhttps://www.start.gg/");

    expect(externalLinkAt(state, 5)).toBeNull();
    expect(externalLinkAt(state, 20)?.url).toBe("https://www.start.gg/");
  });
});

describe("list item indentation", () => {
  it("gives the first nesting level a clearly visible step", () => {
    expect(listItemIndentEm(4, "-", false)).toBeCloseTo(2.9);
    expect(listItemPrefixOffsetEm(4, "-", false)).toBe(1.8);
  });

  it("keeps later nesting steps even after the larger first step", () => {
    expect(listItemIndentEm(8, "-", false)).toBeCloseTo(3.9);
    expect(listItemIndentEm(12, "-", false)).toBeCloseTo(4.9);
  });

  it("preserves marker-specific spacing", () => {
    expect(listItemIndentEm(0, "-", false)).toBe(0.8);
    expect(listItemIndentEm(0, "10.", false)).toBeCloseTo(1.65);
    expect(listItemIndentEm(0, "-", true)).toBe(1.35);
  });
});
