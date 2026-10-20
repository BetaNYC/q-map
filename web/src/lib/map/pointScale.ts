/**
 * How big the resource points are at each zoom.
 *
 * d26's ramp (~/Github/d26-gi-web-map, web/src/lib/map/markers.ts
 * `ICON_NATIVE_PX` and `ICON_SIZE_RAMP`): a 20px square up to zoom 15, then
 * linear to 1.75x (35px) at zoom 20, held there beyond. d26 drew Figma's 16px
 * design at 20px and ramped that; so does this (Andrew, 2026-10-20).
 *
 * d26 applies it as a symbol layer's `icon-size`. Here the points are HTML
 * markers, and Map.svelte writes the size to one custom property on every
 * zoom frame. The marker SIZES itself from it - box and letter - rather than
 * being scaled with a transform, so its border stays one crisp line. A
 * transform scaled the border too: Chrome draws the 0.75px border as 1px, so
 * it grew to ~1.75px and smeared across a third device pixel the moment the
 * scale passed 1, which read as a sudden jump in weight just past zoom 15.
 */
export const POINT_BASE_PX = 20;
export const POINT_SIZE_RAMP = { zMin: 15, sMin: 1, zMax: 20, sMax: 1.75 } as const;

export function pointScale(zoom: number): number {
  const { zMin, sMin, zMax, sMax } = POINT_SIZE_RAMP;
  if (zoom <= zMin) return sMin;
  if (zoom >= zMax) return sMax;
  return sMin + ((sMax - sMin) * (zoom - zMin)) / (zMax - zMin);
}

/** The point's square, in CSS px, at `zoom`. */
export function pointSizePx(zoom: number): number {
  return POINT_BASE_PX * pointScale(zoom);
}
