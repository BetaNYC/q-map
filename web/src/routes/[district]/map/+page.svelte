<script lang="ts">
  import { browser } from '$app/environment';
  import { goto } from '$app/navigation';
  import { base } from '$app/paths';
  import { page } from '$app/state';
  import ResourceRow from '$lib/components/ResourceRow.svelte';

  let { data } = $props();

  /**
   * §5's map state, read from the URL in the browser only.
   *
   * `browser` is not belt-and-braces — accessing page.url.searchParams during
   * prerender throws, because the prerendered page has no query string. On the
   * server this is null, which is exactly the default state; on the client the
   * $derived re-runs against the real URL, so a shared ?categories= link
   * resolves on hydration and on any later client-side navigation.
   *
   * null and [] are different: null is "no parameter, show the default", [] is
   * "a parameter was given and nothing in it was recognised". §5 says absent
   * means default, and that unknown ids are dropped rather than fatal.
   */
  const requested = $derived(browser ? page.url.searchParams.get('categories') : null);

  const known = $derived(new Set(data.district.resource_categories.map((c) => c.slug)));

  /** The categories showing. null -> all of them, the default. */
  const selected = $derived.by(() => {
    if (requested === null) return null;
    return requested.split(',').filter((slug) => known.has(slug));
  });

  function isOn(slug: string): boolean {
    return selected === null || selected.includes(slug);
  }

  /**
   * Toggling writes the selection back into the URL rather than into local
   * state, because the URL IS the state (§5). Two people opening the same link
   * see the same map, and the browser's back button walks the toggles.
   *
   * `replaceState` so twelve taps do not leave twelve history entries to back
   * out of. `noScroll` and `keepFocus` because the row that was tapped must
   * stay where it is and keep focus — a toggle that moves the page or drops
   * focus to the body is unusable with a keyboard or a screen reader.
   *
   * Order-independence (§5) falls out of deriving the parameter from the
   * category list rather than from tap order.
   */
  function toggle(slug: string) {
    const current = selected === null ? data.district.resource_categories.map((c) => c.slug) : selected;

    const next = current.includes(slug)
      ? current.filter((s) => s !== slug)
      : data.district.resource_categories.map((c) => c.slug).filter((s) => current.includes(s) || s === slug);

    const url = new URL(page.url);
    url.searchParams.set('categories', next.join(','));
    goto(url, { replaceState: true, noScroll: true, keepFocus: true });
  }
</script>

<!-- SCAFFOLD ONLY. The map itself, the bottom sheet and the popup are steps 8
     and 9. What is real here is the row list and its URL round-trip. -->

<p><a href="{base}/{data.district.slug}">{data.district.display_name}</a></p>

<h1>{data.district.display_name} map</h1>

<!-- All twelve stay listed whatever the selection — §7.3: every category is
     present and toggleable. Filtering the LIST would strand a user who arrived
     from a CategoryRow link with no way to turn anything else on. What the
     ?categories= parameter controls is which are ON, not which exist. -->
<ul class="rows">
  {#each data.district.resource_categories as category (category.slug)}
    <li>
      <ResourceRow {category} pressed={isOn(category.slug)} onToggle={toggle} />
    </li>
  {/each}
</ul>

<style>
  .rows {
    list-style: none;
    margin: 0;
    padding: 0;
  }
</style>
