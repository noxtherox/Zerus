import { describe, expect, it } from "vitest";
import type { TypeNode } from "./note-utils";
import {
  TYPE_TREE_PAGE_SIZE,
  visibleTypeNodes,
} from "./type-tree-pagination";

function makeNodes(count: number): TypeNode[] {
  return Array.from({ length: count }, (_, index) => ({
    name: `type-${index}`,
    path: [`type-${index}`],
    count: 0,
    children: [],
  }));
}

describe("visibleTypeNodes", () => {
  it("limits a large sibling group to the first page by default", () => {
    const nodes = makeNodes(TYPE_TREE_PAGE_SIZE + 5);

    expect(visibleTypeNodes(nodes)).toEqual(nodes.slice(0, TYPE_TREE_PAGE_SIZE));
  });

  it("reveals subsequent pages without changing the source tree", () => {
    const nodes = makeNodes(TYPE_TREE_PAGE_SIZE * 2 + 5);

    expect(visibleTypeNodes(nodes, TYPE_TREE_PAGE_SIZE * 2)).toEqual(
      nodes.slice(0, TYPE_TREE_PAGE_SIZE * 2),
    );
    expect(nodes).toHaveLength(TYPE_TREE_PAGE_SIZE * 2 + 5);
  });

  it("shows every node when the group fits within the requested count", () => {
    const nodes = makeNodes(4);

    expect(visibleTypeNodes(nodes)).toEqual(nodes);
  });
});
