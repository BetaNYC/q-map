<script lang="ts">
  import { page } from '$app/state';
  import { base } from '$app/paths';
</script>

<!-- Rendered when a load throws. On a static host this is reached by
     client-side navigation; a cold hit on an unknown URL is served by
     build/404.html, which src/routes/404/+page.svelte produces. Both are
     scaffolds until step 6. -->

<h1>{page.status}</h1>
<p>{page.error?.message ?? 'Something went wrong.'}</p>
<p><a href="{base}/">Back to the map</a></p>
