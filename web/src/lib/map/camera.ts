/**
 * Where each district's map was last looking, for this visit.
 *
 * The phone map is a page of its own, so a trip to a resource page unmounts
 * it, and the map that comes back used to re-fit the district, losing the
 * reader's pan and zoom. Map.svelte records the camera here after every move
 * and, on mounting for a district it has seen, returns to it instead of
 * fitting (Andrew, 2026-10-20).
 *
 * In memory, not in the URL and not in storage: a module-level Map lives as
 * long as the tab's JavaScript does, which is "this visit" exactly. A reload
 * or a new tab starts from the fitted district again, and the URL keeps §5's
 * four parameters - a camera position is not worth putting in a shared link.
 *
 * On desktop the map stays mounted across pages, so its camera already
 * persisted; this changes nothing there.
 */

export interface Camera {
  center: [number, number];
  zoom: number;
}

const cameras = new Map<string, Camera>();

export function rememberCamera(districtSlug: string, camera: Camera): void {
  cameras.set(districtSlug, camera);
}

export function recallCamera(districtSlug: string): Camera | undefined {
  return cameras.get(districtSlug);
}
