<script lang="ts">
  import { base } from '$app/paths';

  let { data } = $props();
</script>

<!-- SCAFFOLD ONLY. The district screen — hazard rows, resource categories, gap
     sentences — is built in step 5. -->

<p><a href="{base}/">All districts</a></p>

<!-- display_name and cd_label are both shipped and both rendered; neither is
     derivable from the other (handoff §2). -->
<h1>{data.district.display_name}</h1>
<p>{data.district.cd_label} · {data.district.cdta2020}</p>

{#if data.district.coad_name}
  <!-- Renders in 1 of 14 districts. null is the common case, not the edge. -->
  <p>{data.district.display_name} is served by the {data.district.coad_name}</p>
{/if}
