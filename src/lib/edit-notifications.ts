/** Batch secondary UI updates, never the draft itself or persistence. */
export function createEditNotifications(notify: () => void, delay = 100, maxWait = 250) {
  let trailing: ReturnType<typeof setTimeout> | undefined;
  let deadline: ReturnType<typeof setTimeout> | undefined;
  const flush = () => {
    clearTimeout(trailing);
    clearTimeout(deadline);
    trailing = deadline = undefined;
    notify();
  };
  return {
    flush,
    schedule() {
      clearTimeout(trailing);
      trailing = setTimeout(flush, delay);
      deadline ??= setTimeout(flush, maxWait);
    },
  };
}
