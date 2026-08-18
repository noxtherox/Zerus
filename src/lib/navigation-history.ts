export interface NavigationHistory<T> {
  back: T[];
  current: T;
  forward: T[];
}

export function createNavigationHistory<T>(current: T): NavigationHistory<T> {
  return { back: [], current, forward: [] };
}

export function pushNavigationHistory<T>(
  history: NavigationHistory<T>,
  next: T,
  equals: (left: T, right: T) => boolean,
  limit = 100,
): NavigationHistory<T> {
  if (equals(history.current, next)) return history;

  return {
    back: [...history.back, history.current].slice(-limit),
    current: next,
    forward: [],
  };
}

export function goBackInNavigationHistory<T>(
  history: NavigationHistory<T>,
): NavigationHistory<T> {
  const previous = history.back.at(-1);
  if (!previous) return history;

  return {
    back: history.back.slice(0, -1),
    current: previous,
    forward: [history.current, ...history.forward],
  };
}

export function goForwardInNavigationHistory<T>(
  history: NavigationHistory<T>,
): NavigationHistory<T> {
  const [next, ...remaining] = history.forward;
  if (!next) return history;

  return {
    back: [...history.back, history.current],
    current: next,
    forward: remaining,
  };
}
