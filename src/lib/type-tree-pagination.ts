import type { TypeNode } from "./note-utils";

export const TYPE_TREE_PAGE_SIZE = 30;

export function visibleTypeNodes(
  nodes: TypeNode[],
  visibleCount = TYPE_TREE_PAGE_SIZE,
): TypeNode[] {
  return nodes.slice(0, visibleCount);
}
