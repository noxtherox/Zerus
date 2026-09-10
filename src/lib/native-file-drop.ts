export function nativeFileDropPoint(
  position: { x: number; y: number },
  scaleFactor: number,
  platform = navigator.platform,
) {
  // Wry 0.55's AppKit handler emits logical points, despite Tauri's PhysicalPosition label.
  const scale = /Mac|iPhone|iPad/.test(platform) ? 1 : Math.max(1, scaleFactor);
  return { x: position.x / scale, y: position.y / scale };
}
