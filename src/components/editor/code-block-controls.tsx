import { codeBlockToParagraph } from "./code-block-text";
import { useCellValue } from "@mdxeditor/gurx";
import { CodeMirrorEditor, readOnly$, useCodeBlockEditorContext, type CodeBlockEditorProps } from "@mdxeditor/editor";
import { HISTORY_PUSH_TAG } from "lexical";
import { useCodeBlocksEnabled } from "@/lib/editor-preferences";
import { InsertCodeBlock } from "@mdxeditor/editor";

export function InsertEnabledCodeBlock() {
  return useCodeBlocksEnabled() ? <InsertCodeBlock /> : null;
}

export function ConvertibleCodeEditor(props: CodeBlockEditorProps) {
  const { parentEditor, lexicalNode } = useCodeBlockEditorContext();
  const readOnly = useCellValue(readOnly$);
  // Keep the control outside CodeMirror so it is available without focusing code.
  return <div className="zerus-convertible-code">
    <div className="flex justify-end px-2 pt-2">
      <button type="button" disabled={readOnly} className="rounded px-2 py-1 text-xs text-muted-foreground hover:bg-muted disabled:opacity-50"
        onMouseDown={event => event.preventDefault()}
        onClick={() => parentEditor.update(() => {
          if (lexicalNode.isAttached()) codeBlockToParagraph(lexicalNode.getLatest()).selectEnd();
        }, { tag: HISTORY_PUSH_TAG })}>Turn back into text</button>
    </div>
    <CodeMirrorEditor {...props} />
  </div>;
}
