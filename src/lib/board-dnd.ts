import {
  closestCenter,
  pointerWithin,
  type CollisionDetection,
} from "@dnd-kit/core";

/**
 * Cards should target the column under the pointer. Comparing column centers
 * makes the top of a tall column lose to a nearby short or empty column.
 */
export const boardCollisionDetection: CollisionDetection = (args) => {
  if (args.active.data.current?.type !== "card") {
    return closestCenter(args);
  }

  const pointerCollisions = pointerWithin(args);
  return pointerCollisions.length > 0 ? pointerCollisions : closestCenter(args);
};
