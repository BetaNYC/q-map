<script lang="ts">
  import * as maplibregl from 'maplibre-gl';
  import 'maplibre-gl/dist/maplibre-gl.css';
  import { dataUrl } from '$lib/data';
  import { BASEMAP_STYLE, INITIAL_CENTER, INITIAL_ZOOM } from '$lib/map/basemap';
  import type { GeoJSONSource } from 'maplibre-gl';
  import { overlaySpecs } from '$lib/map/overlays';
  import { registerMapProtocols } from '$lib/map/protocols';
  import { configureMapWorker } from '$lib/map/worker';
  import type { MapDistrict } from '$lib/mapView';

  /**
   * The district map. Step 8: the basemap, the PMTiles protocol, the district
   * outline, and the overlays driven by `?layers=`.
   *
   * The resource points, the popup and the bottom sheet are step 9.
   *
   * WHY EVERYTHING IS SET UP ONCE AND MUTATED AFTER. MapLibre owns its own
   * canvas and its own state; re-creating the map when a toggle changes would
   * throw away the user's pan and zoom. So the map is built on mount, and the
   * $effect below only flips `visibility` on layers that already exist. Adding
   * and removing sources per toggle would also re-download the PMTiles archive
   * every time — 5.9 MB for the moderate stormwater layer.
   *
   * The same rule is what lets one map serve the docked desktop layout, where
   * it lives in the root layout and outlasts the page beside it. `district`
   * can change under a mounted map, so the district outline, the fit and the
   * resource points are effects below, not one-off steps in `load`.
   *
   * `district` null is the Queens overview the docked map shows on pages not
   * about one district (entry, alerts, 404). It is drawn as the phone's entry
   * picker draws Queens (Andrew, 2026-10-07): each district filled #3258a3 at
   * 10% with a 1px outline, and named. Fitted to `overviewBbox`.
   */

  interface Props {
    /** null: all of Queens (the docked map's overview). */
    district: MapDistrict | null;
    /** Fitted to when `district` is null. [xmin, ymin, xmax, ymax]. */
    overviewBbox?: MapDistrict['bbox'];
    /** `layer_id`s currently on, from `?layers=`. */
    visibleLayers: string[];
    /** Category slugs currently on, from `?categories=`. null means all. */
    visibleCategories: string[] | null;
    /** Fired when a resource point is tapped — the page writes `?resource=`. */
    onSelectResource?: (resourceId: string) => void;
    /**
     * Fired when another district is clicked, with its slug. Absent, the
     * other districts are not clickable at all: no hit layer is hit-tested
     * and no pointer cursor shows.
     */
    onSelectDistrict?: (slug: string) => void;
    /** cdta2020 ids that have pages (the Queens 14). Only these are clickable,
     *  and in the overview these are the districts outlined. */
    selectableDistricts?: string[];
    /** The districts named on the overview, at their `point_on_surface`. */
    overviewDistricts?: MapDistrict[];
  }

  let {
    district,
    overviewBbox,
    visibleLayers,
    visibleCategories,
    onSelectResource,
    onSelectDistrict,
    selectableDistricts = [],
    overviewDistricts = []
  }: Props = $props();

  /** The resource points layer id, used by the filter effect and the click
   *  handler. `layers/resources/<slug>.geojson` carries only resource_id,
   *  name, category, source and is_coad_member — the popup's address and
   *  operator come from the join the page does (§7.4). */
  const RESOURCE_LAYER = 'resource-points';

  /** Invisible fill over the other clickable districts. A line layer is only
   *  hit on its 0.75px stroke, so clicking inside a district needs a fill. */
  const DISTRICT_HIT_LAYER = 'cdta-hit';

  /** Matches no feature: the starting filter for layers whose real filter
   *  depends on `district`, which the effects below set. */
  const NOTHING: maplibregl.FilterSpecification = ['==', ['get', 'cdta2020'], ''];

  const EMPTY: GeoJSON.FeatureCollection = { type: 'FeatureCollection', features: [] };

  let container = $state<HTMLDivElement>();
  let map: maplibregl.Map | undefined;
  let styleReady = $state(false);

  const specs = overlaySpecs();

  $effect(() => {
    if (!container) return;

    configureMapWorker();
    registerMapProtocols();

    const instance = new maplibregl.Map({
      container,
      style: BASEMAP_STYLE,
      center: INITIAL_CENTER,
      zoom: INITIAL_ZOOM,
      // The overlays are the content; tilting and spinning them adds nothing
      // and makes a one-handed phone gesture ambiguous.
      pitchWithRotate: false,
      dragRotate: false,
      touchZoomRotate: true,
      attributionControl: { compact: true }
    });

    instance.touchZoomRotate.disableRotation();

    instance.addControl(new maplibregl.NavigationControl({ showCompass: false }), 'top-right');

    instance.on('load', () => {
      // cdta.geojson carries `cdta2020` and `slug` only; everything else joins
      // client-side. promoteId makes cdta2020 the feature id so setFeatureState
      // can push attributes later without a per-feature lookup (§9).
      instance.addSource('cdta', {
        type: 'geojson',
        data: dataUrl('cdta.geojson'),
        promoteId: 'cdta2020'
      });

      // Every district except this one, dimmed — context for where you are
      // without competing with the overlays.
      instance.addLayer({
        id: 'cdta-others',
        type: 'line',
        source: 'cdta',
        filter: NOTHING,
        paint: { 'line-color': '#d7dce4', 'line-width': 0.75 }
      });

      // The overview's district fill: DistrictPicker's queens-fill exactly.
      // Only Queens, only on the overview; the district effect sets the filter.
      instance.addLayer({
        id: 'queens-fill',
        type: 'fill',
        source: 'cdta',
        filter: NOTHING,
        paint: { 'fill-color': '#3258a3', 'fill-opacity': 0.1 }
      });

      // Opacity 0, not visibility none: a hidden layer is not hit-tested, a
      // transparent one is. Below the overlays so it never tints them.
      instance.addLayer({
        id: DISTRICT_HIT_LAYER,
        type: 'fill',
        source: 'cdta',
        filter: NOTHING,
        paint: { 'fill-color': '#000000', 'fill-opacity': 0 }
      });

      instance.on('click', DISTRICT_HIT_LAYER, (e) => {
        const slug = e.features?.[0]?.properties?.slug;
        if (typeof slug === 'string') onSelectDistrict?.(slug);
      });

      // Overlays go in BEFORE the district outline so the outline stays legible
      // on top of a translucent flood polygon.
      for (const spec of Object.values(specs)) {
        instance.addSource(spec.sourceId, spec.source);
        for (const layer of spec.layers) {
          // Added hidden. The $effect below is the single place that decides
          // what is on, so the initial state and a later toggle take the same
          // code path.
          instance.addLayer({ ...layer, layout: { visibility: 'none' } });
        }
      }

      // Per-district resource points — 178 KB at the largest, against 1.19 MB
      // for one Queens-wide file. A district map needs only its own. Starts
      // empty; the effect below says which file, if any, to load.
      instance.addSource('resources', { type: 'geojson', data: EMPTY });

      instance.addLayer({
        id: RESOURCE_LAYER,
        type: 'circle',
        source: 'resources',
        paint: {
          'circle-radius': ['interpolate', ['linear'], ['zoom'], 11, 3, 16, 7],
          'circle-color': '#3258a3',
          'circle-stroke-width': 1,
          'circle-stroke-color': '#fefcfa'
        }
      });

      instance.on('click', RESOURCE_LAYER, (e) => {
        const id = e.features?.[0]?.properties?.resource_id;
        if (typeof id === 'string') onSelectResource?.(id);
      });

      // A point is a 6px circle; the cursor is the only affordance on a
      // pointer device that it can be tapped at all. The same goes for a
      // district you can click through to.
      for (const layerId of [RESOURCE_LAYER, DISTRICT_HIT_LAYER]) {
        instance.on('mouseenter', layerId, () => {
          instance.getCanvas().style.cursor = 'pointer';
        });
        instance.on('mouseleave', layerId, () => {
          instance.getCanvas().style.cursor = '';
        });
      }

      instance.addLayer({
        id: 'cdta-current',
        type: 'line',
        source: 'cdta',
        filter: NOTHING,
        // #3258a3 (color/blue/700), matching the entry map's district outlines
        // (Andrew, 2026-10-01). Was #0a0a0a.
        paint: { 'line-color': '#3258a3', 'line-width': 2 }
      });

      // A drag, wheel or keyboard pan carries an originalEvent; fitBounds
      // does not. After the reader moves the map, a resize leaves it alone.
      instance.on('movestart', (e) => {
        if (e.originalEvent) userMoved = true;
      });

      instance.on('zoom', scaleLabels);
      instance.on('zoomend', layoutLabels);

      map = instance;
      styleReady = true;
    });

    /**
     * Refit when the container changes size and the reader has not moved the
     * map since the last fit. On desktop the toolbar under the map arrives
     * once the district's categories load, usually after the first fit, and
     * shortens the map by about 180px. MapLibre resizes the canvas itself but
     * keeps the centre and zoom, which would leave the district's edges under
     * the toolbar.
     */
    const observer = new ResizeObserver(() => {
      if (!map || !lastBounds || userMoved) return;
      map.resize();
      map.fitBounds(lastBounds, { padding: 24, animate: false });
    });
    observer.observe(container);

    return () => {
      observer.disconnect();
      styleReady = false;
      map = undefined;
      fitted = null;
      lastBounds = null;
      labels = [];
      instance.remove();
    };
  });

  let userMoved = false;
  let lastBounds: maplibregl.LngLatBoundsLike | null = null;

  /** What the map was last fitted to: a slug, or '' for the overview. null
   *  until the first fit, which is instant; every later one animates, so a
   *  click-through reads as a move across Queens rather than a cut. */
  let fitted: string | null = null;

  /**
   * Point the map at `district`: outline it, dim the rest, and fit to it.
   * Or, with no district, outline all of Queens and fit to that.
   *
   * Runs on load and again whenever the district changes under a mounted map
   * — a click-through on the docked map, or /q14/map to /q12/map, where
   * SvelteKit reuses the page component and only the props change.
   */
  $effect(() => {
    const current = district ? [district.cdta2020] : selectableDistricts;
    const key = district?.slug ?? '';
    const bbox = district?.bbox ?? overviewBbox;
    const clickable = onSelectDistrict
      ? selectableDistricts.filter((id) => id !== district?.cdta2020)
      : [];
    if (!styleReady || !map) return;

    const isCurrent: maplibregl.ExpressionSpecification = [
      'in',
      ['get', 'cdta2020'],
      ['literal', current]
    ];
    map.setFilter('cdta-current', isCurrent);
    map.setFilter('cdta-others', ['!', isCurrent]);
    // Overview: the picker's 10% fill and 1px outline. A district: no fill,
    // and the 2px outline that marks "you are here".
    map.setFilter('queens-fill', district ? NOTHING : isCurrent);
    map.setPaintProperty('cdta-current', 'line-width', district ? 2 : 1);
    map.setFilter(DISTRICT_HIT_LAYER, ['in', ['get', 'cdta2020'], ['literal', clickable]]);

    if (fitted === key || !bbox) return;

    const reduceMotion = matchMedia('(prefers-reduced-motion: reduce)').matches;

    // bbox is [xmin, ymin, xmax, ymax] in EPSG:4326, straight from
    // districts.json — no need to compute it from the geometry.
    lastBounds = [
      [bbox[0], bbox[1]],
      [bbox[2], bbox[3]]
    ];
    map.fitBounds(lastBounds, { padding: 24, animate: fitted !== null && !reduceMotion });
    fitted = key;
    userMoved = false;
  });

  /* ---- District names on the overview -------------------------------- */

  /**
   * DistrictPicker's labels, carried over: HTML markers at each district's
   * `point_on_surface` (not a centroid; QN14's falls in Jamaica Bay), the
   * largest district placed first, any label that would overlap a placed one
   * hidden. Its district is still clickable, and the entry page's list names
   * it.
   *
   * SIZE BY MAP SCALE, NOT BY OPENING VIEW. The picker sizes labels 7px at its
   * opening zoom, x1.35 per level in, capped at 12px. Its opening zoom is
   * Queens fitted into a 358x350 box. The docked map opens about 1.4 levels
   * closer in (Queens fitted into ~1035x900), so the same rule measured from
   * the picker's opening zoom gives ~10.5px here: the same size for the same
   * map scale on both maps.
   */
  const LABEL = { basePx: 7, growth: 1.35, maxPx: 12, pickerW: 358, pickerH: 350, pickerPad: 12 };

  let labels: maplibregl.Marker[] = [];

  /** The zoom at which `bbox` fits the phone picker's box: Web Mercator,
   *  512px tiles, as MapLibre's own fitBounds computes it. */
  function pickerZoom(bbox: MapDistrict['bbox']): number {
    const mercY = (lat: number) => Math.log(Math.tan(Math.PI / 4 + (lat * Math.PI) / 360)) / (2 * Math.PI);
    const dx = (bbox[2] - bbox[0]) / 360;
    const dy = mercY(bbox[3]) - mercY(bbox[1]);
    return Math.log2(
      Math.min(
        (LABEL.pickerW - 2 * LABEL.pickerPad) / (512 * dx),
        (LABEL.pickerH - 2 * LABEL.pickerPad) / (512 * dy)
      )
    );
  }

  function scaleLabels() {
    if (!map || !container || !overviewBbox) return;
    const px = Math.min(LABEL.maxPx, LABEL.basePx * LABEL.growth ** (map.getZoom() - pickerZoom(overviewBbox)));
    container.style.setProperty('--district-label-size', `${px.toFixed(2)}px`);
  }

  function layoutLabels() {
    for (const m of labels) m.getElement().style.display = '';
    requestAnimationFrame(() => {
      const placed: DOMRect[] = [];
      const PAD = 1;
      for (const marker of labels) {
        const el = marker.getElement();
        const r = el.getBoundingClientRect();
        const clash = placed.some(
          (q) => r.left < q.right + PAD && r.right > q.left - PAD && r.top < q.bottom + PAD && r.bottom > q.top - PAD
        );
        if (clash) el.style.display = 'none';
        else placed.push(r);
      }
    });
  }

  $effect(() => {
    const show = district === null;
    const list = overviewDistricts;
    if (!styleReady || !map) return;

    for (const m of labels) m.remove();
    labels = [];
    if (!show) return;

    const area = (d: MapDistrict) => (d.bbox[2] - d.bbox[0]) * (d.bbox[3] - d.bbox[1]);
    for (const d of [...list].sort((a, b) => area(b) - area(a))) {
      const el = document.createElement('span');
      el.className = 'district-label';
      el.textContent = d.display_name;
      labels.push(new maplibregl.Marker({ element: el }).setLngLat(d.point_on_surface).addTo(map));
    }
    scaleLabels();
    layoutLabels();
  });

  /**
   * Which points file the map should hold. A string so the effect below only
   * re-runs when it changes: toggling one category of twelve must filter the
   * points already loaded, not fetch them again.
   *
   * `[]` means the page shows no points, so nothing is fetched — the district
   * page would otherwise download up to 178 KB on every visit to draw nothing.
   */
  const resourcesUrl = $derived(
    !district || visibleCategories?.length === 0
      ? null
      : dataUrl(`layers/resources/${district.slug}.geojson`)
  );

  $effect(() => {
    const url = resourcesUrl;
    if (!styleReady || !map) return;

    map.getSource<GeoJSONSource>('resources')?.setData(url ?? EMPTY);
  });

  /**
   * Apply `?categories=` to the resource points.
   *
   * A filter rather than add/remove: the source stays loaded, so toggling a
   * category does not re-download the district's points. `null` means the
   * parameter was absent, which is the default of everything showing — so the
   * filter is removed entirely rather than built from all twelve slugs.
   */
  $effect(() => {
    const categories = visibleCategories;
    if (!styleReady || !map) return;

    map.setFilter(
      RESOURCE_LAYER,
      categories === null ? null : ['in', ['get', 'category'], ['literal', categories]]
    );
  });

  /**
   * Apply `?layers=` to the map.
   *
   * Reads `visibleLayers` and `styleReady`, so it re-runs both when the URL
   * changes and when the style finishes loading — the ordering between those
   * two is not guaranteed, and a toggle applied before `load` would throw.
   */
  $effect(() => {
    const on = new Set(visibleLayers);
    if (!styleReady || !map) return;

    for (const [layerId, spec] of Object.entries(specs)) {
      for (const layer of spec.layers) {
        map.setLayoutProperty(layer.id, 'visibility', on.has(layerId) ? 'visible' : 'none');
      }
    }
  });
</script>

<div class="map" bind:this={container} aria-label="Map of {district?.display_name ?? 'Queens'}"></div>

<style>
  .map {
    width: 100%;
    /* Fills the stage, which is whatever the header leaves of one viewport.
       The 04 Map frames give the map 748px of a 938px frame; a share of the
       viewport rather than a fixed height, so it holds on a phone that is not
       390x844. */
    height: 100%;
    background: var(--color-surface-sunken);
  }

  /* DistrictPicker's label: the app's sans with a surface-coloured halo, as
     the names sit over fills, outlines and streets. */
  .map :global(.district-label) {
    font-family: var(--font-sans);
    font-size: var(--district-label-size, 10px);
    line-height: var(--line-height-tight);
    color: var(--color-text-primary);
    text-align: center;
    white-space: nowrap;
    pointer-events: none;
    -webkit-text-stroke: 0.4em #fefcfa;
    paint-order: stroke fill;
    text-shadow: 0 0 2px #fefcfa;
  }

  /* MapLibre's controls are 29px by default, under the 44px minimum. */
  .map :global(.maplibregl-ctrl-group button) {
    width: var(--touch-target-min);
    height: var(--touch-target-min);
  }
</style>
