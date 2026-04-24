import { useEffect, useState } from 'react';
const STORAGE_KEY = 'portal-control-plane:v1';
export function useWorkspaceStorage(initialSnapshot) {
    const [snapshot, setSnapshot] = useState(initialSnapshot);
    // Persist to localStorage whenever snapshot changes
    useEffect(() => {
        if (typeof window === 'undefined') {
            return;
        }
        window.localStorage.setItem(STORAGE_KEY, JSON.stringify(snapshot));
    }, [snapshot]);
    return { snapshot, setSnapshot };
}
//# sourceMappingURL=useWorkspaceStorage.js.map