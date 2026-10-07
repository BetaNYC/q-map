/**
 * §5's map selection parameters, `?layers=` and `?categories=`: reading them
 * from a URL and writing a toggle back.
 *
 * Shared by the phone map page, which owns its own map, and the root layout,
 * which reads the URL of whatever page is open for the docked desktop map. One
 * implementation, so a link means the same thing on both.
 *
 * The rules, from §5 and the map page as first built:
 *
 *   - Absent means the page's default, not empty. `parseSelection` returns
 *     null for an absent parameter so the caller can apply its own default.
 *   - Present but empty (`?layers=`) is an explicit empty selection.
 *   - Unknown ids are dropped, never fatal: a link shared before a layer was
 *     retired opens the map minus that layer.
 *   - Order does not matter. Selections come back in the order of `known`.
 *
 * And one rule added for the docked map, where the default differs per page:
 * a selection equal to the page's default is written as no parameter at all.
 * The shortest URL is the one worth sharing, and it keeps meaning "this page's
 * default" if the default later changes.
 */

/**
 * A comma-separated selection, as given in the URL. null: the parameter is
 * absent. Without `known`, every non-empty id is kept, for callers that have no
 * list to check against; an unknown id then simply matches nothing on the map.
 */
export function parseSelection(param: string | null, known?: readonly string[]): string[] | null {
  if (param === null) return null;
  const given = param.split(',').filter(Boolean);
  if (!known) return given;
  const set = new Set(given);
  return known.filter((id) => set.has(id));
}

/**
 * `current` with `id` switched, in the order of `known`. `current` is the
 * effective selection, defaults already applied; for categories, where null
 * means all, pass the full list.
 */
export function toggleSelection(
  current: readonly string[],
  id: string,
  known: readonly string[]
): string[] {
  const on = new Set(current);
  if (on.has(id)) on.delete(id);
  else on.add(id);
  return known.filter((k) => on.has(k));
}

/**
 * A copy of `url` with parameter `name` set to `next`, or removed when `next`
 * is the page's default. `fallback` is that default, with null meaning every
 * id in `known` (the categories default).
 */
export function withSelection(
  url: URL,
  name: string,
  next: readonly string[],
  fallback: readonly string[] | null,
  known: readonly string[]
): URL {
  const out = new URL(url);
  const defaults = new Set(fallback ?? known);
  const isDefault =
    next.length === known.filter((id) => defaults.has(id)).length &&
    next.every((id) => defaults.has(id));

  if (isDefault) out.searchParams.delete(name);
  else out.searchParams.set(name, next.join(','));
  return out;
}
