import { describe, expect, it } from 'vitest';
import { pointScale, pointSizePx } from './pointScale';

describe('point size: d26 ramp from a 20px base', () => {
  it.each([
    [10, 1, 20],
    [15, 1, 20],
    [17.5, 1.375, 27.5],
    [20, 1.75, 35],
    [22, 1.75, 35]
  ])('zoom %s -> x%s, %spx', (zoom, scale, px) => {
    expect(pointScale(zoom)).toBeCloseTo(scale, 10);
    expect(pointSizePx(zoom)).toBeCloseTo(px, 10);
  });
});
