import { useEffect } from "react";
import { MarkdownShortcutPlugin } from "@lexical/react/LexicalMarkdownShortcutPlugin";
import { useLexicalComposerContext } from "@lexical/react/LexicalComposerContext";
import { HorizontalRuleNode, $createHorizontalRuleNode } from "@lexical/react/LexicalHorizontalRuleNode";
import {
  BOLD_ITALIC_STAR, BOLD_ITALIC_UNDERSCORE, BOLD_STAR, BOLD_UNDERSCORE,
  INLINE_CODE, ITALIC_STAR, ITALIC_UNDERSCORE, LINK, HEADING, QUOTE,
  ORDERED_LIST, UNORDERED_LIST, CHECK_LIST, type ElementTransformer, type Transformer,
} from "@lexical/markdown";
import {
  $getSelection, $isRangeSelection, COMMAND_PRIORITY_HIGH, PASTE_COMMAND,
} from "lexical";
import {
  realmPlugin, addComposerChild$, addNestedEditorChild$, addTableCellEditorChild$,
  CodeBlockNode, $createCodeBlockNode,
} from "@mdxeditor/editor";
import { useCodeBlocksEnabled } from "@/lib/editor-preferences";

const code: ElementTransformer = {
  export: () => null,
  type: "element",
  regExp: /^```([\w+-]+)?\s?$/,
  triggerOnEnter: true,
  dependencies: [CodeBlockNode],
  replace(parent, _children, match) {
    const node = $createCodeBlockNode({ code: "", language: match[1] ?? "", meta: "" });
    parent.selectPrevious();
    parent.replace(node);
    // CodeMirror subscribes to focus after the new block has mounted.
    setTimeout(() => node.select(), 80);
  },
};
const rule: ElementTransformer = {
  type: "element", dependencies: [HorizontalRuleNode], export: () => null,
  regExp: /^(---|\*\*\*|___)\s?$/,
  replace(parent, _children, _match, isImport) {
    const node = $createHorizontalRuleNode();
    if (isImport || parent.getNextSibling()) parent.replace(node);
    else parent.insertBefore(node);
    node.selectNext();
  },
};
const base: Transformer[] = [BOLD_ITALIC_STAR, BOLD_ITALIC_UNDERSCORE, BOLD_STAR, BOLD_UNDERSCORE,
  INLINE_CODE, ITALIC_STAR, ITALIC_UNDERSCORE, LINK, HEADING, QUOTE, rule];
const lists = [ORDERED_LIST, UNORDERED_LIST, CHECK_LIST];
const enabledTransformers = [...base, ...lists, code];
const disabledTransformers = [...base, ...lists];
const tableEnabledTransformers = [...base, code];

// Registered as a composer child by the realm plugin below.
// eslint-disable-next-line react-refresh/only-export-components
function ProseShortcuts({ table = false }: { table?: boolean }) {
  const enabled = useCodeBlocksEnabled();
  const [editor] = useLexicalComposerContext();
  useEffect(() => {
    if (enabled) return;
    return editor.registerCommand(PASTE_COMMAND, event => {
      if (!event || !("clipboardData" in event) || !event.clipboardData) return false;
      const data = event.clipboardData;
      const html = data.getData("text/html");
      const serialized = data.getData("application/x-lexical-editor");
      if (!/<pre\b/i.test(html) && !/"type"\s*:\s*"codeblock"/.test(serialized)) return false;
      const selection = $getSelection();
      if (!$isRangeSelection(selection)) return false;
      const plain = data.getData("text/plain");
      // Preserve image/file pastes and leave unsupported clipboard formats alone.
      if (!plain) return false;
      event.preventDefault();
      selection.insertRawText(plain);
      return true;
    }, COMMAND_PRIORITY_HIGH);
  }, [editor, enabled]);
  return <MarkdownShortcutPlugin transformers={table
    ? enabled ? tableEnabledTransformers : base
    : enabled ? enabledTransformers : disabledTransformers} />;
}
export const proseShortcutsPlugin = realmPlugin({
  init(realm) {
    realm.pubIn({
      [addComposerChild$]: ProseShortcuts,
      [addNestedEditorChild$]: ProseShortcuts,
      [addTableCellEditorChild$]: () => <ProseShortcuts table />,
    });
  },
});
