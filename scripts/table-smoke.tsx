// Development-only manual regression harness; not part of the production entry.
import React, { useState } from "react";
import { createRoot } from "react-dom/client";
import { MarkdownEditor } from "../src/components/editor/MdxMarkdownEditor";
import "../src/globals.css";
const fixtures = {
  small:
    "# Table verification\n\nBefore table.\n\n| Item | Details | Status |\n| --- | :---: | ---: |\n| **Keyboard** | A comfortable mechanical keyboard | Ready |\n| Notebook | [A long link](https://example.com/a/very/long/address/that/should/wrap/without/widening/the/page) | In progress |\n| Empty | | |\n\nAfter table.",
  large:
    "# Large table\n\nBefore table.\n\n| " +
    Array.from({ length: 10 }, (_, c) => `Column ${c + 1}`).join(" | ") +
    " |\n| " +
    Array(10).fill("---").join(" | ") +
    " |\n" +
    Array.from(
      { length: 999 },
      (_, r) =>
        "| " +
        Array.from({ length: 10 }, (_, c) => `Cell ${r + 1}:${c + 1}`).join(
          " | ",
        ) +
        " |",
    ).join("\n") +
    "\n\nAfter table.",
};
export function Harness() {
  const [kind, setKind] = useState<"small" | "large" | "recovery">("small");
  const [readOnly, setReadOnly] = useState(false);
  const [markdown, setMarkdown] = useState(fixtures.small);
  const [revision, setRevision] = useState(0);
  return (
    <main style={{ maxWidth: 1000, margin: "auto", padding: 16 }}>
      <nav style={{ display: "flex", gap: 16, flexWrap: "wrap" }}>
        <button
          onClick={() => {
            setKind("small");
            setMarkdown(fixtures.small);
          }}
        >
          Small fixture
        </button>
        <button
          onClick={() => {
            setKind("large");
            setMarkdown(fixtures.large);
          }}
        >
          10,000-cell fixture
        </button>
        <button onClick={() => setReadOnly((value) => !value)}>
          {readOnly ? "Enable editing" : "Read-only"}
        </button>
        <button
          onClick={() => {
            setKind("recovery");
            setMarkdown("# Recovery fixture\n\n<UnclosedComponent>");
          }}
        >
          Recovery fixture
        </button>
        <button onClick={() => setRevision((r) => r + 1)}>
          Reload saved Markdown
        </button>
        <button
          onClick={() => document.documentElement.classList.toggle("dark")}
        >
          Toggle theme
        </button>
      </nav>
      <div style={{ height: "80dvh", marginTop: 16 }}>
        <MarkdownEditor
          noteId={`${kind}-${revision}`}
          initialContent={markdown}
          onChange={setMarkdown}
          autoFocus={false}
          readOnly={readOnly}
          getLinkableTitles={() => []}
          isTitleResolved={() => false}
          onFollowLink={() => {}}
        />
      </div>
      <details>
        <summary>Saved Markdown</summary>
        <pre id="saved-markdown">{markdown}</pre>
      </details>
    </main>
  );
}
const root = createRoot(document.getElementById("root")!);
root.render(<Harness />);
if (import.meta.hot) import.meta.hot.dispose(() => root.unmount());
