import * as maplibregl from 'maplibre-gl';
// `?worker&url`: Vite bundles the worker entry — including its import of
// ./maplibre-gl-shared.mjs — into one file of its own and hands back that
// file's URL. It is emitted with a hashed name under _app/immutable, so the
// /q-map/ base path is already applied.
import workerUrl from 'maplibre-gl/dist/maplibre-gl-worker.mjs?worker&url';

let configured = false;

/**
 * Point MapLibre at its web worker. Call before the first `new Map()`.
 *
 * maplibre-gl 6 ships ESM-only and, left alone, looks for its worker as a
 * SIBLING of the module that imported it:
 * `new URL('./maplibre-gl-worker.mjs', import.meta.url)`. Once Vite has bundled
 * MapLibre into an app chunk, that sibling does not exist — the URL is built
 * from a variable, so Vite cannot see it to emit the file. The build succeeds,
 * and every map then fails at runtime on a 404 for the worker. The same happens
 * in `vite dev`, where MapLibre is served from the pre-bundled deps cache.
 *
 * Idempotent: the worker URL is global to MapLibre, not per-map, and both the
 * entry picker and the district map call this.
 */
export function configureMapWorker(): void {
  if (configured) return;
  maplibregl.setWorkerUrl(workerUrl);
  configured = true;
}
