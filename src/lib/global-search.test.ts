import { describe, expect, it } from "vitest";
import {
  buildSearchItems,
  EMPTY_SEARCH_FILTERS,
  filterSearchItems,
  searchChatRequest,
  searchExcerpt,
} from "./global-search";
import type { Note } from "./note-utils";
import type { Task } from "./tasks";
import type { ChatConversation } from "./mobile-chat-history";
const note = (
  id: string,
  content: string,
  extra: Partial<Note> = {},
): Note => ({
  id,
  content,
  path: `work/${id}.md`,
  pinned: false,
  updatedAt: "2026-09-16T00:00:00Z",
  ...extra,
});
const search = (notes: Note[], query: string) =>
  filterSearchItems(
    buildSearchItems(notes, [], []),
    query,
    EMPTY_SEARCH_FILTERS,
  ).map((item) => item.id);
describe("global search", () => {
  it("ranks titles before frontmatter and body, and exact text before fuzzy matches", () => {
    expect(
      search(
        [
          note("body", "# Meeting\nProject launch"),
          note("fuzzy", "# Project launches"),
          note("title", "# Project launch"),
          note("property", "---\nproject: Project launch\n---\n# Budget"),
        ],
        "Project launch",
      ),
    ).toEqual(["title", "fuzzy", "body", "property"]);
    expect(
      search(
        [
          note("typo", "# Project launch"),
          note("body", "# Meeting\nprojet launch"),
        ],
        "projet launch",
      ),
    ).toEqual(["body", "typo"]);
  });
  it("matches frontmatter keys, list values, booleans, numbers, and nested raw YAML", () => {
    const n = note(
      "metadata",
      "---\nproject: Aurora\ntags:\n  - launch\n  - design\napproved: false\nbudget: 4200\ncustomer:\n  region: Lisbon\n---\n# Planning",
    );
    for (const query of [
      "Aurora",
      "launch",
      "approved",
      "false",
      "4200",
      "Lisbon",
    ])
      expect(search([n], query)).toEqual(["metadata"]);
    expect(searchExcerpt(buildSearchItems([n], [], [])[0], "Aurora")).toContain(
      "project: Aurora",
    );
  });
  it("includes external notes and links, excludes trash and gates archived items", () => {
    const items = buildSearchItems(
      [
        note("external", "# Test", { externalPath: "/tmp/test.md" }),
        note(
          "link",
          "---\nzerus-link-id: web\nzerus-link-url: https://example.com\n---\n# Test",
        ),
        note("trash", "# Test", { path: ".trash/test.md" }),
        note("archived", "# Test", { archived: true }),
      ],
      [],
      [],
    );
    expect(
      filterSearchItems(items, "Test", EMPTY_SEARCH_FILTERS)
        .map((item) => item.id)
        .sort(),
    ).toEqual(["external", "link"]);
    expect(
      filterSearchItems(items, "Test", {
        ...EMPTY_SEARCH_FILTERS,
        archived: true,
      }),
    ).toHaveLength(3);
  });
  it("combines collection, date, type, and exact property filters", () => {
    const items = buildSearchItems(
      [
        note("one", "---\ntags: [design, launch]\napproved: false\n---\n# One"),
        note("two", "---\ntags: [redesign]\n---\n# Two", {
          updatedAt: "2020-01-01T00:00:00Z",
        }),
      ],
      [],
      [],
    );
    expect(
      filterSearchItems(
        items,
        "",
        {
          ...EMPTY_SEARCH_FILTERS,
          collection: "notes",
          type: "work",
          property: "tags",
          value: "design",
          days: "7",
        },
        Date.parse("2026-09-16"),
      ).map((item) => item.id),
    ).toEqual(["one"]);
    expect(
      filterSearchItems(items, "", {
        ...EMPTY_SEARCH_FILTERS,
        property: "approved",
        value: "false",
      }),
    ).toHaveLength(1);
  });
  it("searches task metadata and chat messages with lifecycle and task filters", () => {
    const task = {
      id: "task",
      title: "Ship",
      category: "Aurora",
      priority: "high",
      completed: false,
      createdAt: "2026-09-16",
      linkedNoteIds: [],
    } as unknown as Task;
    const chat = {
      id: "chat",
      title: "Planning",
      messages: [{ role: "user", text: "Aurora roadmap" }],
      updatedAt: "2026-09-16",
    } as ChatConversation;
    const items = buildSearchItems(
      [],
      [task],
      [chat, { ...chat, id: "deleted", deletedAt: "2026-09-16" }],
    );
    expect(
      filterSearchItems(items, "Aurora", EMPTY_SEARCH_FILTERS),
    ).toHaveLength(2);
    expect(
      filterSearchItems(items, "Aurora", {
        ...EMPTY_SEARCH_FILTERS,
        collection: "tasks",
        status: "open",
        priority: "high",
      }).map((item) => item.id),
    ).toEqual(["task"]);
    expect(searchChatRequest("summarize", items[0]).document?.name).toBe(
      "Ship",
    );
    expect(
      searchChatRequest(
        "summarize",
        buildSearchItems([note("one", "# One")], [], [])[0],
      ).noteIds,
    ).toEqual(["one"]);
  });
  it("tolerates missing letters and transpositions without fuzzy short-word noise", () => {
    expect(search([note("one", "# Project launch")], "projet launch")).toEqual([
      "one",
    ]);
    expect(search([note("one", "# Project launch")], "porject launch")).toEqual(
      ["one"],
    );
    expect(search([note("one", "# Cat")], "car")).toEqual([]);
  });
});
