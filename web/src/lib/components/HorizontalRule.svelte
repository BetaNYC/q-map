<!--
  Figma: HorizontalBreak — the divider between sections and above/below COAD.

  A 0.5px line inset 10px from each end, in #707070. Exported by Figma as an
  SVG; it is a border here, because an <img> of a line cannot follow the text
  colour, scales badly and costs a request.

  NOTE THE COLOUR: `--color-text-secondary`, not `--color-border`. The design
  uses the secondary text grey for rules and reserves border/default (#d7dce4)
  for the group rule inside NestedContainer. Transcribed as drawn rather than
  normalised to one.

  Presentational: `role="presentation"` rather than a bare <hr>, because the
  sections around it already carry headings that convey the same boundary, and
  a screen reader announcing a separator between every one is noise.
-->
<div class="rule" role="presentation"></div>

<style>
  .rule {
    /* 0.5px renders as a hairline on a 2x screen and rounds to 1px on a 1x
       one, which is what the design intends either way. */
    border-top: 0.5px solid var(--color-text-secondary);
    margin-inline: 10px;
  }
</style>
