<script lang="ts">
  import '../app.css';

  let { children } = $props();
</script>

<!-- The app shell lands in build step 5. For now the layout exists only to own
     the global stylesheet and the prerender declaration in +layout.ts. -->
{@render children()}
