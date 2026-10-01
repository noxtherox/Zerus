import type * as Mdast from "mdast";
import type { Extension as FromMarkdownExtension } from "mdast-util-from-markdown";
import type { Options as ToMarkdownExtension } from "mdast-util-to-markdown";

const TABLE_WIDTHS = "zerusColumnWidths";
const TABLE_WIDTHS_COMMENT =
  /^<!--\s*zerus-table-widths:\s*([0-9]+(?:\s*,\s*[0-9]+)*)\s*-->$/;
const TABLE_WIDTHS_MDX = /^<zerus-table-widths widths="([0-9]+(?:,[0-9]+)*)" \/>$/;

type TableData = Record<string, unknown> & { zerusColumnWidths?: number[] };

function isParent(node: Mdast.Node): node is Mdast.Parent {
  return "children" in node && Array.isArray(node.children);
}

function parseWidths(value: string): number[] | null {
  const match = value.match(TABLE_WIDTHS_COMMENT) ?? value.match(TABLE_WIDTHS_MDX);
  if (!match) return null;
  const widths = match[1].split(",").map((width) => Number(width.trim()));
  return widths.every(
    (width) => Number.isInteger(width) && width >= 80 && width <= 720,
  )
    ? widths
    : null;
}

/** MDX discards HTML comments; use a temporary node until table import consumes it. */
export function prepareTableWidthMarker(node: Mdast.Node): string | null {
  let value: string | null = null;
  if (node.type === "html") value = (node as Mdast.Html).value;
  else if (node.type === "paragraph" && isParent(node) && node.children.length === 1) {
    const child = node.children[0];
    if (child.type === "text") value = (child as Mdast.Text).value;
  }
  if (value === null) return null;
  const widths = parseWidths(value.trim());
  if (!widths) return null;
  // Keep a blank line so CommonMark can still recognize the following table
  // when compatibility preparation is applied again.
  return TABLE_WIDTHS_MDX.test(value.trim())
    ? value
    : `<zerus-table-widths widths="${widths.join(",")}" />\n`;
}

/** Widths are editor metadata; the GFM table remains readable in every Markdown app. */
export function getTableColumnWidths(table: Mdast.Table): number[] | null {
  const widths = (table.data as TableData | undefined)?.[TABLE_WIDTHS];
  const columns = table.children[0]?.children.length ?? 0;
  return Array.isArray(widths) &&
    widths.length === columns &&
    widths.every(
      (width) => Number.isInteger(width) && width >= 80 && width <= 720,
    )
    ? [...widths]
    : null;
}

export function setTableColumnWidths(
  table: Mdast.Table,
  widths: readonly number[] | null,
): void {
  const next = widths ? widths.map((width) => Math.round(width)) : null;
  if (
    !next ||
    next.length !== (table.children[0]?.children.length ?? 0) ||
    next.some((width) => width < 80 || width > 720)
  ) {
    if (table.data) delete (table.data as TableData)[TABLE_WIDTHS];
    return;
  }
  table.data ??= {};
  (table.data as unknown as TableData).zerusColumnWidths = next;
}

function restoreWidths(parent: Mdast.Parent): void {
  for (let index = 0; index < parent.children.length; index += 1) {
    const node = parent.children[index] as Mdast.RootContent;
    if (node.type === "html" || node.type === "mdxJsxFlowElement") {
      let widths: number[] | null = null;
      if (node.type === "html") widths = parseWidths(node.value.trim());
      else if (node.name === "zerus-table-widths" && node.attributes.length === 1) {
        const attribute = node.attributes[0];
        if (attribute.type === "mdxJsxAttribute" && attribute.name === "widths" && typeof attribute.value === "string") {
          widths = parseWidths(`<!-- zerus-table-widths: ${attribute.value} -->`);
        }
      }
      const table = parent.children[index + 1];
      if (widths && table?.type === "table") {
        setTableColumnWidths(table, widths);
        parent.children.splice(index, 1);
        index -= 1;
        continue;
      }
    }
    if (isParent(node)) restoreWidths(node);
  }
}

/** Consumes Zerus' invisible width marker before mdast nodes reach the editor. */
export const tableWidthsFromMarkdown: FromMarkdownExtension = {
  transforms: [
    (tree) => {
      restoreWidths(tree);
      return tree;
    },
  ],
};

/** Adds the invisible width marker while delegating table formatting to GFM. */
export function withTableWidthSerialization(
  extension: ToMarkdownExtension,
): ToMarkdownExtension {
  const tableHandler = extension.handlers?.table;
  if (!tableHandler) return extension;
  return {
    ...extension,
    handlers: {
      ...extension.handlers,
      table(node, parent, state, info) {
        const markdown = tableHandler(node, parent, state, info);
        const widths = getTableColumnWidths(node as Mdast.Table);
        return widths
          ? `<!-- zerus-table-widths: ${widths.join(",")} -->\n${markdown}`
          : markdown;
      },
    },
  };
}
