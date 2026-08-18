import type { Active, CollisionDetection, DroppableContainer } from "@dnd-kit/core";
import { closestCenter } from "@dnd-kit/core";
import { describe, expect, it } from "vitest";
import { boardCollisionDetection } from "./board-dnd";

type CollisionArgs = Parameters<CollisionDetection>[0];

function rect(left: number, top: number, width: number, height: number) {
  return {
    left,
    top,
    right: left + width,
    bottom: top + height,
    width,
    height,
    x: left,
    y: top,
    offsetLeft: left,
    offsetTop: top,
  };
}

function droppable(id: string, value: string): DroppableContainer {
  return {
    id,
    key: id,
    disabled: false,
    data: { current: { type: "column", value } },
    node: { current: null },
    rect: { current: null },
  };
}

function collisionArgs(activeType: "card" | "column"): CollisionArgs {
  const tall = droppable("board-column:tall", "tall");
  const empty = droppable("board-column:empty", "empty");
  const active: Active = {
    id: activeType,
    data: { current: { type: activeType } },
    rect: { current: { initial: null, translated: null } },
  };

  return {
    active,
    collisionRect: rect(10, 10, 80, 40),
    droppableContainers: [tall, empty],
    droppableRects: new Map([
      [tall.id, rect(0, 0, 100, 1000)],
      [empty.id, rect(120, 0, 100, 100)],
    ]),
    pointerCoordinates: { x: 50, y: 30 },
  };
}

describe("board collision detection", () => {
  it("targets the tall column under a dragged card near its top", () => {
    const args = collisionArgs("card");

    expect(closestCenter(args)[0]?.id).toBe("board-column:empty");
    expect(boardCollisionDetection(args)[0]?.id).toBe("board-column:tall");
  });

  it("retains center-based collision detection for column reordering", () => {
    const args = collisionArgs("column");

    expect(boardCollisionDetection(args)[0]?.id).toBe(closestCenter(args)[0]?.id);
  });
});
