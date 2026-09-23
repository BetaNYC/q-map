<script lang="ts">
  import { base } from '$app/paths';
</script>

<!-- This route exists to produce build/404.html.

     GitHub Pages serves a site-root 404.html, with a real 404 status, for any
     path that does not resolve — which is how §5's "a bad route is an error"
     survives on a host with no server. Writing it as a route rather than as a
     hand-authored static/404.html means it inherits the layout and, later, the
     design tokens.

     With trailingSlash at its default ('never') adapter-static writes this to
     build/404.html, exactly where Pages looks. If trailingSlash ever changes to
     'always' it becomes build/404/index.html and Pages stops finding it.

     SCAFFOLD ONLY — copy and layout land in step 6. -->

<svelte:head>
  <title>Page not found | Queens Resource Map</title>
</svelte:head>

<h1>Page not found</h1>
<p>That district, hazard or resource does not exist.</p>
<p><a href="{base}/">Back to the district list</a></p>
