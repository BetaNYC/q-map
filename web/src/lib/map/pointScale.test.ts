import { describe, expect, it } from 'vitest';
import { pointScale } from './pointScale';

describe('pointScale: d26 ramp', () => {
  it.each([
    [10, 1],
    [15, 1],
    [17.5, 1.375],
    [20, 1.75],
    [22, 1.75]
  ])('zoom %s -> %s', (zoom, scale) => expect(pointScale(zoom)).toBeCloseTo(scale, 10));
});
