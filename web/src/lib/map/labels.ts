/**
 * District-name placement for the Queens overview maps: the entry page's
 * DistrictPicker and the docked Map with no district selected.
 *
 * EVERY NAME ALWAYS SHOWS (Andrew, 2026-11-05: users were sensitive to names
 * disappearing). Both maps used to hide any label that overlapped one already
 * placed, largest district first; on a phone that dropped 4 of the 14 at the
 * opening view. Now a clashing label is MOVED, never hidden:
 *
 *   1. Names wrap onto two lines at their hyphens (CSS, in each component), so
 *      "Kew Gardens-Richmond Hill-Woodhaven" is a compact block, not a 150px
 *      line.
 *   2. Placed SMALLEST district first, each label takes the nearest offset
 *      at which it overlaps nothing already placed. Smallest first because a
 *      small district has the least room around its label: placed last (as
 *      the old hiding rule had it), Kew Gardens-Richmond Hill-Woodhaven was
 *      pushed out of its district into Jamaica Bay. The big districts' labels
 *      have room to move and stay inside their own.
 *   3. If no offset within reach is clear, it takes the one that overlaps
 *      least. It still shows.
 *
 * Kept pure (boxes in, offsets out) so it can be tested without a map.
 */

export interface Box {
  /** Left, top, width, height in screen pixels, at the label's anchor. */
  x: number;
  y: number;
  w: number;
  h: number;
}

export interface Offset {
  dx: number;
  dy: number;
}

/** How far a label may move: up to MAX_STEPS steps of half its height (plus
 *  padding) up or down, and a quarter or half its width sideways. Beyond that
 *  it would sit over the wrong district. */
const MAX_STEPS = 6;

function overlap(a: Box, b: Box, pad: number): number {
  const w = Math.min(a.x + a.w, b.x + b.w) + pad - (Math.max(a.x, b.x) - pad);
  const h = Math.min(a.y + a.h, b.y + b.h) + pad - (Math.max(a.y, b.y) - pad);
  return w > 0 && h > 0 ? w * h : 0;
}

/** Candidate offsets for a box, nearest first. The vertical step is half the
 *  box plus its padding, so two steps stack two labels exactly clear of each
 *  other - plain half-heights left them a padding's width short. */
function candidates(box: Box, pad: number): Offset[] {
  const step = box.h / 2 + pad;
  const dys = [0];
  for (let i = 1; i <= MAX_STEPS; i++) dys.push(-step * i, step * i);
  const out: Offset[] = [];
  for (const fx of [0, -0.25, 0.25, -0.5, 0.5]) for (const dy of dys) out.push({ dx: box.w * fx, dy });
  // Nearest first, in any direction: the first clear spot is then also the
  // least displacement, so a label stays as close to its district as it can.
  return out.sort((a, b) => Math.hypot(a.dx, a.dy) - Math.hypot(b.dx, b.dy));
}

/**
 * One offset per box, in the order given (smallest district first). A box is
 * never dropped: if nothing within reach is clear, it gets the offset with
 * the least overlap.
 */
export function resolveLabelOffsets(boxes: readonly Box[], pad = 1): Offset[] {
  const placed: Box[] = [];
  return boxes.map((box) => {
    let best: Offset = { dx: 0, dy: 0 };
    let bestOverlap = Infinity;
    for (const o of candidates(box, pad)) {
      const moved = { ...box, x: box.x + o.dx, y: box.y + o.dy };
      const total = placed.reduce((sum, p) => sum + overlap(moved, p, pad), 0);
      if (total < bestOverlap) {
        best = o;
        bestOverlap = total;
        if (total === 0) break;
      }
    }
    placed.push({ ...box, x: box.x + best.dx, y: box.y + best.dy });
    return best;
  });
}

/** The shape both maps' markers share: the DOM element and MapLibre's offset. */
interface LabelMarker {
  getElement(): HTMLElement;
  setOffset(offset: [number, number]): unknown;
}

/**
 * Lay out a map's district labels: clear last time's offsets, measure, place.
 * Call after the markers exist and on every zoomend (a label's size changes
 * with zoom, and so do the gaps between districts).
 */
export function placeLabels(markers: readonly LabelMarker[]): void {
  for (const m of markers) m.setOffset([0, 0]);
  requestAnimationFrame(() => {
    const boxes = markers.map((m) => {
      const r = m.getElement().getBoundingClientRect();
      return { x: r.left, y: r.top, w: r.width, h: r.height };
    });
    resolveLabelOffsets(boxes).forEach((o, i) => markers[i].setOffset([Math.round(o.dx), Math.round(o.dy)]));
  });
}
