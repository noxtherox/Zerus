import { TableCellNode, TableNode, TableRowNode } from "@lexical/table";
import {
  addComposerChild$,
  addExportVisitor$,
  addImportVisitor$,
  addLexicalNode$,
  addMdastExtension$,
  addSyntaxExtension$,
  addToMarkdownExtension$,
  realmPlugin,
  lexicalTheme$,
} from "@mdxeditor/editor";
import {
  type Options as GfmTableOptions,
  gfmTableFromMarkdown,
  gfmTableToMarkdown,
} from "mdast-util-gfm-table";
import { gfmTable } from "micromark-extension-gfm-table";
import { ElementTableBehavior } from "./element-table-controls";
import {
  LexicalElementTableVisitor,
  LargeTableExportVisitor,
  MdastElementTableVisitor,
} from "./element-table-model";

import { LargeTableNode } from "./large-table-node";

/**
 * GFM table support backed by Lexical element nodes rather than MDXEditor's
 * per-cell nested editors. This keeps large tables as one editor tree.
 */
export const elementTablePlugin = realmPlugin<GfmTableOptions>({
  init(realm, options) {
    realm.pub(lexicalTheme$, {
      ...realm.getValue(lexicalTheme$),
      tableScrollableWrapper: "zerus-table-scroll",
      tableCellSelected: "zerus-table-cell-selected",
    });
    realm.pubIn({
      [addMdastExtension$]: gfmTableFromMarkdown(),
      [addSyntaxExtension$]: gfmTable(),
      [addImportVisitor$]: MdastElementTableVisitor,
      [addLexicalNode$]: [
        TableNode,
        TableRowNode,
        TableCellNode,
        LargeTableNode,
      ],
      [addExportVisitor$]: [
        LexicalElementTableVisitor,
        LargeTableExportVisitor,
      ],
      [addToMarkdownExtension$]: gfmTableToMarkdown({
        tableCellPadding: options?.tableCellPadding ?? true,
        // Avoid padding every row to the longest cell in a large table.
        tablePipeAlign: options?.tablePipeAlign ?? false,
      }),
      [addComposerChild$]: ElementTableBehavior,
    });
  },
});
