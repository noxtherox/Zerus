import type * as Mdast from "mdast";
import type { Extension as FromMarkdownExtension } from "mdast-util-from-markdown";
import type { Options as ToMarkdownExtension } from "mdast-util-to-markdown";

const TABLE_WIDTHS = "zerusColumnWidths";
const TABLE_WIDTHS_COMMENT =
  /^<!--\s*zerus-table-widths:\s*([0-9]+(?:\s*,\s*[0-9]+)*)\s*-->$/;

type TableData = Record<string, unknown> & { zerusColumnWidths?: number[] };

function isParent(node: Mdast.Node): node is Mdast.Parent {
  return "children" in node && Array.isArray(node.children);
}

function parseWidths(value: string): number[] | null {
  const match = value.match(TABLE_WIDTHS_COMMENT);
  if (!match) return null;
  const widths = match[1].split(",").map((width) => Number(width.trim()));
  return widths.every(
    (width) => Number.isInteger(width) && width >= 80 && width <= 720,
  )
    ? widths
    : null;
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
    const node = parent.children[index] as Mdast.Node;
    if (node.type === "html") {
      const widths = parseWidths((node as Mdast.Html).value.trim());
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
