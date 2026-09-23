<script lang="ts">
  import maplibregl from 'maplibre-gl';
  import 'maplibre-gl/dist/maplibre-gl.css';
  import { dataUrl } from '$lib/data';
  import { BASEMAP_STYLE, INITIAL_CENTER, INITIAL_ZOOM } from '$lib/map/basemap';
  import { overlaySpecs } from '$lib/map/overlays';
  import { registerMapProtocols } from '$lib/map/protocols';
  import type { DistrictIndexEntry } from '$lib/types';

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
   */

  interface Props {
    district: DistrictIndexEntry;
    /** `layer_id`s currently on, from `?layers=`. */
    visibleLayers: string[];
    /** Category slugs currently on, from `?categories=`. null means all. */
    visibleCategories: string[] | null;
    /** Fired when a resource point is tapped — the page writes `?resource=`. */
    onSelectResource: (resourceId: string) => void;
  }

  let { district, visibleLayers, visibleCategories, onSelectResource }: Props = $props();

  /** The resource points layer id, used by the filter effect and the click
   *  handler. `layers/resources/<slug>.geojson` carries only resource_id,
   *  name, category, source and is_coad_member — the popup's address and
   *  operator come from the join the page does (§7.4). */
  const RESOURCE_LAYER = 'resource-points';

  let container = $state<HTMLDivElement>();
  let map: maplibregl.Map | undefined;
  let styleReady = $state(false);

  const specs = overlaySpecs();

  $effect(() => {
    if (!container) return;

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
        filter: ['!=', ['get', 'cdta2020'], district.cdta2020],
        paint: { 'line-color': '#d7dce4', 'line-width': 0.75 }
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
      // for one Queens-wide file. A district map needs only its own.
      instance.addSource('resources', {
        type: 'geojson',
        data: dataUrl(`layers/resources/${district.slug}.geojson`)
      });

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
        if (typeof id === 'string') onSelectResource(id);
      });

      // A point is a 6px circle; the cursor is the only affordance on a
      // pointer device that it can be tapped at all.
      instance.on('mouseenter', RESOURCE_LAYER, () => {
        instance.getCanvas().style.cursor = 'pointer';
      });
      instance.on('mouseleave', RESOURCE_LAYER, () => {
        instance.getCanvas().style.cursor = '';
      });

      instance.addLayer({
        id: 'cdta-current',
        type: 'line',
        source: 'cdta',
        filter: ['==', ['get', 'cdta2020'], district.cdta2020],
        paint: { 'line-color': '#0a0a0a', 'line-width': 2 }
      });

      // bbox is [xmin, ymin, xmax, ymax] in EPSG:4326, straight from
      // districts.json — no need to compute it from the geometry.
      instance.fitBounds(
        [
          [district.bbox[0], district.bbox[1]],
          [district.bbox[2], district.bbox[3]]
        ],
        { padding: 24, animate: false }
      );

      map = instance;
      styleReady = true;
    });

    return () => {
      styleReady = false;
      map = undefined;
      instance.remove();
    };
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

<div class="map" bind:this={container} aria-label="Map of {district.display_name}"></div>

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

  /* MapLibre's controls are 29px by default, under the 44px minimum. */
  .map :global(.maplibregl-ctrl-group button) {
    width: var(--touch-target-min);
    height: var(--touch-target-min);
  }
</style>
