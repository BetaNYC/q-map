# Queens Resource Map

**Under Construction**

An emergency-preparedness map for Queens. Hazard profiles, resource directories, and derived resource gaps for all 14 Community Districts.

**What's changed:** every change a reader would notice, newest first, is in [`WHATS-CHANGED.md`](WHATS-CHANGED.md) and on the site at https://betanyc.github.io/q-map/whats-changed, linked from the home page. A change a reader would notice gets an entry at the top, dated the day it is merged (merging to `main` deploys the site): if that day has moved on since the entry was written, the last commit before merge changes the entry's date to the merge date. Old entries are never edited; add a dated `- **Update YYYY-MM-DD:**` line instead. `npm run whats-changed` in `web/` rebuilds the page, and every build runs it. `web/scripts/whats_changed.py` is a copy of a shared BetaNYC file: do not edit it here. It sits under `web/` so that changing it does not re-run the pipeline.

## Approach

Everything is computed citywide across all 59 community-district CDTAs and
displayed for the 14 in Queens. The percentiles and composite indicators that appear on a district page are defined relative to the rest of the city.

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
