# Queens Resource Map

**Under Construction**

An emergency-preparedness map for Queens. Hazard profiles, resource directories, and derived resource gaps for all 14 Community Districts.

## Approach

Everything is computed citywide across all 59 community-district CDTAs and
displayed for the 14 in Queens. The percentiles and composite indicators that appear on a district page are defined relative to the rest of the city, so the full matrix is needed to produce any single district's numbers.

## Layout

```
R/                  function library, sourced into the DAG
scripts/            standalone: mirrors, crosswalk build, heavy local steps
_targets.R          the pipeline
content/hazards/    authored hazard guidance
data/
  crosswalk/        committed, hand-verifiable geography + category crosswalks
  registry/         the resource-gap registry
  canonical/        the hand-maintained resource file
  source/           raw inputs (gitignored)
  prepared/         Tier-2 mirror outputs (gitignored, published as data-v*)
  processed/        pipeline outputs (written and committed by CI)
alerts/             Notify NYC poller — separate service, separate deploy
web/                Svelte 5 + MapLibre app
```

## Running it

To come.

## Documents

To come.

## Notes

`test/` is the original dataset research
