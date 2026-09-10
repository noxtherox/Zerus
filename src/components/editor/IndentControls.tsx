import { useEffect, useState } from "react";
import { useCellValues } from "@mdxeditor/gurx";
import { activeEditor$, ButtonWithTooltip, readOnly$ } from "@mdxeditor/editor";
import {
  $getSelection,
  $isRangeSelection,
  INDENT_CONTENT_COMMAND,
  OUTDENT_CONTENT_COMMAND,
  type LexicalNode,
} from "lexical";
import { IndentDecrease, IndentIncrease } from "@/lib/icons";

function listItemFor(node: LexicalNode): LexicalNode | null {
  for (let current: LexicalNode | null = node; current; current = current.getParent()) {
    if (current.getType() === "listitem") return current;
  }
  return null;
}

export function IndentControls() {
  const [editor, readOnly] = useCellValues(activeEditor$, readOnly$);
  const [available, setAvailable] = useState({ increase: false, decrease: false });

  useEffect(() => {
    if (!editor) {
      setAvailable({ increase: false, decrease: false });
      return;
    }
    const update = () => editor.getEditorState().read(() => {
      const selection = $getSelection();
      if (!$isRangeSelection(selection)) {
        setAvailable({ increase: false, decrease: false });
        return;
      }
      const items = selection.getNodes()
        .filter((node) => node.getType() !== "list")
        .map(listItemFor);
      // Do not offer transient paragraph indentation: Markdown cannot save it.
      const inList = items.length > 0 && items.every(Boolean);
      const nested = items.some((item) => item?.getParent()?.getParent()?.getType() === "listitem");
      const decrease = inList && nested;
      setAvailable((previous) => previous.increase === inList && previous.decrease === decrease
        ? previous
        : { increase: inList, decrease });
    });
    update();
    return editor.registerUpdateListener(update);
  }, [editor]);

  return (
    <>
      <ButtonWithTooltip
        title="Decrease indent"
        disabled={readOnly || !available.decrease}
        onMouseDown={(event) => event.preventDefault()}
        onClick={() => editor?.dispatchCommand(OUTDENT_CONTENT_COMMAND, undefined)}
      >
        <IndentDecrease size={18} aria-hidden="true" />
      </ButtonWithTooltip>
      <ButtonWithTooltip
        title="Increase indent"
        disabled={readOnly || !available.increase}
        onMouseDown={(event) => event.preventDefault()}
        onClick={() => editor?.dispatchCommand(INDENT_CONTENT_COMMAND, undefined)}
      >
        <IndentIncrease size={18} aria-hidden="true" />
      </ButtonWithTooltip>
    </>
  );
}
