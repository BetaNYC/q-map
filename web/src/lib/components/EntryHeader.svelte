<script lang="ts">
  /**
   * The entry screen's title. Figma: EntryHeader, node 86:1920 — 358x30, the
   * text inset 8px and 4px.
   *
   * Same type as DistrictHeader's name (title/map-heading, 18px, -0.2px
   * tracking), which is deliberate: on the entry screen this IS the page
   * title, and on a district screen the district's name takes the same slot.
   */
</script>

<header class="header">
  <h1 class="title">Queens Resource Map</h1>
</header>

<style>
  .header {
    display: flex;
    flex-direction: column;
    align-items: flex-start;
    padding-inline: var(--space-200);
    padding-block: var(--space-100);
  }

  .title {
    margin: 0;
    font-size: var(--font-size-title);
    font-weight: var(--font-weight-title);
    letter-spacing: var(--letter-spacing-title);
    line-height: var(--line-height-tight);
  }
</style>
