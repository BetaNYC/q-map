/**
 * How much the resource points grow as the map zooms in.
 *
 * d26's ramp, carried over exactly (~/Github/d26-gi-web-map,
 * web/src/lib/map/markers.ts `ICON_SIZE_RAMP`): native size up to zoom 15,
 * then linear to 1.75x at zoom 20, held there beyond. d26 applies it as a
 * symbol layer's `icon-size`; here the points are HTML markers, so Map.svelte
 * applies it as a CSS scale on every zoom frame.
 *
 * Native is PointMarker's 16px (Figma 261:1276). d26 drew its 16px design at
 * 20px before ramping; that part is not carried over.
 */
export const POINT_SIZE_RAMP = { zMin: 15, sMin: 1, zMax: 20, sMax: 1.75 } as const;

export function pointScale(zoom: number): number {
  const { zMin, sMin, zMax, sMax } = POINT_SIZE_RAMP;
  if (zoom <= zMin) return sMin;
  if (zoom >= zMax) return sMax;
  return sMin + ((sMax - sMin) * (zoom - zMin)) / (zMax - zMin);
}
