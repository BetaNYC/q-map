<script lang="ts">
  import * as maplibregl from 'maplibre-gl';
  import 'maplibre-gl/dist/maplibre-gl.css';
  import { goto } from '$app/navigation';
  import { base } from '$app/paths';
  import { dataUrl } from '$lib/data';
  import { BASEMAP_STYLE } from '$lib/map/basemap';
  import { configureMapWorker } from '$lib/map/worker';
  import type { DistrictIndexEntry } from '$lib/types';
  import CdtaCard from './CdtaCard.svelte';

  /**
   * The entry screen's map picker, in the "Select on map" panel. Figma:
   * MapPlaceholder, node 86:1956 — 358x350. Interactive since frontend cycle 2,
   * step 5 (Andrew's spec, 2026-10-01 — described rather than drawn):
   *
   *   - THE FIRST TAP SELECTS, THE SECOND GOES. On a phone-sized map a first
   *     tap that leaves the page is a mis-tap waiting to happen. The selected
   *     district gets a heavier outline and its CdtaCard appears below the
   *     map; tapping the same district again navigates to it, and so does the
   *     card. Tapping another district moves the selection; tapping outside
   *     Queens clears it.
   *   - TWO FINGERS TO PAN AND ZOOM (`cooperativeGestures`), so a one-finger
   *     swipe still scrolls the page; MapLibre's default overlay explains it.
   *     +/− buttons for anyone who cannot pinch. Zoomed out no further than all
   *     of Queens, and kept near it.
   *   - IF THE MAP CANNOT BE DRAWN (no WebGL2 — maplibre 6 throws at
   *     construction), the 358x350 space says so on grey/100 and points at the
   *     list. Before cycle 2 this was an uncaught error and a blank box.
   *
   * CARTO POSITRON, the same basemap as the district map — streets are what let
   * you recognise where you live. Fills are therefore translucent: a click
   * target and a tint, not a cover.
   *
   * LABELS ARE HTML MARKERS, NOT A SYMBOL LAYER: a symbol layer needs fonts
   * from a glyph CDN, and every other label in the app is AUTHENTIC Sans Pro.
   * The cost is doing collision detection by hand — now on every zoom. Labels
   * also grow as the map zooms in (LABEL below), so more names fit and they
   * become readable as the districts get larger.
   *
   * THE CARDS ARE STILL THE ACCESSIBLE PICKER. The canvas is tabindex="-1";
   * the other panel holds the same fourteen destinations as real links. The
   * zoom buttons are focusable, which is harmless.
   *
   * The container is NOT aria-hidden: the attribution and zoom controls put
   * focusable elements inside it (axe `aria-hidden-focus`).
   */

  interface Props {
    /** All 59; the Queens 14 are filtered out here. */
    districts: DistrictIndexEntry[];
  }

  let { districts }: Props = $props();

  const queens = $derived(districts.filter((d) => d.boro === 'Queens'));

  let container = $state<HTMLDivElement>();
  let selectedSlug = $state<string | null>(null);
  let unavailable = $state(false);

  const selected = $derived(queens.find((d) => d.slug === selectedSlug) ?? null);

  /** Andrew's spec: the selected outline in #3258a3 at 90%. 3px so it reads
   *  against the 1px outline every district already has. */
  const SELECTED_LINE = { color: '#3258a3', opacity: 0.9, width: 3 };

  /** Labels grow with the map: 7px at the opening view of Queens, x1.35 per
   *  zoom level in, capped at 12px (body/small) - so names get readable as
   *  districts get larger, without ever outgrowing the app's own small type. */
  const LABEL = { basePx: 7, growth: 1.35, maxPx: 12 };

  /** The union of the 14 district bboxes. */
  function queensBounds(entries: DistrictIndexEntry[]): [[number, number], [number, number]] {
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

    configureMapWorker();

    const bounds = queensBounds(queens);
    // Panning stops a little beyond Queens, so the map cannot be lost.
    const [[w, s], [e, n]] = bounds;
    const padX = (e - w) * 0.25;
    const padY = (n - s) * 0.25;

    let map: maplibregl.Map;
    try {
      map = new maplibregl.Map({
        container,
        style: BASEMAP_STYLE,
        bounds,
        fitBoundsOptions: { padding: 12, animate: false },
        maxBounds: [
          [w - padX, s - padY],
          [e + padX, n + padY]
        ],
        maxZoom: 15,
        cooperativeGestures: true,
        dragRotate: false,
        pitchWithRotate: false,
        keyboard: false,
        attributionControl: { compact: true }
      });
    } catch {
      // maplibre 6 throws GPUInitializationError without WebGL2.
      unavailable = true;
      return;
    }

    map.touchZoomRotate.disableRotation();
    map.addControl(new maplibregl.NavigationControl({ showCompass: false }), 'top-right');
    // MapLibre gives its canvas tabindex="0"; the cards are the keyboard route.
    map.getCanvas().setAttribute('tabindex', '-1');

    const markers: maplibregl.Marker[] = [];

    /**
     * Show as many labels as fit at this zoom: largest district first, so when
     * two compete the one with more room survives; a clashing label is hidden,
     * not removed — its district is still tappable, and the card names it.
     */
    const layoutLabels = () => {
      for (const m of markers) m.getElement().style.display = '';
      requestAnimationFrame(() => {
        const placed: DOMRect[] = [];
        const PAD = 1;
        for (const marker of markers) {
          const el = marker.getElement();
          const r = el.getBoundingClientRect();
          const clash = placed.some(
            (q) => r.left < q.right + PAD && r.right > q.left - PAD && r.top < q.bottom + PAD && r.bottom > q.top - PAD
          );
          if (clash) el.style.display = 'none';
          else placed.push(r);
        }
      });
    };

    map.on('load', () => {
      // Not zoomable out past the Queens view it opened on.
      const baseZoom = map.getZoom();
      map.setMinZoom(baseZoom);

      const scaleLabels = () => {
        const px = Math.min(LABEL.maxPx, LABEL.basePx * LABEL.growth ** (map.getZoom() - baseZoom));
        container!.style.setProperty('--picker-label-size', `${px.toFixed(2)}px`);
      };
      scaleLabels();
      map.on('zoom', scaleLabels);

      map.addSource('cdta', { type: 'geojson', data: dataUrl('cdta.geojson'), promoteId: 'cdta2020' });

      const queensIds = queens.map((d) => d.cdta2020);
      const inQueens: maplibregl.FilterSpecification = ['in', ['get', 'cdta2020'], ['literal', queensIds]];

      map.addLayer({
        id: 'queens-fill',
        type: 'fill',
        source: 'cdta',
        filter: inQueens,
        paint: { 'fill-color': '#3258a3', 'fill-opacity': 0.1 }
      });
      map.addLayer({
        id: 'queens-line',
        type: 'line',
        source: 'cdta',
        filter: inQueens,
        paint: { 'line-color': '#3258a3', 'line-width': 1 }
      });
      map.addLayer({
        id: 'queens-selected',
        type: 'line',
        source: 'cdta',
        filter: ['==', ['get', 'slug'], ''],
        paint: {
          'line-color': SELECTED_LINE.color,
          'line-opacity': SELECTED_LINE.opacity,
          'line-width': SELECTED_LINE.width
        }
      });

      map.on('click', (e) => {
        const hit = map.queryRenderedFeatures(e.point, { layers: ['queens-fill'] })[0];
        const slug = typeof hit?.properties?.slug === 'string' ? hit.properties.slug : null;
        // A second tap on the selected district goes there.
        if (slug && slug === selectedSlug) {
          goto(`${base}/${slug}`);
          return;
        }
        selectedSlug = slug;
      });
      map.on('mouseenter', 'queens-fill', () => (map.getCanvas().style.cursor = 'pointer'));
      map.on('mouseleave', 'queens-fill', () => (map.getCanvas().style.cursor = ''));

      const byArea = [...queens].sort((a, b) => {
        const area = (d: DistrictIndexEntry) => (d.bbox[2] - d.bbox[0]) * (d.bbox[3] - d.bbox[1]);
        return area(b) - area(a);
      });
      for (const d of byArea) {
        const el = document.createElement('span');
        el.className = 'picker-label';
        el.textContent = d.display_name;
        // point_on_surface, not a centroid: QN14's centroid is in Jamaica Bay (§2).
        markers.push(new maplibregl.Marker({ element: el }).setLngLat(d.point_on_surface).addTo(map));
      }
      layoutLabels();
      map.on('zoomend', layoutLabels);
    });

    map.on('load', () => (mapRef = map));

    /* Attribution collapsed to its (i) button from the start (Andrew,
       2026-10-01). Compact mode opens it expanded and collapses it only on the
       first drag - by removing this class, which is all this does. Once the
       map is idle, so the credits have been written in and will not reopen it.
       Tapping (i) still shows them. */
    map.once('idle', () => {
      container?.querySelector('.maplibregl-ctrl-attrib')?.classList.remove('maplibregl-compact-show');
    });

    return () => {
      mapRef = undefined;
      for (const m of markers) m.remove();
      map.remove();
    };
  });

  /** Set once the style and layers exist; the highlight effect needs both. */
  let mapRef = $state<maplibregl.Map>();

  // The selection drives the highlight outline.
  $effect(() => {
    mapRef?.setFilter('queens-selected', ['==', ['get', 'slug'], selectedSlug ?? '']);
  });
</script>

{#if unavailable}
  <div class="picker unavailable" role="note">
    <p>This map can't be shown on this device. Choose a district from the list.</p>
  </div>
{:else}
  <!-- A shortcut to the fourteen cards in the other panel, which are the accessible picker. -->
  <div class="picker" bind:this={container}></div>
{/if}

<!-- The selected district's card - the same card as in the list, and the link. -->
<div class="selection" aria-live="polite">
  {#if selected}
    <CdtaCard district={selected} />
  {/if}
</div>

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

  /* Andrew's spec: the message in the space the map would take, on grey/100.
     Primary text: secondary grey is 4.0:1 on grey/100, under AA. */
  .unavailable {
    display: flex;
    align-items: center;
    justify-content: center;
    padding: var(--space-400);
    box-sizing: border-box;
    background: var(--color-surface-muted);
  }

  .unavailable p {
    margin: 0;
    max-width: 24ch;
    text-align: center;
    font-size: var(--font-size-body);
    line-height: var(--line-height-prose);
  }

  .selection:not(:empty) {
    padding-top: var(--space-300);
  }

  /* Marker elements are created imperatively and live outside this
     component's scoped markup, so the rule has to be global. */
  .picker :global(.picker-label) {
    font-family: var(--font-sans);
    font-size: var(--picker-label-size, 7px);
    line-height: var(--line-height-tight);
    color: var(--color-text-primary);
    text-align: center;
    white-space: nowrap;
    pointer-events: none;
    /* A halo: the labels sit over fills, boundaries and streets. */
    -webkit-text-stroke: 0.4em #fefcfa;
    paint-order: stroke fill;
    text-shadow:
      0 0 2px #fefcfa;
  }
</style>
 