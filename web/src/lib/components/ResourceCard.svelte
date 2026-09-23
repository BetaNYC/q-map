<script lang="ts">
  import { plainText } from '$lib/resources';
  import type { Resource } from '$lib/types';

  /**
   * The labelled detail rows on a resource page. QNPD and FRANC only — FacDB
   * records have no detail page by design.
   *
   * Figma: ResourceCard, node 85:1797. Rows 16px apart, each a bold header over
   * its value 8px below.
   *
   * ROWS ARE BUILT, NOT BRANCHED. Figma exposes eight booleans — hasMission,
   * hasAddress, hasPhone and so on. Modelling eight props would put the "is
   * this field present" decision on every caller. The rows are assembled from
   * the record here instead, and an empty value drops out.
   *
   * WHY THE WHOLE CARD CAN VANISH (§7.5). FRANC records carry ONLY `mission`,
   * and only 67 of 79 have one: address, phone, contact, email, languages,
   * fees, referrals and website are zero across all 79. So 12 of the 248
   * detail records produce no rows at all, and this renders nothing at all in
   * that case rather than an empty card with a border around it.
   *
   * FEES IS FREE TEXT, RENDERED VERBATIM. Not a boolean: "None", "Yes", "$40
   * registration fee", "Depends upon the program." Any attempt to interpret it
   * is wrong for some record.
   *
   * REFERRALS ONLY WHEN IT IS NOT "YES" (§7.5). "Yes" is the unremarkable case
   * — 164 of 168 — and a row saying so on almost every page is noise. The 4
   * records that say "No" are the ones worth a line. Figma's mock shows
   * "Accepts Referrals: Yes", which is the contradiction; §7.5 wins because it
   * is the behavioural rule and the frame is one illustrative instance.
   */

  interface Props {
    resource: Resource;
  }

  let { resource }: Props = $props();

  const rows = $derived.by(() => {
    const r = resource;

    // Contact is two fields stacked, as Figma draws it: a name line and an
    // email line, either of which may be missing on its own.
    const contact = [r.contact_name, r.email].filter(Boolean).join('\n');

    const candidates: Array<[string, string | undefined]> = [
      ['Mission', r.mission],
      ['Address', r.address],
      ['Phone', r.phone],
      ['Contact', contact],
      ['Languages Served', r.languages],
      ['Fees', r.fees],
      ['Accepts Referrals', r.accepts_referrals === 'Yes' ? undefined : r.accepts_referrals],
      ['Website', r.website]
    ];

    return candidates
      .filter((entry): entry is [string, string] => Boolean(entry[1]?.trim()))
      // 27 FRANC missions carry a literal <br>. plainText turns it into a real
      // newline that `white-space: pre-line` renders; nothing else is unescaped.
      .map(([label, value]) => ({ label, value: plainText(value) }));
  });
</script>

{#if rows.length}
  <dl class="card">
    {#each rows as row (row.label)}
      <div class="row">
        <dt>{row.label}</dt>
        <!-- A definition list, not a stack of paragraphs: these are labelled
             values and the association should be programmatic, not visual. -->
        <dd>{row.value}</dd>
      </div>
    {/each}
  </dl>
{/if}

<style>
  .card {
    display: flex;
    flex-direction: column;
    gap: var(--space-400);
    margin: 0;
  }

  .row {
    display: flex;
    flex-direction: column;
    gap: var(--space-200);
  }

  dt {
    font-weight: var(--font-weight-bold);
    line-height: var(--line-height-tight);
  }

  dd {
    margin: 0;
    line-height: var(--line-height-prose);
    overflow-wrap: break-word;

    /* Address and Contact arrive with newlines in them and Figma draws them on
       separate lines. Preserved without turning the whole value monospace or
       stopping it wrapping. */
    white-space: pre-line;
  }
</style>
