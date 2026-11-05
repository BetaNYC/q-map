import { describe, expect, it } from 'vitest';
import { resolveLabelOffsets, type Box } from './labels';

const overlaps = (a: Box, b: Box) => a.x < b.x + b.w && a.x + a.w > b.x && a.y < b.y + b.h && a.y + a.h > b.y;
const moved = (boxes: Box[], offs: { dx: number; dy: number }[]) => boxes.map((b, i) => ({ ...b, x: b.x + offs[i].dx, y: b.y + offs[i].dy }));

describe('resolveLabelOffsets', () => {
  it('leaves labels that do not clash where they are', () => {
    const boxes = [{ x: 0, y: 0, w: 50, h: 10 }, { x: 100, y: 0, w: 50, h: 10 }];
    expect(resolveLabelOffsets(boxes)).toEqual([{ dx: 0, dy: 0 }, { dx: 0, dy: 0 }]);
  });

  it('moves a clashing label clear instead of dropping it, the first one staying put', () => {
    const boxes = [{ x: 0, y: 0, w: 80, h: 10 }, { x: 20, y: 2, w: 80, h: 10 }];
    const offs = resolveLabelOffsets(boxes);
    expect(offs[0]).toEqual({ dx: 0, dy: 0 });
    const [a, b] = moved(boxes, offs);
    expect(overlaps(a, b)).toBe(false);
  });

  it('returns an offset for every label, even when nothing nearby is clear', () => {
    // Fourteen identical boxes on one spot: the worst case.
    const boxes = Array.from({ length: 14 }, () => ({ x: 0, y: 0, w: 60, h: 10 }));
    const offs = resolveLabelOffsets(boxes);
    expect(offs).toHaveLength(14);
    for (const o of offs) expect(Number.isFinite(o.dx) && Number.isFinite(o.dy)).toBe(true);
  });

  it('separates a tight cluster of five', () => {
    const boxes = [0, 4, 8, 12, 16].map((x) => ({ x, y: x / 2, w: 70, h: 12 }));
    const placed = moved(boxes, resolveLabelOffsets(boxes));
    for (let i = 0; i < placed.length; i++) for (let j = i + 1; j < placed.length; j++) expect(overlaps(placed[i], placed[j])).toBe(false);
  });
});
