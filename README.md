# Queens Resource Map

**Under Construction**

An emergency-preparedness map for Queens. Hazard profiles, resource directories, and derived resource gaps for all 14 Community Districts.

## Approach

Everything is computed citywide across all 59 community-district CDTAs and
displayed for the 14 in Queens. The percentiles and composite indicators that appear on a district page are defined relative to the rest of the city, so the full matrix is needed to produce any single district's numbers.

## Layout

```
R/                  functions
scripts/            standalone scripts: mirrors, crosswalk build, heavy local steps
_targets.R          the pipeline
content/hazards/    hazard guidance
data/
  crosswalk/        geography + category crosswalks
  registry/         resource-gap registry
  canonical/        hand-maintained resource file
  source/           raw inputs (gitignored)
  prepared/         mirrored outputs (gitignored, published as data-v* GitHub releases)
  processed/        pipeline outputs (written and committed by CI)
alerts/             Notify NYC poller
web/                Svelte 5 + MapLibre app
```

## Running it

To come.

## Documents

To come.

## Notes

`test/` is the original dataset research
