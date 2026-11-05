/**
 * The basemap style.
 *
 * CARTO Positron, as d26 uses — a MapLibre-native style, no API key, light grey
 * streets. Centralised here so swapping it is a one-line change.
 *
 * THIS IS THE APP'S ONLY THIRD-PARTY RUNTIME DEPENDENCY, and it is worth being
 * explicit about that. Everything else — every payload, every overlay, both
 * PMTiles archives, the fonts — is served same-origin from Pages. This is
 * fetched from basemaps.cartocdn.com on every map load, which means:
 *
 *   - If CARTO is down or blocked, the map renders with no streets. The
 *     overlays and resource points still draw, because they are ours.
 *   - It is a third party observing requests from an emergency-preparedness
 *     tool.
 *
 * Neither the 04 Map frames nor the entry screen's picker draw a street
 * basemap — the picker shows district outlines on a plain ground. So "no
 * basemap at all" is a defensible reading of the design, and would remove the
 * dependency entirely. It would also make it much harder to tell where a
 * cooling centre actually is, which is the point of the screen.
 *
 * The fix that keeps both is a self-hosted Protomaps basemap: one .pmtiles
 * file in data/processed/, served same-origin through the protocol already
 * registered for the stormwater layers. That is a pipeline change, so it is
 * flagged rather than done here. See web/README.md.
 */
export const BASEMAP_STYLE = 'https://basemaps.cartocdn.com/gl/positron-gl-style/style.json';

/**
 * Where the map sits before a district's bounds are applied. Queens' rough
 * centre — only ever visible for the frame or two before `fitBounds` runs.
 */
export const INITIAL_CENTER: [number, number] = [-73.82, 40.71];
export const INITIAL_ZOOM = 10;
export const MIN_ZOOM = 8.75;
export const MAX_ZOOM = 19;
export const MAX_BOUNDS: [[number, number], [number, number]] = [[-74.8, 40.05], [-72.75, 41.3]];

/**
 * The basemap layer the 'under-roads' overlays are inserted before
 * ($lib/map/overlays.ts): Positron's first road layer. Everything Positron
 * draws from here up - tunnels, roads, bridges, buildings, labels - lands on
 * top of the graded flood fills, so an opaque fill never hides a street.
 * Water and land cover stay beneath them.
 *
 * A layer id in someone else's style can change without notice. Map.svelte
 * checks it exists and, if not, draws the overlays on top instead: streets
 * hidden under a fill is a worse map, but a missing beforeId would throw and
 * leave no map at all.
 */
export const BASEMAP_ROADS_BEFORE = 'tunnel_service_case';

/** How many zoom levels a basemap layer takes to fade in (Andrew, 2026-11-05). */
export const BASEMAP_FADE_ZOOMS = 1;

/** The part of a map this needs - narrow so a test can pass a stub. */
interface StyleTarget {
  getStyle(): { layers?: Array<{ id: string; type: string; minzoom?: number; 'source-layer'?: string }> } | undefined;
  getPaintProperty(layerId: string, name: string): unknown;
  setPaintProperty(layerId: string, name: string, value: unknown): void;
}

const OPACITY_PROPERTY: Record<string, string> = {
  fill: 'fill-opacity',
  line: 'line-opacity'
};

/**
 * Where the DATA arrives later than the layer starts. A layer's minzoom is
 * when Positron starts drawing it; what it draws is whatever CARTO's tiles
 * hold at that zoom. For buildings that is a small fraction until z15, so a
 * fade from the layer's minzoom (13) finished long before most buildings
 * arrived, and they still snapped on (Andrew, 2026-11-05).
 *
 * Building outlines over the same ground around Howard Beach, CARTO's
 * 2026-10-26 build (counted by outline: the low-zoom tiles merge many
 * buildings into one feature, so a feature count reads far too low):
 *
 *   z13  ~290      z14  ~3,200      z15  ~20,000
 *
 * Two jumps, and nothing per building to fade them one by one. So the whole
 * layer fades in over 15-16, where the last of them land (Andrew chose this
 * knowing the cost: no buildings below z15, including the ~3,200 mid-sized
 * ones the z14 tiles carry).
 *
 * Streets were checked the same way and do NOT jump - minor-road segments
 * run ~1,000, ~1,300, ~1,600 over z13-15 - so they keep the plain fade from
 * their layer's minzoom.
 *
 * These are facts about CARTO's tiles, not its style, and can change with a
 * new build. If they do, the worst case is a snap coming back.
 */
const DATA_ARRIVES: Array<{ match: (layer: { id: string; 'source-layer'?: string }) => boolean; zoom: number }> = [
  { match: (l) => l['source-layer'] === 'buildings', zoom: 15 }
];

/**
 * Fade Positron's roads, buildings and other features in as you zoom, instead
 * of letting them appear all at once (Andrew, 2026-11-05: "jarring").
 *
 * Positron starts most road and building layers at a fixed zoom - minor roads
 * at 13 and 15, buildings at 13 - at full opacity, so they snap on. This
 * replaces each such layer's opacity with a ramp: 0 at its start zoom, its
 * normal opacity BASEMAP_FADE_ZOOMS later.
 *
 * WHICH LAYERS. Fills and lines only: labels already fade in (MapLibre's
 * fadeDuration, 300ms). Only a layer that has a start zoom the app can reach,
 * and whose opacity is a plain number or unset. A layer Positron already
 * styles by zoom (major roads half-fade at 5-7) is left alone rather than
 * overwritten - unless its data arrives late (DATA_ARRIVES), when the fade
 * starts at that later zoom instead.
 *
 * Read from the loaded style, not hard-coded, so a CARTO update to the style
 * can at worst leave a new layer snapping on again - never break the map.
 *
 * NOT FIXED BY THIS: tiles are simplified differently at each whole zoom, so a
 * shoreline can still visibly sharpen crossing from z12 to z13. That is the
 * data, not the styling.
 *
 * Call once on the map's `load`, before adding our own layers: anything that
 * is not in the style yet is untouched, which is the intent.
 */
export function fadeInBasemapLayers(map: StyleTarget, fromZoom: number, width = BASEMAP_FADE_ZOOMS): string[] {
  const faded: string[] = [];
  for (const layer of map.getStyle()?.layers ?? []) {
    const property = OPACITY_PROPERTY[layer.type];
    const late = DATA_ARRIVES.find((d) => d.match(layer))?.zoom;
    const start = late === undefined ? layer.minzoom : Math.max(late, layer.minzoom ?? 0);
    // A layer that is already on at the app's lowest zoom never appears
    // during use, so there is nothing to fade.
    if (!property || start === undefined || start <= fromZoom) continue;
    const current = map.getPaintProperty(layer.id, property);
    // Positron's own zoom styling is kept - except where the data arrives
    // late, because that styling fades over the wrong zooms (the building
    // tops fade 13-16, and are still at 67% when every building lands at 15).
    if (current !== undefined && typeof current !== 'number' && late === undefined) continue;
    const full = typeof current === 'number' ? current : 1;
    map.setPaintProperty(layer.id, property, ['interpolate', ['linear'], ['zoom'], start, 0, start + width, full]);
    faded.push(layer.id);
  }
  return faded;
}
