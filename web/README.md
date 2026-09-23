# web — the Queens Resource Map frontend

Svelte 5 + MapLibre GL JS, prerendered to static HTML, deployed to GitHub Pages
at `https://betanyc.github.io/q-map/`.

`Q-MAP-frontend-handoff.md` is the brief; `DATA_CONTRACT.md` is the data
contract. This file covers only the one thing neither of them decides: how
`data/processed/` becomes a URL.

## Getting started

```bash
cd web
npm install
npm run dev        # http://localhost:5173/q-map/
```

The dev server serves at `/q-map/`, not `/`. That is deliberate — the base path
is exercised from the first minute rather than discovered at deploy.

| Script | Does |
|---|---|
| `npm run dev` | dev server, guarded by `scripts/check-data.mjs` |
| `npm run build` | prerender every route to `build/`, same guard |
| `npm run preview` | serve `build/` as Pages will |
| `npm run check` | `svelte-check` |

## The data path

`web/static/data` is a **symlink** to `../../data/processed`, committed to the
repo (git stores it as mode `120000`).

`data/processed/` is itself committed — CI writes and auto-commits it — so a
fresh clone has real payloads with no pipeline run and no sync step to forget.
Re-run `tar_make()` and the dev server serves the new outputs immediately,
because there is no copy to go stale.

Everything resolves to `{base}/data/<path>`, where `<path>` is exactly the path
`DATA_CONTRACT.md` §1 names. **`src/lib/data.ts` is the only place that builds
that URL**; nothing else should concatenate one.

The same URL works in `vite dev`, in `vite preview`, during prerender and on
Pages. Verified, including `206 Partial Content` on the `.pmtiles` files — a
range request is not optional for PMTiles, and it works through the symlink.

**CI never traverses the symlink.** Both workflows replace it with a real
directory before building, so a change in how Vite or SvelteKit handles symlinks
can only ever break a developer's machine, never a deploy.

### If `static/data` goes missing

`scripts/check-data.mjs` runs on `predev` and `prebuild` and fails loudly.
Without it the build succeeds and prerenders 389 pages of nothing, which reads
as a data problem rather than a setup one.

```bash
ln -s ../../data/processed web/static/data
```

## Routing

Static prerender, one HTML file per route — 389 once every screen has landed,
16 today (entry, the Queens 14, and 404). `svelte.config.js` sets
`paths.base` to `/q-map` (GitHub Pages project site) and adapter-static runs in
its default `strict` mode, so a route that cannot be prerendered fails the build
instead of quietly becoming a production 404.

Parameterised routes generate their own entries — see
`src/routes/[district]/+page.server.ts` for the worked example. No route list is
hand-maintained.

`src/routes/404/+page.svelte` produces `build/404.html`, which Pages serves with
a real 404 status for any unresolved path.

### Two loader shapes, and the measurement behind them

| File | Runs | Serialised into the HTML |
|---|---|---|
| `+page.ts` | prerender **and** browser | the whole fetched **response** |
| `+page.server.ts` | prerender only | only the **returned value** |

Measured on the same ~114 KB source file returning the same single record:
**193,790 bytes** of HTML from a universal load, **1,595 bytes** from a server
load. Fetching `resources/q*.json` in a universal load on the 248
resource-detail pages would be roughly 48 MB of HTML to deliver 248 addresses.

So: universal where the client genuinely needs the whole payload (the map
screen's popup join), server where the build should slice it (resource detail).

## Cache busting

CI sets `VITE_DATA_VERSION` to the deploy SHA and `dataUrl()` appends it as
`?v=`. Unset in dev, so local URLs stay clean.

Not the `DATA_VERSION` file (`data-v4`) — that is the tag of the Tier-2 *input*
mirror release the pipeline downloads, and it does not change when the outputs
change.

## Deployment

`.github/workflows/pipeline.yml` builds and deploys the app and the data as one
artifact. The web build lives in that workflow rather than a separate one on
purpose: its `paths-ignore: data/processed/**` guard sits on the trigger, so a
Pages workflow added alongside it would not inherit the guard and the pipeline's
auto-commit would set the two chasing each other.

A push touching only `web/` skips the R pipeline — `web/**` is not in the
`changes` filter — and deploys against the committed `data/processed/`.

`.github/workflows/web.yml` builds and type-checks on every pull request
touching `web/`. `pipeline.yml` has no `pull_request` trigger, so without it a
frontend PR gets no automated check at all.
