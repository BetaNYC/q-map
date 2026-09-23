<script lang="ts">
  import { mailtoHref, plainText, telHref, websiteHref } from '$lib/resources';
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
   * A ROW HOLDS LINES, NOT A STRING. Contact stacks a name over an email, and
   * only the email is a link; Address arrives with newlines in it. So each row
   * is a list of lines, each optionally carrying an href.
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

  interface Line {
    text: string;
    href?: string;
  }

  interface Props {
    resource: Resource;
  }

  let { resource }: Props = $props();

  const rows = $derived.by(() => {
    const r = resource;
    const built: Array<{ label: string; lines: Line[] }> = [];

    const add = (label: string, lines: Array<Line | null>) => {
      const kept = lines.filter((l): l is Line => l !== null && Boolean(l.text?.trim()));
      if (kept.length) built.push({ label, lines: kept });
    };

    // plainText handles the 27 FRANC missions carrying a literal <br>.
    add('Mission', [r.mission ? { text: plainText(r.mission) } : null]);
    add('Address', [r.address ? { text: r.address } : null]);
    add('Phone', [r.phone ? { text: r.phone, href: telHref(r.phone) ?? undefined } : null]);

    // Two lines, and only the second is ever a link.
    add('Contact', [
      r.contact_name ? { text: r.contact_name } : null,
      r.email ? { text: r.email, href: mailtoHref(r.email) ?? undefined } : null
    ]);

    add('Languages Served', [r.languages ? { text: r.languages } : null]);
    add('Fees', [r.fees ? { text: r.fees } : null]);

    if (r.accepts_referrals && r.accepts_referrals !== 'Yes') {
      add('Accepts Referrals', [{ text: r.accepts_referrals }]);
    }

    add('Website', [
      r.website ? { text: r.website, href: websiteHref(r.website) ?? undefined } : null
    ]);

    return built;
  });
</script>

{#if rows.length}
  <dl class="card">
    {#each rows as row (row.label)}
      <div class="row">
        <dt>{row.label}</dt>
        <!-- A definition list, not a stack of paragraphs: these are labelled
             values and the association should be programmatic, not visual. -->
        <dd>
          {#each row.lines as line, i (line.text + i)}
            <span class="line">
              {#if line.href}
                <a href={line.href}>{line.text}</a>
              {:else}
                {line.text}
              {/if}
            </span>
          {/each}
        </dd>
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
  }

  .line {
    display: block;
    /* Address arrives with newlines in it and Figma draws it on separate
       lines. Preserved without turning the value monospace or stopping it
       wrapping. */
    white-space: pre-line;
  }

  /* Blue and underlined, matching PhoneElement — the treatment the app already
     gives a tappable number. Figma draws these as plain black text; see
     $lib/resources for why that is departed from. */
  .line a {
    color: var(--color-link);
    text-decoration: underline;

    /* TARGET SIZE. These are inline links inside a labelled value, not list
     * rows — the 44px table in §10 covers Resource Row, LayerRow, CategoryRow
     * and HazardRow, all of which pass.
     *
     * WCAG 2.1 AA, which §10 names, has no target-size criterion. 2.2 added
     * 2.5.8 at 24px AA, with an explicit exception for targets "in a sentence
     * or block of text" — which these are. 44px is 2.5.5, AAA.
     *
     * Padded to clear 24px anyway, because a 14px phone link on a phone is
     * genuinely hard to hit. NOT to 44px: that needs +15px a side against an
     * 8px gap between lines, so adjacent targets would overlap — which 2.5.8
     * prohibits in the same breath. The negative margin keeps the layout. */
    display: inline-block;
    padding-block: 5px;
    margin-block: -5px;
  }
</style>
