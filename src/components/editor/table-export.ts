import { $getRoot, type LexicalNode } from "lexical";
import {
  exportLexicalTreeToMdast,
  type LexicalVisitor,
  type ExportLexicalTreeOptions,
} from "@mdxeditor/editor";
import type { TableNode } from "@lexical/table";
import type * as Mdast from "mdast";

/** Reuse MDXEditor's visitors, skipping branches outside this table. */
export function $exportSingleTable(
  table: TableNode,
  options: Omit<ExportLexicalTreeOptions, "root">,
): Mdast.Table {
  const ancestors = new Set(table.getParents().map((node) => node.getKey()));
  const skipOtherBranches: LexicalVisitor = {
    priority: 1000,
    testLexicalNode: (node): node is LexicalNode =>
      node !== table &&
      !ancestors.has(node.getKey()) &&
      !node.getParents().some((parent) => parent === table),
    visitLexicalNode() {},
  };
  const result = exportLexicalTreeToMdast({
    ...options,
    root: $getRoot(),
    visitors: [skipOtherBranches, ...options.visitors],
    addImportStatements: false,
  });
  function find(node: Mdast.Nodes): Mdast.Table | undefined {
    if (node.type === "table") return node;
    if ("children" in node) {
      for (const child of node.children) {
        const table = find(child as Mdast.Nodes);
        if (table) return table;
      }
    }
  }
  const exported = find(result);
  if (!exported) throw new Error("Table could not be serialized.");
  return exported;
}
