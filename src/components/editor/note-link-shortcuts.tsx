import { useCallback, useMemo, useState } from "react";
import { createPortal } from "react-dom";
import { LexicalTypeaheadMenuPlugin, MenuOption, type TriggerFn } from "@lexical/react/LexicalTypeaheadMenuPlugin";
import { $createLinkNode, $isLinkNode } from "@lexical/link";
import { $createTextNode, $getSelection, $isRangeSelection, $isTextNode } from "lexical";
import { addComposerChild$, addNestedEditorChild$, addTableCellEditorChild$, realmPlugin } from "@mdxeditor/editor";
import { useNoteLinkShortcutsEnabled } from "@/lib/editor-preferences";
import { useVault } from "@/store/notes-store";
import { noteReference, noteTitle, type Note } from "@/lib/note-utils";
import { searchLinkNotes } from "./vault-link-options";
import { matchNoteLinkTrigger } from "./note-link-trigger";

class NoteOption extends MenuOption {
  constructor(readonly note: Note) { super(note.id); }
}

// eslint-disable-next-line react-refresh/only-export-components
function NoteLinkPicker() {
  const { notes } = useVault();
  const [query, setQuery] = useState<string | null>(null);
  const options = useMemo(() => query === null ? [] : searchLinkNotes(notes, query).slice(0, 8).map(note => new NoteOption(note)), [notes, query]);
  const trigger = useCallback<TriggerFn>((text) => {
    const selection = $getSelection();
    if (!$isRangeSelection(selection)) return null;
    const node = selection.anchor.getNode();
    if (!$isTextNode(node) || node.hasFormat("code") || node.getParents().some($isLinkNode)) return null;
    return matchNoteLinkTrigger(text);
  }, []);
  return <LexicalTypeaheadMenuPlugin<NoteOption>
    onQueryChange={setQuery}
    options={options}
    triggerFn={trigger}
    anchorClassName="zerus-note-picker-anchor"
    onSelectOption={(option, textNode, close) => {
      if (!textNode) { close(); return; }
      const link = $createLinkNode(`#zerus-note:${encodeURIComponent(noteReference(option.note))}`);
      link.append($createTextNode(noteTitle(option.note)));
      textNode.replace(link);
      const space = $createTextNode(" ");
      link.insertAfter(space);
      space.selectEnd();
      close();
    }}
    menuRenderFn={(anchor, { selectedIndex, selectOptionAndCleanUp, setHighlightedIndex }) => anchor.current ? createPortal(
      <div className="zerus-note-picker" onMouseDown={event => event.preventDefault()}>
        <div className="zerus-note-picker-heading">Link a note</div>
        <ul role="listbox" aria-label="Matching notes">
          {options.map((option, index) => <li key={option.key} id={`typeahead-item-${index}`} role="option" aria-selected={selectedIndex === index}
            ref={element => option.setRefElement(element)}
            onMouseEnter={() => setHighlightedIndex(index)} onClick={() => selectOptionAndCleanUp(option)}>
            <strong>{noteTitle(option.note)}</strong><small>{option.note.path}</small>
          </li>)}
        </ul>
        {!options.length && <p role="status">No matching notes. Try another title.</p>}
        <div className="zerus-note-picker-hint">↑↓ Choose · Enter Insert · Esc Dismiss</div>
      </div>, anchor.current) : null}
  />;
}

// eslint-disable-next-line react-refresh/only-export-components
function NoteLinkShortcuts() {
  return useNoteLinkShortcutsEnabled() ? <NoteLinkPicker /> : null;
}

export const noteLinkShortcutsPlugin = realmPlugin({
  init(realm) {
    realm.pubIn({
      [addComposerChild$]: NoteLinkShortcuts,
      [addNestedEditorChild$]: NoteLinkShortcuts,
      [addTableCellEditorChild$]: NoteLinkShortcuts,
    });
  },
});
