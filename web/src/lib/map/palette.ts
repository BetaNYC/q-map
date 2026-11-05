import type { ExpressionSpecification } from 'maplibre-gl';

/**
 * WORKED EXAMPLE — the map overlays' colours, and the one place they live.
 *
 * MapLibre paint is evaluated in a canvas and cannot read a CSS custom
 * property, so these cannot be tokens in tokens.css. They are the next best
 * thing: hex constants named after their Figma variables, so a `grep` for
 * `color/blue/600` finds both the CSS token and the map paint. The map's
 * paint expressions AND the Layers tab's swatches read from here, so the key
 * is always the colour on the map.
 *
 * THE PALETTE ("H1", Andrew, 2026-11-05; METHODOLOGY.md, *The flood-layer
 * palette, and stormwater tiles merged*). Every ramp shares color/blue's
 * lightness at every step. teal, violet and magenta are not in Figma yet:
 * they were made from color/blue (its lightness and chroma per step, hue
 * rotated to 195, 300 and 345) and are to be added as primitives. Until they
 * are, this file is their source.
 *
 * Steps run 300-700 for the graded layers: at 200 every hue is near-white and
 * the lightest class of two layers looked identical; at 800 and above the warm
 * ramps turn brown.
 */

/** Figma primitives the map uses, by their Figma variable name. */
export const PRIMITIVE = {
  'color/blue/200': '#cedef0',
  'color/blue/600': '#3f6bb9',
  'color/off-white/primary': '#fefcfa',

  'color/grey/200': '#d7dce4',
  'color/grey/300': '#b6bbc2',
  'color/grey/400': '#91979f',
  'color/grey/500': '#7a818a',
  'color/grey/600': '#686e76',
  'color/grey/700': '#575c62',

  // Not yet in Figma - derived from color/blue (see above).
  'color/magenta/300': '#dda8c5',
  'color/magenta/400': '#c77aa6',
  'color/magenta/500': '#b55e91',
  'color/magenta/600': '#a1497f',
  'color/magenta/700': '#8c386c',

  'color/teal/300': '#80c9c9',
  'color/teal/400': '#16acac',
  'color/teal/500': '#0c9293',
  'color/teal/600': '#077d7d',
  'color/teal/700': '#00696a',

  'color/violet/300': '#c1b0e3',
  'color/violet/500': '#8c6cc1',
  'color/violet/700': '#684798'
} as const;

/**
 * A graded layer: the property it is styled on, and its classes from lowest
 * to highest, each with the colour it draws. Lowest-to-highest is also the
 * legend's order.
 */
export interface Ramp {
  /** The feature property the colour is read from (DATA_CONTRACT.md §8). */
  property: string;
  classes: ReadonlyArray<{ value: number | string; color: string }>;
}

/**
 * Present-day storm surge: the Flood Vulnerability Index's `ss_cur`, 1-5,
 * ranked among exposed tracts only. A tract absent from the file is not
 * exposed, so there is no class for "none".
 */
export const SURGE: Ramp = {
  property: 'ss_cur',
  classes: [
    { value: 1, color: PRIMITIVE['color/magenta/300'] },
    { value: 2, color: PRIMITIVE['color/magenta/400'] },
    { value: 3, color: PRIMITIVE['color/magenta/500'] },
    { value: 4, color: PRIMITIVE['color/magenta/600'] },
    { value: 5, color: PRIMITIVE['color/magenta/700'] }
  ]
};

/**
 * Tidal flooding in the 2020s: the FVI's `tid_20s`, 1-5, read exactly as
 * surge. Teal, so it is never mistaken for surge where the two meet.
 */
export const TIDAL: Ramp = {
  property: 'tid_20s',
  classes: [
    { value: 1, color: PRIMITIVE['color/teal/300'] },
    { value: 2, color: PRIMITIVE['color/teal/400'] },
    { value: 3, color: PRIMITIVE['color/teal/500'] },
    { value: 4, color: PRIMITIVE['color/teal/600'] },
    { value: 5, color: PRIMITIVE['color/teal/700'] }
  ]
};

/**
 * FEMA flood zones, NYC's 2007 effective map: `zone`, least to most severe.
 * Three classes over a two-step spacing (300, 500, 700) so each is clearly
 * apart.
 */
export const FEMA: Ramp = {
  property: 'zone',
  classes: [
    { value: '0.2PCT', color: PRIMITIVE['color/violet/300'] },
    { value: 'AE', color: PRIMITIVE['color/violet/500'] },
    { value: 'VE', color: PRIMITIVE['color/violet/700'] }
  ]
};

/**
 * Hurricane evacuation zones: `zone` 1-6, where zone 1 evacuates first. Listed
 * 6 to 1 so the ramp still runs lowest to highest risk, and zone 1 is darkest.
 * Grey (Andrew, 2026-11-05): planning context, not a hazard intensity. Drawn
 * at EVAC_OPACITY, because zone 1 covers almost all of the Rockaways and a
 * full-strength grey would fill the district.
 */
export const EVAC: Ramp = {
  property: 'zone',
  classes: [
    { value: 6, color: PRIMITIVE['color/grey/200'] },
    { value: 5, color: PRIMITIVE['color/grey/300'] },
    { value: 4, color: PRIMITIVE['color/grey/400'] },
    { value: 3, color: PRIMITIVE['color/grey/500'] },
    { value: 2, color: PRIMITIVE['color/grey/600'] },
    { value: 1, color: PRIMITIVE['color/grey/700'] }
  ]
};
export const EVAC_OPACITY = 0.55;

/**
 * Stormwater, unchanged since 2026-10-08 apart from the outline: moderate rain
 * blue/600 at 65%, limited rain blue/200 at 90% on top of it.
 *
 * The outline (2026-11-05) is what keeps moderate visible above the graded
 * layers. Over magenta, teal and violet 500-700, blue/600 at 65% fell to
 * 1.0-1.2:1 - one family, one lightness. The off-white outline holds it at
 * 2.9-5.0:1 over every class. It is only possible since the tiles were
 * re-cut with the two depth categories merged (data-v6); before, every
 * boundary between them drew as a line inside the shape.
 */
export const STORMWATER = {
  moderate: { color: PRIMITIVE['color/blue/600'], opacity: 0.65 },
  limited: { color: PRIMITIVE['color/blue/200'], opacity: 0.9 },
  outline: { color: PRIMITIVE['color/off-white/primary'], width: 1 }
} as const;

/**
 * A MapLibre `match` expression for a ramp. A value outside the ramp draws
 * transparent rather than in a fallback colour: an unexpected index must not
 * pass for a real class on the map. The pipeline asserts the domain, so this
 * is the belt to its braces.
 */
export function rampExpression(ramp: Ramp) {
  return [
    'match',
    ['get', ramp.property],
    ...ramp.classes.flatMap((c) => [c.value, c.color]),
    'rgba(0, 0, 0, 0)'
  ] as unknown as ExpressionSpecification;
}

/**
 * The Layers tab's flat swatch for a graded layer: its darkest class (Andrew,
 * 2026-11-05). A placeholder until the legend Andrew is designing replaces it.
 */
export const darkest = (ramp: Ramp): string => ramp.classes[ramp.classes.length - 1].color;

/**
 * The Layers tab's swatch per layer: the colour the map draws, or for a graded
 * layer its darkest class (a placeholder until Andrew's legend lands). The map
 * paint reads the same constants, so the key cannot drift from the map.
 */
export const LAYER_SWATCH: Record<string, string> = {
  stormwater_limited_1_77: STORMWATER.limited.color,
  stormwater_moderate_2_13: STORMWATER.moderate.color,
  tidal_2020s: darkest(TIDAL),
  surge_current: darkest(SURGE),
  fema_flood_zones: darkest(FEMA),
  hurricane_evac_zones: darkest(EVAC)
};
