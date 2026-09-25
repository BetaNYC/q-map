import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import type { MapLayer } from '$lib/layers';

/**
 * Reads `data/registry/map_layers.csv` at build time.
 *
 * `$lib/server/` is a SvelteKit-protected directory: importing it from
 * client-side code is a build error, not a runtime surprise. That matters here
 * because this reaches outside `web/` into the repo's human-owned registry, and
 * nothing about that path should ever reach a browser.
 *
 * WHY READ THE REGISTRY RATHER THAN SHIP IT:
 *
 * The registry is the vocabulary for hazard content's `map_layers` and §6's
 * "only rows with status: available can be shown", but it is not among the
 * artifacts in DATA_CONTRACT.md §1 — the pipeline does not emit it to
 * `data/processed/`. So the frontend has no runtime source for layer labels or
 * their available/blocked status.
 *
 * Reading the committed CSV at build time is the option that does not create a
 * second copy. The alternative — hardcoding ten labels in TypeScript — is the
 * hand-maintained table that CLAUDE.md says drifts, and it would drift silently
 * the first time a layer was retired.
 *
 * The better long-term fix is for the pipeline to emit the registry as
 * `data/processed/layers.json`, which would also let the map screen show
 * blocked layers as "not available yet" rather than omitting them. Flagged in
 * web/README.md; it is a pipeline change, and CI owns data/processed.
 */
const REGISTRY = join(process.cwd(), '..', 'data', 'registry', 'map_layers.csv');

/**
 * Minimal RFC 4180 reader — enough for this file and no more.
 *
 * Hand-rolled rather than pulled in as a dependency because it parses exactly
 * one known file at build time. It DOES need quote handling: the `notes` column
 * contains commas inside quoted strings, and a naive split on "," silently
 * shifts every column after it.
 */
function parseCsv(text: string): Record<string, string>[] {
  const rows: string[][] = [];
  let row: string[] = [];
  let field = '';
  let quoted = false;

  for (let i = 0; i < text.length; i++) {
    const c = text[i];

    if (quoted) {
      if (c === '"') {
        if (text[i + 1] === '"') {
          field += '"'; // an escaped quote inside a quoted field
          i++;
        } else {
          quoted = false;
        }
      } else {
        field += c;
      }
      continue;
    }

    if (c === '"') quoted = true;
    else if (c === ',') {
      row.push(field);
      field = '';
    } else if (c === '\n') {
      row.push(field);
      rows.push(row);
      row = [];
      field = '';
    } else if (c !== '\r') {
      field += c;
    }
  }

  if (field !== '' || row.length) {
    row.push(field);
    rows.push(row);
  }

  const [header, ...body] = rows;
  return body.map((r) => Object.fromEntries(header.map((h, i) => [h, r[i] ?? ''])));
}

/**
 * The available layers, in registry order.
 *
 * Asserts the file is present and non-trivial: a missing or truncated registry
 * would otherwise yield an empty Layers tab, which looks like a design decision
 * rather than a broken read.
 */
export function readAvailableLayers(): MapLayer[] {
  const rows = parseCsv(readFileSync(REGISTRY, 'utf8'));

  if (rows.length < 10) {
    throw new Error(`${REGISTRY}: parsed only ${rows.length} rows; the registry has 15`);
  }

  const available = rows
    .filter((r) => r.status === 'available')
    .map((r) => ({
      layer_id: r.layer_id,
      label: r.label,
      kind: r.kind as MapLayer['kind'],
      delivery: r.delivery,
      status: r.status
    }));

  if (!available.length) {
    throw new Error(`${REGISTRY}: no rows with status "available"`);
  }

  return available;
}
