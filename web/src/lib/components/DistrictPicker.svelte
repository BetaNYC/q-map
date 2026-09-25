<script lang="ts">
  import maplibregl from 'maplibre-gl';
  import 'maplibre-gl/dist/maplibre-gl.css';
  import { goto } from '$app/navigation';
  import { base } from '$app/paths';
  import { dataUrl } from '$lib/data';
  import { BASEMAP_STYLE } from '$lib/map/basemap';
  import type { DistrictIndexEntry } from '$lib/types';

  /**
   * The entry screen's map picker. Figma: MapPlaceholder, node 86:1956 —
   * 358x350, Queens' districts outlined on a plain ground.
   *
   * CARTO POSITRON, the same basemap as the district map — one style constant
   * for both, in $lib/map/basemap. The frame draws district outlines on a
   * plain ground with no streets, but streets are what let you recognise where
   * you live, which is the whole job of a picker.
   *
   * The fills are therefore TRANSLUCENT. An opaque district fill over a street
   * basemap hides the thing the basemap was added for; the fill is here to
   * give the polygon a click target and a tint, not to cover the map.
   *
   * LABELS ARE HTML MARKERS, NOT A SYMBOL LAYER. Positron's style does supply
   * a `glyphs` URL, so a symbol layer with free collision detection is now
   * available — but its fonts are Open Sans and Noto, and every other label in
   * this app is AUTHENTIC Sans Pro. DOM markers keep the typography
   * consistent; the cost is doing collision detection by hand, below.
   *
   * They also need a join: `cdta.geojson` carries only `cdta2020` and `slug`
   * (§9), so the names come from districts.json — which the entry screen has
   * already loaded for the cards.
   *
   * THE MAP IS A SHORTCUT, THE CARDS ARE THE PICKER. The same fourteen
   * destinations sit immediately below as real links, and the canvas is
   * `tabindex="-1"` so a keyboard user is not stranded on a target they
   * cannot operate — the cards are the route.
   *
   * The container is NOT `aria-hidden`. It was, which is the tidier statement
   * about a decorative map, but the attribution control puts focusable links
   * inside it and `aria-hidden` around a focusable element is an axe
   * `aria-hidden-focus` violation — a keyboard user tabbing into something a
   * screen reader is told does not exist. A canvas with no fallback content
   * is already invisible to assistive technology, so leaving the container
   * plain costs nothing and keeps the attribution reachable.
   *
   * PAN AND ZOOM ARE OFF. A 350px map inside a scrolling page competes for
   * every vertical swipe — MapLibre sets `touch-action: none` on its canvas,
   * so a drag pans the map instead of scrolling the page. The frame is a fixed
   * view of Queens, so this is one too. Clicks still fire.
   */

  interface Props {
    /** All 59; the Queens 14 are filtered out here. */
    districts: DistrictIndexEntry[];
  }

  let { districts }: Props = $props();

  const queens = $derived(districts.filter((d) => d.boro === 'Queens'));

  let container = $state<HTMLDivElement>();

  /** The union of the 14 district bboxes — the frame's extent. */
  function queensBounds(entries: DistrictIndexEntry[]): maplibregl.LngLatBoundsLike {
    const b = entries.reduce(
      (acc, d) => [
        Math.min(acc[0], d.bbox[0]),
        Math.min(acc[1], d.bbox[1]),
        Math.max(acc[2], d.bbox[2]),
        Math.max(acc[3], d.bbox[3])
      ],
      [180, 90, -180, -90]
    );
    return [
      [b[0], b[1]],
      [b[2], b[3]]
    ];
  }

  $effect(() => {
    if (!container || queens.length === 0) return;

    const map = new maplibregl.Map({
      container,
      style: BASEMAP_STYLE,
      bounds: queensBounds(queens),
      fitBoundsOptions: { padding: 12, animate: false },
      // See the note above: a picker, not a map to explore.
      scrollZoom: false,
      dragPan: false,
      dragRotate: false,
      touchZoomRotate: false,
      keyboard: false,
      doubleClickZoom: false,
      // MapLibre's built-in control, as on the district map. Required by both
      // CARTO and OpenStreetMap; compact keeps it to an "i" until tapped.
      attributionControl: { compact: true }
    });

    // MapLibre gives its canvas tabindex="0". Inside an aria-hidden subtree
    // that would be a focusable element a screen reader cannot describe.
    map.getCanvas().setAttribute('tabindex', '-1');

    const markers: maplibregl.Marker[] = [];

    map.on('load', () => {
      map.addSource('cdta', {
        type: 'geojson',
        data: dataUrl('cdta.geojson'),
        promoteId: 'cdta2020'
      });

      const queensIds = queens.map((d) => d.cdta2020);

      // No layer for the other 45: Positron already draws the rest of the
      // city, so Queens reads by being the tinted part rather than by the
      // others being drawn differently.
      map.addLayer({
        id: 'queens-fill',
        type: 'fill',
        source: 'cdta',
        filter: ['in', ['get', 'cdta2020'], ['literal', queensIds]],
        // Translucent: the fill is a click target and a tint, not a cover.
        paint: { 'fill-color': '#3258a3', 'fill-opacity': 0.1 }
      });

      map.addLayer({
        id: 'queens-line',
        type: 'line',
        source: 'cdta',
        filter: ['in', ['get', 'cdta2020'], ['literal', queensIds]],
        paint: { 'line-color': '#3258a3', 'line-width': 1 }
      });

      map.on('click', 'queens-fill', (e) => {
        const slug = e.features?.[0]?.properties?.slug;
        if (typeof slug === 'string') goto(`${base}/${slug}`);
      });

      map.on('mouseenter', 'queens-fill', () => {
        map.getCanvas().style.cursor = 'pointer';
      });
      map.on('mouseleave', 'queens-fill', () => {
        map.getCanvas().style.cursor = '';
      });

      /**
       * Labels, placed largest district first and skipped where they would
       * collide.
       *
       * A MapLibre symbol layer would do this for free — collision detection
       * is the main thing symbol layers are for — but it needs a `glyphs` URL
       * and that means fetching a font from a CDN. Doing it by hand here is
       * the price of the map having no third-party dependency at all.
       *
       * Largest first so that when two labels compete, the one with more room
       * around it survives. The alternative — hiding by list order — drops
       * labels arbitrarily.
       *
       * The map is static (pan and zoom are off), so positions are fixed and
       * this runs once rather than on every frame.
       *
       * point_on_surface, not a centroid: guaranteed inside the polygon.
       * QN14's true centroid falls in Jamaica Bay (§2).
       */
      const byArea = [...queens].sort((a, b) => {
        const area = (d: DistrictIndexEntry) =>
          (d.bbox[2] - d.bbox[0]) * (d.bbox[3] - d.bbox[1]);
        return area(b) - area(a);
      });

      for (const d of byArea) {
        const el = document.createElement('span');
        el.className = 'picker-label';
        el.textContent = d.display_name;
        markers.push(
          new maplibregl.Marker({ element: el }).setLngLat(d.point_on_surface).addTo(map)
        );
      }

      // Measure after a frame, so the markers have been laid out.
      requestAnimationFrame(() => {
        const placed: DOMRect[] = [];
        const PAD = 1;

        for (const marker of markers) {
          const el = marker.getElement();
          const r = el.getBoundingClientRect();
          const clash = placed.some(
            (q) =>
              r.left < q.right + PAD &&
              r.right > q.left - PAD &&
              r.top < q.bottom + PAD &&
              r.bottom > q.top - PAD
          );

          if (clash) {
            // Hidden, not removed: the district is still tappable, and the
            // card below carries its name. A half-legible pile of overlapping
            // text is worse than fewer labels.
            el.style.display = 'none';
          } else {
            placed.push(r);
          }
        }
      });
    });

    return () => {
      for (const m of markers) m.remove();
      map.remove();
    };
  });
</script>

<!-- A shortcut to the fourteen cards below, which are the accessible picker. -->
<div class="picker" bind:this={container}></div>

<style>
  .picker {
    width: 100%;
    /* 358x350 in the frame — an aspect ratio rather than a fixed height, so it
       holds at the widths above the 390px baseline. */
    aspect-ratio: 358 / 350;
    border-radius: 3px;
    overflow: hidden;
    background: var(--color-surface-sunken);
  }

  /* Marker elements are created imperatively and live outside this
     component's scoped markup, so the rule has to be global. */
  .picker :global(.picker-label) {
    font-family: var(--font-sans);
    font-size: 7px;
    line-height: var(--line-height-tight);
    color: var(--color-text-primary);
    text-align: center;
    white-space: nowrap;
    pointer-events: none;
    /* The labels sit over the fills, and several districts are narrow. A halo
       keeps them readable where a boundary runs underneath. */
    /* A halo, now over streets rather than a flat ground — the basemap gives
       the labels much more to compete with. */
    text-shadow:
      0 0 2px #fefcfa,
      0 0 2px #fefcfa,
      0 0 3px #fefcfa;
  }
</style>
