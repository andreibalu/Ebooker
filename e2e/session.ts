// The native compatibility helper joins the mobile engine's sole worker slot.
// Keep these together: additional workers require per-worker session routing.
export const MOBILE_SESSION = 'unpaged-e2e';
export const MOBILE_WORKERS = 1;
export const NATIVE_WORKER_SESSION = `${MOBILE_SESSION}-0`;
