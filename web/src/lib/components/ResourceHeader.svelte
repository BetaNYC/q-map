<script lang="ts">
  import { base } from '$app/paths';
  import ArrowLeftIcon from '$lib/icons/ArrowLeftIcon.svelte';

  /**
   * The resource detail screen's header. Figma: ResourceHeader, node 85:1781 —
   * the resource name at 18px, its category at 12px, and a back link.
   *
   * THE BACK LINK IS A PROPERTY OF THE ROUTE (§5). Resource pages are
   * district-scoped precisely so this can be a real href to a real page rather
   * than a history.back() that has nowhere to go when someone arrives from a
   * shared link.
   *
   * It points at the MAP, not the district page — back to the view this
   * resource was tapped in, with its category filtered and its popup reopened.
   * The caller supplies the href (see mapReturnPath in $lib/resources) rather
   * than this component building one, so the destination is visible at the
   * call site instead of buried in a header.
   *
   * The LABEL is still the district name. That is deliberate: it names where
   * you are going back to, and the map is district-scoped, so "The Rockaways"
   * is true of both the district page and the district's map.
   *
   * Same shape as DistrictHeader; see that file for why the back link is drawn
   * in primary black rather than link blue.
   */

  interface Props {
    name: string;
    /** The resolved category label, not the slug. */
    categoryLabel: string;
    /** Site-relative, without `base` — applied here as everywhere else. */
    backHref: string;
    districtName: string;
  }

  let { name, categoryLabel, backHref, districtName }: Props = $props();
</script>

<header class="header">
  <h1 class="name">{name}</h1>
  <p class="category">{categoryLabel}</p>

  <div class="body">
    <a class="back" href="{base}{backHref}">
      <ArrowLeftIcon />
      {districtName}
    </a>
  </div>
</header>

<style>
  .header {
    display: flex;
    flex-direction: column;
    align-items: flex-start;
    gap: var(--space-300);
    padding-inline: var(--space-200);
    padding-bottom: var(--space-200);
  }

  .name {
    margin: 0;
    font-size: var(--font-size-title);
    font-weight: var(--font-weight-title);
    letter-spacing: var(--letter-spacing-title);
    line-height: var(--line-height-tight);
    overflow-wrap: break-word;
  }

  .category {
    margin: 0;
    font-size: var(--font-size-small);
    line-height: var(--line-height-tight);
  }

  .body {
    display: flex;
    flex-direction: column;
    align-items: flex-start;
    padding-left: var(--space-100);
    font-size: var(--font-size-small);
  }

  .back {
    display: flex;
    align-items: center;
    gap: var(--space-100);
    color: var(--color-text-primary);
    text-decoration: none;
    line-height: var(--line-height-tight);

    /* 44px hit area on a 12px line, taken as padding with the margin pulled
       back so the ink stays where the design puts it. */
    padding-block: calc((var(--touch-target-min) - 1lh) / 2);
    margin-block: calc((var(--touch-target-min) - 1lh) / -2);
  }
</style>
