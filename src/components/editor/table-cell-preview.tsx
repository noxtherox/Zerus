import type { ReactNode } from "react";
import type * as Mdast from "mdast";
import { tableText } from "./table-data";

function inline(node: Mdast.PhrasingContent, key: number): ReactNode {
  const children =
    "children" in node
      ? node.children.map((child, i) =>
          inline(child as Mdast.PhrasingContent, i),
        )
      : null;
  switch (node.type) {
    case "strong":
      return <strong key={key}>{children}</strong>;
    case "emphasis":
      return <em key={key}>{children}</em>;
    case "delete":
      return <s key={key}>{children}</s>;
    case "inlineCode":
      return <code key={key}>{node.value}</code>;
    case "link":
      return (
        <span key={key} className="zerus-table-link" title={node.url}>
          {children}
        </span>
      );
    case "image":
      return (
        <span key={key} title={node.url}>
          Image: {node.alt || "Untitled"}
        </span>
      );
    default:
      return (
        <span key={key}>{"value" in node ? String(node.value) : children}</span>
      );
  }
}
export function TableCellPreview({ cell }: { cell: Mdast.TableCell }) {
  const text = tableText(cell);
  if (!text) return <>—</>;
  // A long cell is fully available in its editor without mounting its entire preview.
  if (text.length > 4000) return <>{text.slice(0, 4000)}…</>;
  return <>{cell.children.map(inline)}</>;
}
