export function shouldDismissImagePopover(
  eventPath: EventTarget[],
  popover: EventTarget | null,
  selectedImage: EventTarget | null,
): boolean {
  return (
    (!popover || !eventPath.includes(popover)) &&
    (!selectedImage || !eventPath.includes(selectedImage))
  );
}
