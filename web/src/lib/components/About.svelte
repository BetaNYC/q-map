<script lang="ts">
  /**
   * The About button in SiteHeader and the dialog it opens.
   *
   * The treatment is d26's AboutModal (a centred card over a dimmed page, the
   * title and a close button at the top, the copy scrolling below), drawn with
   * the same measurements. d26 builds this with a hand-written Modal: focus
   * trap, Escape, focus returned to the trigger, background made inert. A
   * native <dialog> opened with showModal() does all four, so this uses one.
   *
   * The copy is the entry page's about paragraph, word for word.
   */

  let dialog = $state<HTMLDialogElement>();

  /** A click on the dim area outside the card. The card fills the dialog box,
   *  so the dialog element itself is the click target only out there. */
  function onBackdropClick(e: MouseEvent) {
    if (e.target === dialog) dialog.close();
  }
</script>

<svelte:head>
  <!-- With no JavaScript the button would do nothing, so it is hidden, as
       LocateButton is. The same copy is on the entry page. -->
  <noscript><style>.about-button { display: none !important; }</style></noscript>
</svelte:head>

<!-- "Use my location"'s outlined style, as a smaller button. -->
<button type="button" class="about-button" aria-haspopup="dialog" onclick={() => dialog?.showModal()}>
  <span class="label">About</span>
</button>

<!-- svelte-ignore a11y_click_events_have_key_events, a11y_no_noninteractive_element_interactions -->
<dialog bind:this={dialog} aria-labelledby="about-title" onclick={onBackdropClick}>
  <div class="card">
    <div class="head">
      <h2 id="about-title">About</h2>
      <button type="button" class="close" onclick={() => dialog?.close()}>
        <span class="visually-hidden">Close</span>
        <span aria-hidden="true">&times;</span>
      </button>
    </div>
    <div class="content">
      <h2 id="background">Background</h2>
      <p>
        Though preparedness work is extensive throughout Queens, information is fragmented across agencies and organizations. 
        This leads to confusion during critical moments when accessing resources is key.  
        Q-Map provides a centralized tool for exploring neighborhood specific hazards and discovering local resources you can access to prepare for, respond to, or recover from disasters.  
        An initiative of the <a href="https://pandemicresponse.columbia.edu/pri-invests-in-community-led-resilience-in-queens/" rel="noopener noreferrer">Queens Resilience Network</a>, this digital asset map was created in partnership with Queens community-based organizations and <a href="https://beta.nyc">BetaNYC</a>, 
        a non-profit organization aimed at building technological resources for New Yorkers.
      </p>
      <h2 id="approach">Approach</h2>
      <p>
        Q-Map combines data from NYC's Department of City Planning's <a href="https://www.nyc.gov/content/planning/pages/resources/datasets/facilities">Facilities Database</a>, 
        the <a href="https://www.queensbp.nyc.gov/nonprofits/">Queens Non-Profit Directory</a>, 
        and local asset maps created by community organizations, namely the <a href="https://www.francnyc.org/">Far Rockaway Arverne Non-Profit Coalition's</a> resource map. 
        The combined database originally contained thousands of resources, 
        but feedback from Queens residents prompted a reduction to only the most critical ones to improve usability. 
        Resources were then aggregated at the community district level, a scale chosen to balance community identity with data resolution.
      </p>
      <p>
        Beyond spatial presentation of resources, Q-Map also organizes information by priority hazard areas as identified by the 2024 <a href="https://www.nyc.gov/site/doh/about/press/pr2025/nyc-health-identifies-top-public-health-hazards-new-yorkers.page">Jurisdictional Risk Assessment</a> released by the NYC Health Department. 
        These hazard areas were ranked for Queens specifically where possible. Additional information on the ranking methodology can be found in this <a href="https://betanyc.github.io/queens-hazard-ranking/">report.</a>
        Then, for each hazard type, best-practices and relevant resources from across city agencies were added in.
      </p>
      <p>
        From development through design and release, Q-Map was guided by Queens community leaders to create a final interactive tool which identifies designated locations for support, highlights preparedness programs, and integrates existing networks and assets.
      </p>
    </div>
  </div>
</dialog>

<style>
  /* LocateButton's .button: sunken fill, 0.5px secondary outline, 3px radius,
     bold body type. Shorter: a 44px button would fill the 44px bar edge to
     edge. The ::after below keeps the hit area 44px tall (WCAG 2.5.5). */
  .about-button {
    position: relative;
    flex-shrink: 0;
    display: flex;
    align-items: center;
    min-height: 32px;
    padding: 0 var(--space-300);
    box-sizing: border-box;
    background: var(--color-surface-sunken);
    border: 0.5px solid var(--color-text-secondary);
    border-radius: 3px;
    color: var(--color-text-primary);
    font: inherit;
    font-size: var(--font-size-body);
    font-weight: var(--font-weight-bold);
    line-height: var(--line-height-tight);
    cursor: pointer;
  }

  .about-button::after {
    content: '';
    position: absolute;
    inset: -6px 0;
  }

  /* Optical centring, as in LocateButton. */
  .label {
    text-box: trim-both cap alphabetic;
  }

  @supports not (text-box: trim-both cap alphabetic) {
    .label {
      position: relative;
      top: 0.1em;
    }
  }

  /* d26 Modal, placement="centered": 520px wide at most, 80vh tall at most,
     8px radius, 20px side padding, a 40% black scrim. */
  dialog {
    width: min(520px, calc(100% - 2 * var(--space-400)));
    max-width: none;
    max-height: 80vh;
    padding: 0;
    border: 0;
    border-radius: 8px;
    background: var(--color-surface);
    color: var(--color-text-primary);
  }

  dialog::backdrop {
    background: rgb(0 0 0 / 0.4);
  }

  /* The card, not the dialog, lays out the content: the dialog's own display
     must stay UA-controlled so it is hidden while closed. */
  .card {
    display: flex;
    flex-direction: column;
    max-height: 80vh;
  }

  .head {
    flex-shrink: 0;
    display: flex;
    align-items: center;
    gap: var(--space-200);
    padding: var(--space-400) 20px 0;
  }

  h2 {
    flex: 1 0 0;
    margin: 0;
    font-size: var(--font-size-body);
    font-weight: var(--font-weight-bold);
  }

  /* Popup's close: a 44px target around a small ×. Negative margins keep the
     box from growing the header row. */
  .close {
    display: flex;
    align-items: center;
    justify-content: center;
    width: var(--touch-target-min);
    height: var(--touch-target-min);
    margin: -14px -14px -14px 0;
    padding: 0;
    background: none;
    border: 0;
    font: inherit;
    font-size: var(--font-size-title);
    line-height: 1;
    color: var(--color-text-primary);
    cursor: pointer;
  }

  .content {
    overflow-y: auto;
    padding: var(--space-200) 20px var(--space-400);
    display: flex;
    flex-direction: column;
    gap: var(--space-300);
    font-size: var(--font-size-body);
    line-height: var(--line-height-prose);
  }

  .content p {
    margin: 0;
  }

  .content a {
    color: var(--color-link);
  }
</style>
