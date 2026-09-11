const DATABASE_NAME = "zerus-startup-cache";
const STORE_NAME = "vaults";

function openDatabase(): Promise<IDBDatabase | null> {
  if (typeof indexedDB === "undefined") return Promise.resolve(null);
  return new Promise((resolve) => {
    let settled = false;
    const finish = (database: IDBDatabase | null) => {
      if (settled) {
        database?.close();
        return;
      }
      settled = true;
      resolve(database);
    };
    try {
      const request = indexedDB.open(DATABASE_NAME, 1);
      request.onupgradeneeded = () => {
        if (!request.result.objectStoreNames.contains(STORE_NAME)) {
          request.result.createObjectStore(STORE_NAME);
        }
      };
      request.onsuccess = () => finish(request.result);
      request.onerror = () => finish(null);
      request.onblocked = () => finish(null);
    } catch {
      finish(null);
    }
  });
}

export function hasLargeStartupCache(): boolean {
  return typeof indexedDB !== "undefined";
}

export async function readLargeStartupCache<T>(key: string): Promise<T | null> {
  const database = await openDatabase();
  if (!database) return null;
  try {
    return await new Promise<T | null>((resolve) => {
      const request = database.transaction(STORE_NAME, "readonly").objectStore(STORE_NAME).get(key);
      request.onsuccess = () => resolve((request.result as T | undefined) ?? null);
      request.onerror = () => resolve(null);
    });
  } catch {
    return null;
  } finally {
    database.close();
  }
}

const pendingWrites = new Map<string, Promise<void>>();

async function writeValue(key: string, value: unknown): Promise<void> {
  const database = await openDatabase();
  if (!database) return;
  try {
    await new Promise<void>((resolve, reject) => {
      const transaction = database.transaction(STORE_NAME, "readwrite");
      transaction.objectStore(STORE_NAME).put(value, key);
      transaction.oncomplete = () => resolve();
      transaction.onerror = () => reject(transaction.error);
      transaction.onabort = () => reject(transaction.error);
    });
  } finally {
    database.close();
  }
}

/**
 * Serializes writes per vault so a slower, older snapshot cannot replace a
 * newer one when several note changes update the cache close together.
 */
export function writeLargeStartupCache(key: string, value: unknown): Promise<void> {
  const previous = pendingWrites.get(key) ?? Promise.resolve();
  const next = previous.catch(() => undefined).then(() => writeValue(key, value));
  pendingWrites.set(key, next);
  const cleanup = () => {
    if (pendingWrites.get(key) === next) pendingWrites.delete(key);
  };
  void next.then(cleanup, cleanup);
  return next;
}
