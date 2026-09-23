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
  }

  let { district, visibleLayers }: Props = $props();

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
    /* The 04 Map frames give the map 748px in a 938px frame. Here it is a
       share of the viewport so it works on a phone that is not 390x844 —
       the bottom sheet takes the rest in step 9. */
    height: 60svh;
    min-height: 320px;
    background: var(--color-surface-sunken);
  }

  /* MapLibre's controls are 29px by default, under the 44px minimum. */
  .map :global(.maplibregl-ctrl-group button) {
    width: var(--touch-target-min);
    height: var(--touch-target-min);
  }
</style>
