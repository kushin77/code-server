/**
 * @file session-indexeddb-store.ts
 * @description Shared IndexedDB store for session expiry between Service Worker and page JS.
 *              Service Workers cannot read cookies (security boundary), so we use IndexedDB
 *              to share the expiry timestamp from the companion cookie.
 * @module session/storage
 */

const DB_NAME = 'code-server-session';
const DB_VERSION = 1;
const STORE_NAME = 'metadata';
const EXPIRY_KEY = 'session_expiry';

/**
 * Opens or creates the IndexedDB database
 */
async function openDatabase(): Promise<IDBDatabase> {
  return new Promise((resolve, reject) => {
    const request = indexedDB.open(DB_NAME, DB_VERSION);

    request.onerror = () => reject(request.error);
    request.onsuccess = () => resolve(request.result);

    request.onupgradeneeded = (event) => {
      const db = (event.target as IDBOpenDBRequest).result;
      if (!db.objectStoreNames.contains(STORE_NAME)) {
        db.createObjectStore(STORE_NAME);
      }
    };
  });
}

/**
 * Stores the session expiry timestamp in IndexedDB
 * Called by page JS after reading _session_expires cookie
 * @param expiry - Unix timestamp (ms) when session expires
 */
export async function storeSessionExpiry(expiry: number): Promise<void> {
  try {
    const db = await openDatabase();
    return new Promise((resolve, reject) => {
      const tx = db.transaction(STORE_NAME, 'readwrite');
      const store = tx.objectStore(STORE_NAME);
      const request = store.put(expiry, EXPIRY_KEY);

      request.onerror = () => reject(request.error);
      tx.oncomplete = () => resolve();
    });
  } catch (error) {
    console.warn('[session-store] Failed to store expiry in IndexedDB:', error);
    // Graceful degradation: SW will handle missing expiry
  }
}

/**
 * Retrieves the session expiry timestamp from IndexedDB
 * Called by Service Worker to know when to refresh
 * @returns Expiry timestamp or null if not set
 */
export async function getSessionExpiry(): Promise<number | null> {
  try {
    const db = await openDatabase();
    return new Promise((resolve, reject) => {
      const tx = db.transaction(STORE_NAME, 'readonly');
      const store = tx.objectStore(STORE_NAME);
      const request = store.get(EXPIRY_KEY);

      request.onerror = () => reject(request.error);
      request.onsuccess = () => resolve(request.result || null);
    });
  } catch (error) {
    console.warn('[session-store] Failed to retrieve expiry from IndexedDB:', error);
    return null;
  }
}

/**
 * Clears the session expiry from IndexedDB (called on logout)
 */
export async function clearSessionExpiry(): Promise<void> {
  try {
    const db = await openDatabase();
    return new Promise((resolve, reject) => {
      const tx = db.transaction(STORE_NAME, 'readwrite');
      const store = tx.objectStore(STORE_NAME);
      const request = store.delete(EXPIRY_KEY);

      request.onerror = () => reject(request.error);
      tx.oncomplete = () => resolve();
    });
  } catch (error) {
    console.warn('[session-store] Failed to clear expiry from IndexedDB:', error);
  }
}

/**
 * Checks if session is currently valid based on stored expiry
 * Useful for early bailout in SW without making a request
 */
export async function isSessionValid(): Promise<boolean> {
  const expiry = await getSessionExpiry();
  if (!expiry) return false;
  return Date.now() < expiry;
}
