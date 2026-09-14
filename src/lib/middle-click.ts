export interface MouseButtonEvent {
  button: number;
  preventDefault: () => void;
}

export function handleMiddleMouseDown(
  event: MouseButtonEvent,
  action: () => void,
): void {
  if (event.button !== 1) return;
  event.preventDefault();
  action();
}
