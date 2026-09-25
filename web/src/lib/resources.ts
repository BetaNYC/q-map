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
 * Turn the one HTML tag that appears in the data into a line break.
 *
 * 27 FRANC `mission` values contain literal `<br>` — "Fridays 9:30AM-<br>10:30AM",
 * "Food Distribution: 1st & 3rd Thursday<br>Nurturing Children…". It is the
 * only tag anywhere in `data/processed/`: no other resource field, no gap
 * sentence and no hazard content carries markup.
 *
 * Svelte escapes by default, so left alone these render as a visible "<br>" in
 * the middle of a sentence. The alternatives were:
 *
 *   {@html}       renders the tag, and opens every one of 3,795 records as an
 *                 injection surface for a field sourced from a scrape.
 *   substitution  converts only <br> to a newline, which `white-space:
 *                 pre-line` then renders, and leaves everything else escaped.
 *
 * The second is what this does. Anything OTHER than <br> appearing later still
 * shows up literally — visible and reportable rather than silently executed.
 *
 * This is a workaround for a pipeline issue: `mission` is documented as a
 * string and should not carry markup. Flagged in web/README.md.
 */
export function plainText(value: string): string {
  return value.replace(/<br\s*\/?>/gi, '\n');
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

/**
 * Actionable contact values.
 *
 * DEPARTURE FROM THE FRAME, and a deliberate one. Figma draws the resource
 * detail screen's phone, email and website as plain black text. On a phone, in
 * an emergency, a number you cannot tap is a usability failure — and the app
 * already establishes the opposite treatment: §7.6's PhoneElement renders
 * hazard phone numbers as `tel:` links in blue. This applies the same rule to
 * a resource's own contact details rather than inventing one. Flagged in
 * web/README.md.
 *
 * Each returns null where the value cannot be trusted to be a single target,
 * and the caller renders plain text instead. That matters: the data is not
 * uniformly clean, and a link that dials the wrong number is worse than text.
 *
 *   phone    166 of 167 are one number; one is "855.322.4357/718.657.6195".
 *            161 have 10 digits, 5 have 13 (an extension or a country code).
 *   email    166 of 169 are one address; three are
 *            "Imanansob@gmail.com/ Info@Ansob.org".
 *   website  All 163 are single. The nine that contain a slash are URL PATHS
 *            ("stfidelischurch.org/events/street-outreach"), not two sites —
 *            which is why a naive multi-value check on "/" is wrong here.
 */

/** `tel:` for a value that is unambiguously one North American number. */
export function telHref(value: string): string | null {
  // Any separator means more than one number, or a number with commentary.
  if (/[,;/]| or | and /i.test(value)) return null;

  const digits = value.replace(/\D/g, '');
  if (digits.length === 10) return `tel:+1${digits}`;
  if (digits.length === 11 && digits.startsWith('1')) return `tel:+${digits}`;
  // 13 digits is an extension or a non-NANP number; dialling the first ten of
  // it would be a guess.
  return null;
}

/** `mailto:` for a value that is unambiguously one address. */
export function mailtoHref(value: string): string | null {
  const trimmed = value.trim();
  if (/[,;/\s]/.test(trimmed)) return null;
  if ((trimmed.match(/@/g) ?? []).length !== 1) return null;
  return `mailto:${trimmed}`;
}

/** An absolute URL. Values arrive bare ("hercareinc.org"), so a scheme is
 *  added — without one the browser resolves it as a relative path. */
export function websiteHref(value: string): string | null {
  const trimmed = value.trim();
  if (!trimmed || /\s/.test(trimmed)) return null;
  return /^https?:\/\//i.test(trimmed) ? trimmed : `https://${trimmed}`;
}
