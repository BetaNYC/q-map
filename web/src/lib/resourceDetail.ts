import { plainText, websiteHref } from './resources';
import type { Resource } from './types';

/**
 * A resource record -> the grouped fields the detail page renders.
 * Figma: "05 Resource Detail - Mobile" — About / Contact / Access, then
 * "About this listing" (frontend cycle 2, step 6).
 *
 * Pure, so every rule is tested against real records (resourceDetail.test.ts).
 *
 * Decisions (2026-09-30): referrals ALWAYS shown when present (supersedes
 * handoff §7.5's "only when not Yes"); `social` is not rendered; the address
 * opens the device's maps app where the platform allows (mapsHref).
 */

export interface Line {
  text: string;
  href?: string;
  /** Opens outside the site - rendered with rel="noopener noreferrer". */
  external?: boolean;
}

export interface Field {
  label: string;
  lines: Line[];
  /** The address: its href is upgraded per platform in the browser. */
  maps?: boolean;
}

export interface Group {
  title: 'About' | 'Contact' | 'Access';
  fields: Field[];
}

/**
 * "718.784.7447 ext.135" -> tel:+17187847447,135 - the comma is a dialling
 * pause, so a phone dials the extension after the call connects. Five of the
 * 167 phone numbers carry an extension ("ext.135", "x 303"); they were
 * unlinked before.
 */
export function phoneHref(value: string): string | null {
  const m = value.trim().match(/^(.*?)(?:\s*(?:ext\.?|x)\s*(\d+))?$/i);
  if (!m) return null;
  const digits = m[1].replace(/\D/g, '');
  const ext = m[2] ? `,${m[2]}` : '';
  if (digits.length === 10) return `tel:+1${digits}${ext}`;
  if (digits.length === 11 && digits.startsWith('1')) return `tel:+${digits}${ext}`;
  return null;
}

/** A field holding several numbers or addresses -> one per line. */
function split(value: string): string[] {
  return value
    .split(/\s*[/;,]\s*|\s+and\s+/i)
    .map((s) => s.trim())
    .filter(Boolean);
}

/**
 * Only something shaped like a host becomes a website. One record's website
 * field holds a street address ("133-33 Brookville Blvd. LL5,") - a data
 * error that is omitted rather than shown under "Website".
 */
function websiteLine(value: string): Line | null {
  const v = value.trim();
  if (/\s/.test(v) || !/^(https?:\/\/)?[a-z0-9-]+(\.[a-z0-9-]+)+(\/\S*)?$/i.test(v)) return null;
  const href = websiteHref(v);
  return href ? { text: v.replace(/^https?:\/\//i, '').replace(/\/$/, ''), href, external: true } : null;
}

/** Where the platform cannot be known - prerendered HTML, desktop: a web map. */
export function webMapHref(lat: number, lon: number): string {
  return `https://www.google.com/maps/search/?api=1&query=${lat}%2C${lon}`;
}

/**
 * The device's own maps app (decision 5c). There is no single URL for
 * "the default maps app", so:
 *   android  geo: - the user's default maps app, or a chooser
 *   ios      Apple Maps - the system app; iOS has no URL that honours a
 *            third-party default
 *   other    a web map
 * Coordinates, not the address string, so the pin is exact however messy the
 * address text.
 */
export function mapsHref(platform: 'android' | 'ios' | 'other', lat: number, lon: number, name: string): string {
  if (platform === 'android') return `geo:${lat},${lon}?q=${lat},${lon}(${encodeURIComponent(name)})`;
  if (platform === 'ios') return `https://maps.apple.com/?q=${encodeURIComponent(name)}&ll=${lat},${lon}`;
  return webMapHref(lat, lon);
}

export function platformOf(nav: Pick<Navigator, 'userAgent' | 'platform' | 'maxTouchPoints'>): 'android' | 'ios' | 'other' {
  if (/Android/i.test(nav.userAgent)) return 'android';
  // iPadOS reports itself as a Mac; touch points give it away.
  if (/iPad|iPhone|iPod/.test(nav.userAgent) || (nav.platform === 'MacIntel' && nav.maxTouchPoints > 1)) return 'ios';
  return 'other';
}

export function groupsFor(r: Resource): Group[] {
  const field = (label: string, lines: (Line | null)[], extra: Partial<Field> = {}): Field | null => {
    const kept = lines.filter((l): l is Line => !!l && !!l.text.trim());
    return kept.length ? { label, lines: kept, ...extra } : null;
  };
  const text = (v?: string): Line | null => (v?.trim() ? { text: v.trim() } : null);

  const groups: Group[] = [
    { title: 'About', fields: [field('Mission', [r.mission ? { text: plainText(r.mission) } : null])] },
    {
      title: 'Contact',
      fields: [
        r.address
          ? field('Address', [{ text: r.address, href: webMapHref(r.lat, r.lon), external: true }], { maps: true })
          : null,
        r.phone ? field('Phone', split(r.phone).map((p) => ({ text: p, href: phoneHref(p) ?? undefined }))) : null,
        field('Contact', [text(r.contact_name)]),
        r.email ? field('Email', split(r.email).filter((e) => e.includes('@')).map((e) => ({ text: e, href: `mailto:${e}` }))) : null,
        r.website ? field('Website', [websiteLine(r.website)]) : null
      ]
    },
    {
      title: 'Access',
      fields: [
        field('Languages served', [text(r.languages)]),
        field('Fees', [text(r.fees)]),
        field('Accepts referrals', [text(r.accepts_referrals)])
      ]
    }
  ].map((g) => ({ title: g.title as Group['title'], fields: g.fields.filter((f): f is Field => f !== null) }));

  return groups.filter((g) => g.fields.length > 0);
}

/** "About this listing". "Call to confirm details." only when there is a number to call. */
export function listingNote(r: Resource): string {
  const source = r.source === 'franc' ? 'the FRANC resource map' : 'the Queens Nonprofit Directory';
  return r.phone ? `From ${source}. Call to confirm details.` : `From ${source}.`;
}
