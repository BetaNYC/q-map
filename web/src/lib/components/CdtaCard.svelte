<script lang="ts">
  import { base } from '$app/paths';
  import type { DistrictIndexEntry } from '$lib/types';

  /**
   * The district card on the entry screen. Fourteen of them, one per Queens
   * CDTA.
   *
   * Replicates HazardRow's navigating-row shape — link wrapping the whole card,
   * padding on the <a> so the hit area and the fill are one rectangle. See that
   * file for the reasoning; not repeated here.
   *
   * Figma: CDTA Card, node 86:1965. 358x52 — 12px padding, a 14px bold name,
   * an 8px gap, a 12px label, 12px padding.
   *
   * BOTH LINES ARE SHIPPED AND BOTH ARE RENDERED. `display_name` ("The
   * Rockaways") and `cd_label` ("Community District 14") are different strings
   * and neither is derivable from the other (handoff §2). The accessible name
   * is both together, which is what makes the link stand alone in a list of
   * fourteen.
   *
   * The href is built from the STORED slug. Never derived from cdta2020 — a
   * published link must not drift.
   */

  interface Props {
    district: DistrictIndexEntry;
  }

  let { district }: Props = $props();
</script>

<a class="card" href="{base}/{district.slug}">
  <span class="name">{district.display_name}</span>
  <span class="label">{district.cd_label}</span>
</a>

<style>
  .card {
    display: flex;
    flex-direction: column;
    align-items: flex-start;
    gap: var(--space-200);

    /* 12px all round. Figma uses a literal 12 here rather than space/300, but
     * they are the same value. */
    padding: var(--space-300);

    background: var(--color-surface-sunken);

    /* 3px. Figma has no token for it — CategoryRow rounds to 4px from
     * space/100 and the rank chip to 2px from radius/sm, so this is the third
     * distinct radius in the file and the only one with no variable behind it.
     * Transcribed as drawn; listed in web/README.md. */
    border-radius: 3px;

    color: inherit;
    text-decoration: none;
  }

  .name {
    font-weight: var(--font-weight-bold);
    line-height: var(--line-height-tight);
  }

  .label {
    font-size: var(--font-size-small);
    line-height: var(--line-height-tight);
  }
</style>
