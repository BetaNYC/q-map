<script lang="ts">
  import { browser } from '$app/environment';
  import { base } from '$app/paths';
  import { page } from '$app/state';

  let { data } = $props();

  /**
   * §5's map state, read from the URL in the browser only.
   *
   * `browser` is not belt-and-braces — accessing page.url.searchParams during
   * prerender throws the same error a load would, because the prerendered page
   * has no query string. On the server this is null, which is exactly the
   * default state; on the client the $derived re-runs against the real URL, so
   * a link shared with ?categories= resolves on hydration and on any later
   * client-side navigation.
   *
   * null and [] are different: null is "no parameter given, show the default",
   * [] is "a parameter was given and nothing in it was recognised". §5 says
   * absent means default, and that unknown ids are dropped rather than fatal —
   * so a link shared before a category was retired opens the map minus that
   * category, not on an error page.
   */
  const requested = $derived(browser ? page.url.searchParams.get('categories') : null);

  const known = $derived(new Set(data.district.resource_categories.map((c) => c.slug)));

  const selected = $derived(
    requested === null ? null : requested.split(',').filter((slug) => known.has(slug))
  );

  const showing = $derived(
    selected === null
      ? data.district.resource_categories
      : data.district.resource_categories.filter((c) => selected.includes(c.slug))
  );
</script>

<!-- SCAFFOLD ONLY. The map, the bottom sheet, the tabs and the popup are steps
     8 and 9. This renders the resolved state so the CategoryRow link is
     verifiable end to end: the category it carried is the one showing. -->

<p><a href="{base}/{data.district.slug}">{data.district.display_name}</a></p>

<h1>{data.district.display_name} map</h1>

<p>
  {#if selected === null}
    Showing all {showing.length} categories — the default, no ?categories= given.
  {:else}
    Showing {showing.length} of {data.district.resource_categories.length} categories.
  {/if}
</p>

<ul>
  {#each showing as category (category.slug)}
    <li>{category.label} — {category.count}</li>
  {/each}
</ul>
