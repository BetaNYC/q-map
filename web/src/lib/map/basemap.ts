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
