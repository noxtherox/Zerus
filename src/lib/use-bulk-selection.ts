import { useCallback, useEffect, useRef, useState, type KeyboardEvent, type MouseEvent } from "react";

export interface BulkSelectionState {
  selectedIds: ReadonlySet<string>;
  selectMode: boolean;
  setSelectMode: (enabled: boolean) => void;
  clearSelection: () => void;
  selectAll: () => void;
  selectOnly: (id: string) => void;
  removeSelected: (ids: Iterable<string>) => void;
  retainSelected: (ids: Iterable<string>) => void;
  toggleOne: (id: string, options?: { range?: boolean; orderedIds?: string[] }) => void;
  handleModifiedClick: (event: MouseEvent, id: string, orderedIds?: string[]) => boolean;
  handleCollectionKeyDown: (event: KeyboardEvent) => void;
}

export function useBulkSelection(
  orderedIds: string[],
  resetKey: string,
): BulkSelectionState {
  const [selectedIds, setSelectedIds] = useState<Set<string>>(() => new Set());
  const [selectMode, setSelectModeState] = useState(false);
  const anchorId = useRef<string | null>(null);

  const clearSelection = useCallback(() => {
    setSelectedIds(new Set());
    setSelectModeState(false);
    anchorId.current = null;
  }, []);

  useEffect(() => {
    clearSelection();
  }, [clearSelection, resetKey]);

  const setSelectMode = useCallback((enabled: boolean) => {
    setSelectModeState(enabled);
    if (!enabled && selectedIds.size === 0) anchorId.current = null;
  }, [selectedIds.size]);

  const toggleOne = useCallback((
    id: string,
    options: { range?: boolean; orderedIds?: string[] } = {},
  ) => {
    const order = options.orderedIds ?? orderedIds;
    setSelectedIds((current) => {
      const next = new Set(current);
      if (options.range && anchorId.current) {
        const start = order.indexOf(anchorId.current);
        const end = order.indexOf(id);
        if (start >= 0 && end >= 0) {
          for (let index = Math.min(start, end); index <= Math.max(start, end); index++) {
            next.add(order[index]);
          }
          return next;
        }
      }
      if (next.has(id)) next.delete(id);
      else next.add(id);
      anchorId.current = id;
      return next;
    });
  }, [orderedIds]);

  const handleModifiedClick = useCallback((
    event: MouseEvent,
    id: string,
    localOrder?: string[],
  ) => {
    const selecting = selectMode || event.metaKey || event.ctrlKey || event.shiftKey;
    if (!selecting) return false;
    event.preventDefault();
    event.stopPropagation();
    toggleOne(id, { range: event.shiftKey, orderedIds: localOrder });
    return true;
  }, [selectMode, toggleOne]);

  const selectAll = useCallback(() => {
    setSelectedIds(new Set(orderedIds));
    setSelectModeState(true);
    anchorId.current = orderedIds.at(-1) ?? null;
  }, [orderedIds]);

  const selectOnly = useCallback((id: string) => {
    setSelectedIds(new Set([id]));
    setSelectModeState(true);
    anchorId.current = id;
  }, []);

  const removeSelected = useCallback((ids: Iterable<string>) => {
    const removed = new Set(ids);
    setSelectedIds((current) => {
      const next = new Set([...current].filter((id) => !removed.has(id)));
      if (!next.size) setSelectModeState(false);
      return next;
    });
  }, []);

  const retainSelected = useCallback((ids: Iterable<string>) => {
    const retained = new Set(ids);
    setSelectedIds((current) => new Set([...current].filter((id) => retained.has(id))));
  }, []);

  const handleCollectionKeyDown = useCallback((event: KeyboardEvent) => {
    const target = event.target as HTMLElement;
    if (target.closest("input, textarea, select, [contenteditable=true]")) return;
    if (event.key === "Escape") {
      clearSelection();
      return;
    }
    if ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === "a") {
      event.preventDefault();
      selectAll();
    }
  }, [clearSelection, selectAll]);

  return {
    selectedIds,
    selectMode,
    setSelectMode,
    clearSelection,
    selectAll,
    selectOnly,
    removeSelected,
    retainSelected,
    toggleOne,
    handleModifiedClick,
    handleCollectionKeyDown,
  };
}
