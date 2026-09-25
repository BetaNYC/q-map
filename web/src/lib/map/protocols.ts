import maplibregl from 'maplibre-gl';
import { Protocol } from 'pmtiles';

let registered = false;

/**
 * Register the `pmtiles://` protocol once, globally.
 *
 * Lifted from d26's `lib/map/protocols.ts`, minus its `cog://` registration —
 * q-map's two raster layers (tree canopy, permeable surface) are `deferred` in
 * the registry and have no artifact, so nothing would use it.
 *
 * Idempotent, so it is safe to call on every map mount. MapLibre's protocol
 * registry is global rather than per-map, and registering twice throws.
 */
export function registerMapProtocols(): void {
  if (registered) return;
  const protocol = new Protocol();
  maplibregl.addProtocol('pmtiles', protocol.tile);
  registered = true;
}
