<script lang="ts">
  import { base } from '$app/paths';
  import { measureLine } from '$lib/hazards';

  let { data } = $props();
</script>

<!-- SCAFFOLD ONLY. The hazard screen is built in step 7; this exists so the
     112 routes are real and HazardRow's links resolve. -->

<p><a href="{base}/{data.district.slug}">{data.district.display_name}</a></p>

<h1>{data.hazard.label}</h1>
<p>{measureLine(data.hazard)}</p>
