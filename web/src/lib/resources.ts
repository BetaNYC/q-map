import type { Resource } from './types';

/**
 * Resource presentation rules (handoff §7.4).
 */

/**
 * Normalise for comparison: case- and punctuation-insensitive.
 *
 * "Variety Boys And Girls Club Of Queens" and "Variety Boys and Girls Club of
 * Queen" are the same organisation, and an exact comparison leaks both of them
 * into the subtitle.
 */
function normalise(value: string): string {
  return value
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, ' ')
    .trim();
}

/**
 * Is the operator just the name again?
 *
 * SUBSTRING IN BOTH DIRECTIONS, not equality — §7.4 is explicit. One direction
 * is not enough: the operator is sometimes a prefix of the name and sometimes
 * the name is a prefix of the operator.
 *
 * Measured across the 3,795 records shipped: 3,441 carry an operator, 1,526 of
 * them (40% of all records) repeat the name outright, and this rule suppresses
 * 1,888 of the 3,441. What survives is the informative half — "Legion Triangle"
 * under NYC Department of Parks and Recreation, "Socrates Sculpture Park" under
 * the same, "P.S. 2 Alfred Zimberg" under Hanac Inc.
 */
function isSameOrganisation(operator: string, name: string): boolean {
  const a = normalise(operator);
  const b = normalise(name);
  if (!a || !b) return false;
  return a.includes(b) || b.includes(a);
}

/**
 * The popup's second line.
 *
 * **Never empty**, which is why there is no boolean for it: `category` is
 * present on every one of the 3,795 records, so the fallback always resolves.
 * Figma exposes a `hasOperator` boolean on the Popup component; it is redundant
 * and is not modelled here — see web/README.md.
 *
 * `operator` is absent on all 248 QNPD and FRANC records, so those always show
 * the category. Of the rest, 1,553 show an operator and 2,242 a category.
 */
export function subtitleFor(resource: Resource, categoryLabel: string): string {
  const { operator, name } = resource;

  if (operator && !isSameOrganisation(operator, name)) {
    return operator;
  }

  return categoryLabel;
}

/**
 * FacDB records have no detail page by design — they are popup-only, and their
 * permalink is /q{NN}/map?resource=facdb:<hash>. 248 of the 3,795 records get a
 * page: 169 QNPD and 79 FRANC.
 */
export function hasDetail(resource: Resource): boolean {
  return resource.source !== 'facdb';
}

/**
 * The detail link's visible text, per source (§7.4).
 *
 * Figma draws "More information", which is exactly the string §10 gives as its
 * example of link text that says nothing out of context. These are §7.4's
 * words; the resource name goes into the accessible name on top. See
 * web/README.md.
 */
export function detailLinkText(resource: Resource): string {
  return resource.source === 'qnpd' ? 'Contact and services' : 'About this resource';
}

/**
 * /q{NN}/resource/{source}/{slug} — `resource_id` split on its one colon.
 *
 * All 248 detail-page ids match [a-z]+:[a-z0-9-]+ with no collisions, so a
 * single split is safe. Returns null for FacDB, which has no page.
 */
export function detailPath(resource: Resource, districtSlug: string): string | null {
  if (!hasDetail(resource)) return null;

  const separator = resource.resource_id.indexOf(':');
  if (separator === -1) return null;

  const source = resource.resource_id.slice(0, separator);
  const slug = resource.resource_id.slice(separator + 1);
  return `/${districtSlug}/resource/${source}/${slug}`;
}
