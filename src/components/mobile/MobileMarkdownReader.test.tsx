import { describe, expect, it } from "vitest";
import { readFileSync } from "node:fs";
import { renderToStaticMarkup } from "react-dom/server";
import { MobileMarkdownReader } from "./MobileMarkdownReader";

describe("mobile note reading mode", () => {
  it("keeps the nested rich editor behind an explicit edit state", () => {
    const source = readFileSync(
      new URL("./MobileZerus.tsx", import.meta.url),
      "utf8",
    );

    expect(source).toContain("const [isEditing, setIsEditing] = useState(false)");
    expect(source).toContain("isEditing ? (");
    expect(source).toContain("<MobileMarkdownReader markdown={draft}");
  });

  it("renders large GFM tables without mounting an editor", () => {
    const rows = Array.from(
      { length: 25 },
      (_, index) => `| ${index + 1} | Question ${index + 1} | Interpretation | Outcome |`,
    ).join("\n");
    const markdown = `## Priority summary\n\n| # | Question | Kind | Result |\n|---|---|---|---|\n${rows}`;

    const html = renderToStaticMarkup(
      <MobileMarkdownReader markdown={markdown} onFollowLink={() => undefined} />,
    );

    expect(html).toContain("<table");
    expect(html).toContain("<h2");
    expect(html).toContain("Question 25");
    expect(html).not.toContain("zerus-mdx-editor");
  });
});
