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

Static prerender, one HTML file per route. **All 389 exist**, plus `404.html`:

| Route | Count | Generated from |
|---|---|---|
| `/` | 1 | — |
| `/q{NN}` | 14 | `districts.json`, filtered on `boro` |
| `/q{NN}/{hazard}` | 112 | each district payload's `hazards[]` |
| `/q{NN}/map` | 14 | `districts.json` |
| `/q{NN}/resource/{source}/{slug}` | 248 | `resources/q*.json`, `source !== 'facdb'` |

No list is hand-maintained, and each generator asserts its own count — 14 × 8
for hazards, exactly 248 for resources. A short payload would otherwise just
build fewer pages, and the links into them would 404 in production with
nothing having failed.

**The 248 resource pages use a server load, not a universal one.** Each needs
one record out of a 114 KB `resources/q*.json`. Built with a universal load
first, and measured: **306 KB of HTML per page and 44 MB across the build**,
against 12 MB of actual data. A server load serialises only what it returns —
3.0 MB total. The map screen is the opposite case and keeps its universal
load, because it genuinely needs the whole list client-side for the popup join.

**FacDB records get no route, and that absence *is* the behaviour.** 3,547 of
the 3,795 resources are popup-only, with `/q{NN}/map?resource=facdb:<hash>` as
their permalink (§7.4). Because the generator never emits them,
`/q14/resource/facdb/<hash>` is a path that was never built — no explicit
rejection is written, and none is needed.

§5's unknown-input table, verified against a served build:

| Case | Result |
|---|---|
| `/q99` — unknown district | 404 |
| `/q14/nonsense` — unknown hazard | 404 |
| `/bk01` — non-Queens CDTA | 404 |
| `/q14/resource/facdb/…` | 404 |
| `/q14/resource/qnpd/not-a-real-org` | 404 |
| unknown `?categories=` / `?layers=` id | dropped, page renders |
| unknown `?resource=` id | map opens, no popup, no error |

`svelte.config.js` sets
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
resource-detail pages was measured at 44 MB of HTML to deliver 248 addresses —
predicted at ~48 MB before the routes existed, and it is why they use a server
load.

So: universal where the client genuinely needs the whole payload (the map
screen's popup join), server where the build should slice it (resource detail).

## Accessibility

**WCAG 2.1 Level AA.** §10 calls this a requirement rather than an aspiration —
it is the standard state and local government web content must meet.

`axe-core` is a devDependency so the audit is repeatable. Run against a served
build over CDP, at `wcag2a,wcag2aa,wcag21a,wcag21aa`, on nine page states:

```
entry · district · hazard · hazard+conditions · resource · map ·
404 · map with the popup open · map with the sheet expanded

0 violations
```

axe catches perhaps a third of what matters, so the rest of §10's list was
tested directly:

| §10 item | Result |
|---|---|
| Tabs: `role="tablist"`, `aria-selected`, `role="tabpanel"` | ✅ plus arrow-key navigation |
| Toggle rows: real `<button>` + `aria-pressed` | ✅ `ResourceRow`, `LayerRow` |
| Navigating rows are `<a href>` | ✅ `HazardRow`, `CategoryRow`, `CdtaCard` |
| Sheet: `aria-expanded`, non-gesture collapse | ✅ handle is a real button |
| Popup: focus in, Escape, visible close, focus returns | ✅ see below |
| Score/rank not by colour alone | ✅ the number is in the accessible name |
| Link text stands alone | ✅ resource name appended in the popup's link |
| TTY labelled | ✅ `"Con Edison TTY, 1-800-642-2308"` |
| `:focus-visible` ring | ✅ measured 2px solid on a real Tab press |
| Reduced motion | ✅ 3 rules ship — sheet, layer swatch, MapLibre |
| `lang` on the document | ✅ `en` |

### The popup

Verified by dispatching a real Escape key:

```
role / aria-labelledby   dialog / popup-name -> "Her Care Inc"
focus on open            the popup container
after Escape             closed, ?resource= removed
focus returned to        .maplibregl-canvas
```

Focus lands on the container, not the close button — the name and address are
announced before the controls. Not `aria-modal`: the map behind stays usable
and nothing is trapped.

The trigger is a point on the map, which is not focusable; MapLibre's canvas
is. Returning there is the closest true reading of "returns to the trigger",
and without it focus falls to `<body>` and the next Tab restarts from the top.

### Target sizes

| Screen | ≥44px | 24–43px | <24px |
|---|---|---|---|
| entry | 14 | 0 | 0 |
| district | 21 | 0 | 0 |
| hazard | 8 | 6 | 0 |
| resource | 1 | 3 | 0 |
| map + sheet | 18 | 0 | 2 |

Every **row** clears 44px, which is what §10's table is about — it lists
Resource Row, LayerRow, CategoryRow and HazardRow.

The 24–43px group is inline links inside a labelled value: phone, TTY, email,
website. **WCAG 2.1 AA, which §10 names, has no target-size criterion at all**;
2.2 added 2.5.8 at 24px AA with an explicit exception for targets "in a
sentence or block of text", and 44px is 2.5.5, AAA. They are padded to clear
24px anyway, because a 14px phone link on a phone is genuinely hard to hit —
but **not** to 44px, which would need +15px a side against an 8px gap and make
adjacent targets overlap, something 2.5.8 prohibits in the same breath.

The two under 24px are MapLibre's own attribution links ("CARTO",
"OpenStreetMap") — third-party markup, inline, required attribution.

### Fixed in this pass

The map screen and `404.html` had **no `<title>`** — the only two real axe
violations, both `serious`. The map screen lost its `<h1>` when the stage
layout landed and never gained a title; the 404 route never had one.

### The limitation §10 asks to be written down

The interface is English-only, in a tool whose leading gap sentence for several
districts is that emergency alerts are not published in residents' languages.
§10 asks that this be recorded as a known gap rather than discovered later.

## Design tokens

`src/tokens.css` holds every colour, size and spacing value, transcribed from
the Figma file `Final-UI` with the Figma variable name in a comment on each
line. `src/app.css` imports it first and sets global element defaults.
**Nothing else in the app carries a literal value** — that comment trail is how
a Figma change is found here.

Hand-written, not generated: ~30 constants that move rarely do not justify a
build-time dependency on the Figma API, unlike `DATA_CONTRACT.md`, whose input
is 3,795 rows.

Two places the transcription deliberately departs from the file:

- **Line height.** Figma's variable dump says `lineHeight: 100`, but its text
  nodes export as `line-height: normal` — `get_design_context` confirms it on
  every one. So it is split into `--line-height-tight` (`normal`, ~1.2) for
  labels and chips, and `--line-height-prose` (1.5, the figure WCAG 1.4.12
  names) for anything that wraps at length.
- **Duplicate namespaces.** Figma defines each value twice
  (`space/100` / `Spacing/space/100`, `Color/on-surface/*` /
  `color/text-blacks/*`). One CSS variable per distinct value, both Figma names
  noted.

### Fonts

AUTHENTIC Sans Pro is licensed for this project and self-hosted. Two static
cuts, declared in `src/fonts.css`:

| File | `font-weight` | Figma |
|---|---|---|
| `src/fonts/authentic-sans-pro-90.woff2` | 433 | style 90 — `body/*`, `caption/metadata` |
| `src/fonts/authentic-sans-pro-130.woff2` | 611 | style 130 — `body/*-bold`, `title/map-heading` |

The weights are Figma's own reported values, so one number runs unbroken from
the Figma token through `tokens.css` to the face that serves it. (d26 ships the
same two files declared at 400/600 under the family name `AUTHENTIC Sans`; not
inherited, because it makes the design's stated weight and the CSS disagree.)

**The files live in `src/fonts/`, not `static/fonts/`.** A `url('/fonts/…')`
under `static/` is root-relative to the *origin* and would 404 under `/q-map/`,
and hardcoding `/q-map/fonts/…` would duplicate a base path `svelte.config.js`
owns. From `src/`, Vite resolves the reference itself, emits the file to
`_app/immutable/assets/` with a content hash, and writes a stylesheet-relative
URL that is correct at any route depth and any base path. It also earns a
far-future cache header, which `static/` does not — Pages serves that at
`max-age=600`.

The condensed cuts exist in d26 but no frame in `Final-UI` uses them, so they
are not carried here.

`NewComputerModernMono10` (`--font-mono-icon`) is **not** loaded as a webfont —
see Icons below. The token remains declared, falling through to the system
monospace stack, in case a genuinely typographic use appears.

## Icons

`icon/default` in Figma is NewComputerModernMono10 BookItalic at 12px. It is
used in three places, and they do not all want the same treatment:

| Component | Glyph | Fixed or derived |
|---|---|---|
| `COAD` | `i` | fixed |
| `AlertBanner` | `!` | fixed — and never renders in v1 (handoff §7.7) |
| `ResourceRow` | the category label's **initial** | derived from data |

The first two ship as inline SVG. The third cannot: it is data-derived, changes
if a category is renamed upstream, and has no fixed glyph to extract. **That one
needs the webfont**, subsetted.

`src/lib/categories.ts` owns the rule — the label's first letter, with two
overrides, because the scheme exists to keep the marks distinct rather than to
be mechanical:

| Category | Mark | Why |
|---|---|---|
| Health care | `hc` | plain first letters gave `h` twice |
| Housing and shelter | `s` | from *shelter* |
| everything else | first letter | |

Derive-with-overrides rather than a table of twelve, because §6 is explicit that
the set is derived per district and has already changed twice — a table would
leave a new category with no mark at all.

**The build asserts the marks stay distinct**, per district, in the map route's
`entries()`. Two categories drawing the same letter is invisible at runtime — it
just looks deliberate, which is how the `h` collision survived into the design —
so it has to fail at build time. Verified by removing both overrides:

```
q01: categories "health-care" and "housing-and-shelter" both render the mark "h".
     Add an override in src/lib/categories.ts.
```

The twelve marks for Queens: `c hc p f l e b g o d s i`.

`--font-mono-icon` currently falls through to the system monospace stack.
Subsetting `NewCMMono10-BookItalic.otf` to those marks plus `i!` and converting
to woff2 is the outstanding work; the OTF is 584 KB and a 2-glyph subset
measured 2,000 bytes, so a 13-glyph one is small.

The two fixed marks ship as inline SVG in `src/lib/icons/`, with outlines
extracted from
the OTF rather than traced, so the curves are the ones the design shows. The
flip from font space (Y up, origin on the baseline) to SVG space (Y down,
origin top-left) and the centring in the 24×24 `IconFrame` are baked into the
coordinates — there is no `transform` attribute to strip.

**The reason is accessibility, not payload.** In Figma these are text nodes
containing the letters `i` and `!`; built as text, a screen reader reads "i"
into the middle of "*&lt;district&gt; is served by the &lt;coad_name&gt;*".
`aria-hidden` on an SVG removes it. The bytes are a wash — ~1.4 KB of path data
against a ~2 KB subsetted font — and since `ResourceRow` needs the font shipped
anyway, the SVGs save a request rather than a dependency. The accessible-name
argument is the one that stands.

`InfoIcon.svelte` carries the full reasoning; `AlertIcon.svelte` points at it.
`aria-hidden` and `focusable` are fixed rather than props: an icon that needs
its own accessible name is a different component.

Glyph outlines are © 2019–2021 Antonis Tsolomitis, from New Computer Modern,
under the GUST Font License. The licence is permissive, but lifting outlines
into standalone artwork is a derivative use — worth a glance before v1 ships.

If the icon set grows past about five, add the extraction as a script rather
than re-deriving the transform each time. For two, hand-placed is correct.

### Contrast

Computed against the real surfaces, not pure white — no surface in this design
is `#ffffff`. `--color-text-secondary` is AA on the page ground (4.84:1) and
**fails on every coloured fill** (3.56–4.17:1). It is not used on a rank chip
today and must not be. `--color-border` is 1.35:1: fine for a rule, not
sufficient for an input boundary, which needs 3:1 under WCAG 1.4.11.

## Components

`src/lib/components/`. Two interaction classes, and which one a row belongs to
is an accessibility decision rather than a styling one (handoff §10):

| Class | Element | Components | Worked example |
|---|---|---|---|
| Navigates | `<a href>` | `HazardRow`, `CategoryRow`, `CdtaCard` | `HazardRow.svelte` |
| Toggles | `<button aria-pressed>` | `ResourceRow`, `LayerRow` | `ResourceRow.svelte` |

Every row in both classes is **48px** — 16px padding around a 16px leading
element, or 12px around a 24px chip — clearing WCAG 2.5.5's 44px minimum.

Each worked example carries the full reasoning; the others follow it and do not
repeat it.

`CategoryRow` navigates to the map carrying its own category, which is §5's
rule that the originating page writes the state into the link:
`/q14/map?categories=food-assistance`.

**`ResourceRow` renders a category, not a resource.** The Figma component is
named "Resource Row" and every instance in the map sheet is a category and its
count — "Children and youth 261", "Libraries and community 69". Kept under the
Figma name so design and code still grep to each other. It is the same
classification `CategoryRow` shows, in the sheet's visual language.

Toggling writes the selection back into the URL rather than into local state,
because the URL *is* the state. `replaceState` so twelve taps do not leave
twelve history entries; `keepFocus` and `noScroll` so the tapped row stays put
and keeps focus.

### The hazard screen

**The district override is fetched *instead of* the base, not merged with it.**
`DATA_CONTRACT.md` §6 says the override "replaces whole top-level keys … it is
not a deep merge", which reads like the frontend has merging to do. It does
not: the emitted file is already self-contained. Verified against the real
file — `slug`, `label`, `jra_category` and `summary` are byte-identical to the
base's, and `meta.overridden` lists only `sections` and `map_layers` as
replaced. One fetch either way, no client-side merge to get wrong.

Only `q14` / `coastal-storm` has one today, and it is what gives that page its
fourth section ("Leaving the peninsula") and its two map layers where every
other district's coastal-storm page is a stub with none.

**`conditions.json` is fetched only where a section declares it** — one hazard,
`infectious-disease`. It is 2 KB, but fetching it unconditionally would inline
it into all 112 hazard pages for the 14 that use it.

#### `default_resource_categories` does not exist

`DATA_CONTRACT.md` §6 documents it on **all 8** hazard files, with an example
of `array[5]`, and §5 has the resource-map button carry it as `?categories=`.

It is absent from all 8 emitted files, absent from every `content/hazards/*.yml`,
absent from `R/` and `scripts/`, and absent from **every committed version of
`data/processed/hazards/`** — checked back through four pipeline commits. The
contract claims to read field lists off real outputs, so either it was
generated against an uncommitted state or that table is partly authored.

The button therefore carries `?layers=` and `?hazard=` only, and the map opens
on its default of every category showing. This also makes the handoff's open
question 1 — "children-and-youth is in no hazard's `default_resource_categories`"
— moot until the field exists.

#### The 2026-09-25 revision

Both hazard frames were re-cut (`40:200` Extreme Heat, `58:403` Heavy Rain),
and `13:839` was updated to mirror the section-title change. What moved:

| | Before | After |
|---|---|---|
| Measure line | rendered on every page | **gone** |
| Summary paragraph | rendered where present | **gone** |
| Map button | a sibling on the route, solid `#707070` | inside `HazardHeader`, sunken `#f5f7f9` card |
| Rules | none on the page at all | after the back link, after the header, between titled sections |
| Section title | 14px | **16px** (`--font-size-section`, new token) |
| `.screen` gap | 12px | 4px |
| Gap between elements in a group | **48px** | 24px |

**The measure was a duplicate.** `measureLine()` produces both `HazardRow`'s
subtitle on the district screen and what was this page's first paragraph, in
the same size and the same grey — so arriving from a district row showed the
identical sentence twice, one tap apart. `measureLine()` itself stays;
`HazardRow` still uses it.

**`content.summary` now renders nowhere.** It is still emitted, still on
`HazardContent`, and four hazards carry one (coastal-storm, hazmat,
infectious-disease, mass-casualty). Neither revised frame draws it. Recorded
here rather than quietly dropped: either a frame should place it or the
pipeline should stop emitting it.

**The 48px gap was double-counted spacing.** `NestedContainer`'s slot set
`gap: 24px` *and* every `HazardElement` padded itself 12px all round, so
siblings sat 48px apart — and `PhoneElement`, which had no padding at all, sat
24px apart and 12px further left in the same group. Now the padding owns the
rhythm alone (slot gap 0, every child `padding-block: 12px`), which is what
`.items` on the route already assumed. Measured on the built page: 24px between
all three groups' children on Extreme Heat, every child at the same left edge.

**Who owns the horizontal inset.** The frames are consistent once you read
them as "whatever sits directly on the page supplies 12px, and nothing nested
repeats it" — the same `NestedContainer` is drawn `p-12px` at page level
(`61:638`) and `py` only inside a Section (`58:413`). So `.untitled` and
`Section` supply it, and `HazardElement`, `PhoneElement` and `NestedContainer`
are all `padding-block` only. Without this the bare "Practice safe outdoor
activities" note sat 12px left of the group labels beside it.

**Two deltas taken deliberately:**

- `Section` keeps its 10px padding, the district frames' literal; the hazard
  frames draw 12px. Costs the hazard screen 2px a side and keeps screen 02
  untouched.
- `HazardHeader` loses its 8px horizontal inset, per the frame. That is also
  what puts the header's rule and the route's section rules on one line — both
  land 26px from the viewport edge (16px gutter + `HorizontalRule`'s own 10px);
  keeping the 8px would have put two rules on one page at different insets.
  Consequences: the hazard `<h1>` sits 8px left of the district and resource
  `<h1>`s, and **screen 04 moves with it**, since the map screen renders the
  same component. One line to revert.

`mapHref` is optional for that reason — omitted, the rule and the button go
with it, which is the map screen's header.

#### One piece still has no design

`ConditionsPanel` follows the **Conditions** component (node 14:1142), which
appears in none of the five screens. A 24px fill holding an arrow, beside a
sentence and the numbers, with three `direction` variants:

| `direction` | Fill | Figma variable |
|---|---|---|
| up | `#f2d4d0` | `color/red/200` — same hex as `severity/extreme/fill` |
| down | `#a0f3af` | `color/green/200` — the only new value |
| flat | `#d7dce4` | `color/grey/200` — same hex as `border/default` |

The two duplicates are kept as **separate tokens** rather than aliased: they
are separate variables in Figma that happen to hold the same value today, and
aliasing would silently propagate a change to one into the other.

Colour is the third channel, not the first — the sentence says "are
increasing" and the arrow's shape differs, so §10's rule that colour is never
the only carrier holds.

Two departures from the frame, both forced by the contract:

- **Geography is in the first line.** The frame's copy carries no geography at
  all, but this renders on a district-scoped page from a citywide figure, and
  the contract calls `geography_label` "the string that stops a citywide figure
  reading as local". Composing the sentence as "*&lt;metric&gt; in
  &lt;geography_label&gt; are &lt;direction&gt;*" satisfies that inside the
  design's own sentence shape rather than bolting a line on.
- **The metric name comes from the payload.** The frame hardcodes "Respiratory
  illness emergency department visits"; the data has two metrics, "Respiratory
  illness visits" and "…hospitalizations", and both render.

`trend` is not shown, and the contract's warning about it does not apply: it
warns specifically against pairing `direction` with a sparkline, and there is
no sparkline. `series` carries the 12 points if a later design wants one.

**"Last week" is correct.** The contract describes `direction` as change over
"the last two weeks", which reads like `previous` is a fortnight back. It is
not — `previous` equals `series[length - 2].value` on both metrics, dated
exactly seven days before `value`. Verified against the real file.

**`series` is `{date, value}[]`, not `number[]`.** The contract says
"array[12]" without giving the element shape.

### Hazard content

Four item shapes, three components, and a small dispatcher:

| Shape | Carries | Component |
|---|---|---|
| Link | `label` + `url` | `HazardElement` |
| Note | `label` + `note: true` | `HazardElement` |
| Phone | `label` + `tel`, optional `tty` | `PhoneElement` |
| Group | `label` + `items` | `NestedContainer` |

`HazardItem.svelte` picks between them. It is not a Figma component — it is the
glue the hazard screen needs, and the only place that knows the mapping. A
Group is checked first because `items` is what makes the dispatch recursive.

**Sections are skipped when they have no `items` and no `body`** (§7.6). Test
on emptiness, never on `status === 'stub'` — status is *absent* on the two
authored hazards, so testing the string treats authored content as a stub.
Both keys always exist and one is always empty.

**`HazardElement`'s header is a two-part row, and the payload now fills both.**
Figma draws a wrapping space-between row with a bold label *and* a separate
blue link — "Apply for a free air conditioner" beside "Home Energy Assistance
Program (HEAP)". That slot went unused when a Link item was `label` + `url` and
nothing else; `link_label` was added to the item schema on 2026-09-23 to fill
it (`R/content.R`, optional, and an error without a `url`). All six link items
on Extreme Heat carry one.

The 20px between the two halves is the frame's "min-gap spacer" (`60:88`), a
20×5px invisible node — Figma's way of writing a minimum column gap. It is
transcribed as `gap: var(--space-300) 20px`, not as an element.

**The whole element is the anchor, not just the blue text.** In the frame only
the destination name is styled as a link, which at 14px is about a 17px tap
target, under the 44px every row component in this app was fixed to. The blue
and the underline stay, because they are the only cue naming where the block
goes. Accessible name: `"Get personalized flood guidance, Blue Dots"`.

**Phone links carry their own context.** §10 requires it — "a screen reader
announces two phone numbers with no way to tell them apart". Verified from the
accessibility tree: `"Con Edison phone, 1-800-752-6633"` and
`"Con Edison TTY, 1-800-642-2308"`. Numbers dial as E.164 (`tel:+18007526633`).

### ResourceHeader — the back link returns to the map

The back link points at `/q{NN}/map`, not the district page, and reopens the
view the resource was tapped in:

```
/q14/map?categories=food-assistance&resource=franc%3Athe-campaign-…
```

Built by `mapReturnPath()` in `$lib/resources` — the inverse of `detailPath()`,
and it lives beside it so the two stay in step. Both parameters are §5's, used
exactly as the map page reads them: `?categories=` narrows the visible points to
the one that was tapped, `?resource=` is §7.4's permalink and reopens the popup.
`URLSearchParams` does the encoding, because `resource_id` carries a colon that
must arrive as `%3A`.

**Derived from the record, not round-tripped.** The alternative was to carry the
map's live query string through the popup's detail link and read it back, which
would preserve a wider selection and any `?layers=`/`?hazard=`. Rejected on two
grounds:

- It needs this derivation as a fallback anyway. **The popup is the only route
  into a resource page** — nothing else in the app calls `detailPath()` — so
  every other arrival is a shared or bookmarked link with no state to
  round-trip, and a back link that behaves one way from the map and another
  from a link is worse than one that always behaves the same.
- The page is prerendered. Derived, the href is static and correct in the built
  HTML; round-tripped, it could only resolve on hydration, so the no-JS and
  pre-hydration answer would be a *different destination*.

The label stays the district name — it names where you are going back to, and
the map is district-scoped, so "The Rockaways" is true of both.

The href is passed in rather than built by the component, so the destination is
visible at the call site instead of buried in a header.

### ResourceCard

Rows are assembled from the record, not passed as eight booleans — an empty
value drops out. QNPD and FRANC only; the mount is guarded by `hasDetail`,
because a FacDB record has an `address` and would otherwise render a one-row
card on a page it has no detail view for.

- **Referrals only when it is not "Yes"** (§7.5) — 164 of 168 say "Yes", so a
  row saying so on nearly every page is noise; the 4 that say "No" are the ones
  worth a line. Figma's mock shows "Accepts Referrals: Yes", which is the
  contradiction; the behavioural rule wins over one illustrative instance.
- **Fees is free text, verbatim** — "None", "Yes", "$40 registration fee".
- **The whole card can vanish.** FRANC records carry only `mission`, and only
  67 of 79 have one, so **12 of the 248** detail records produce no rows. The
  component renders nothing rather than an empty bordered box.

#### Contact details are actionable

**A departure from the frame.** Figma draws the resource screen's phone, email
and website as plain black text. On a phone, in an emergency, a number you
cannot tap is a usability failure — and the app already establishes the
opposite: §7.6's `PhoneElement` renders hazard phone numbers as `tel:` links in
blue. This applies the same treatment to a resource's own contact details
rather than inventing one.

**Each one degrades to plain text where the value cannot be trusted**, because
the data is not uniformly clean and a link that dials the wrong number is worse
than text:

| Field | Linked | Left as text | Why |
|---|---|---|---|
| phone | 161 | 6 | one value is `855.322.4357/718.657.6195`; five have 13 digits (an extension or a country code), and dialling the first ten would be a guess |
| email | 166 | 3 | `Imanansob@gmail.com/ Info@Ansob.org` |
| website | 162 | 1 | `"133-33 Brookville Blvd. LL5,"` — **a street address in the website field** |

That last one is the guard earning its place: without it the page would have
offered a link to `https://133-33 Brookville Blvd. LL5,`.

Counts verified against the built pages — 161 `tel:`, 166 `mailto:`, 162
website links across the 248, and 12 pages with no card at all.

#### 27 missions contain literal `<br>`

`"Fridays 9:30AM-<br>10:30AM"`, `"Food Distribution: 1st & 3rd Thursday<br>…"`.
It is the only markup anywhere in `data/processed/` — no other resource field,
no gap sentence, no hazard content. Svelte escapes by default, so untouched
these render a visible `<br>` mid-sentence.

`plainText()` converts **only** `<br>` to a newline, which the row's
`white-space: pre-line` then renders; everything else stays escaped, so any
other tag appearing later shows up literally — visible and reportable rather
than silently executed. `{@html}` was the alternative and would have opened
every record to a field sourced from a scrape.

This is a workaround. `mission` is documented as a string and should not carry
markup; the fix belongs in the pipeline.

### GapSentence

**The component contains no copy, and that is the feature.** The pipeline emits
`sentence_template` plus `facts` and `$lib/gaps` interpolates by name — never by
position, never against a fixed key set. Eight placeholder names appear across
the 42 sentences shipped today and that list is not a contract.

`{district}` resolves from `facts.district`, not from the payload root.

There is **no branch on `value`** anywhere: where a gap found nothing or an
estimate is unreliable, the pipeline has already swapped in different wording.
A zero check here would double up on a decision made upstream with more
information. A missing placeholder throws rather than rendering a literal
`{pct}` — every page is prerendered, so that fails the build, not a visitor.

`fallback_from` is handled but **has never rendered**: absent on all 42
sentences across all 14 districts. The copy is undesigned and marked as such.

### Popup

**It needs a three-legged join.** The map feature carries only `resource_id`,
`name`, `category`, `source` and `is_coad_member`:

| Field | From |
|---|---|
| `address`, `operator` | `resources/<slug>.json`, on `resource_id` |
| the category *label* | the district payload's `resource_categories`, on the slug |

`resources/<slug>.json` is fetched **in the browser**, not in a load — the third
data-loading shape in this app. A universal load would inline 194 KB of escaped
JSON into each of 14 map pages for a file not needed until a popup opens; a
server load could slice it, but every feature's popup joins against the whole
list, so slicing defeats the purpose. The map needs JS regardless.

**Layout: a column.** Node `77:1708` was re-cut on 2026-09-25 and the detail
link moved from the right of the three lines to below them:

```
flex-direction: column        gap: 16px (space/400)   between lines and link
  .lines                      gap:  8px               between name/category/address
  .detail                     left-aligned under the address
```

Measured against the built CSS: `280px` wide, `column`, `16px` and `8px`. The
lines block is `align-self: stretch` — Figma's text nodes are `w-full`, which
fell out of the row layout for free but makes a column hug its longest word.

That move put the close control over the **name** instead of the detail link,
so `.lines` reserves `16px` on the right. The glyph's ink measures x 252.6–261.4
inside a 280px box; the longest wrapping name reaches 242.1, so there is 10.5px
of clearance. The 44px hit area still overhangs, which is the point of it.

Four deviations from the frame, each deliberate:

- **Three booleans in Figma, two here.** `hasAddress` and `hasDetail` are real.
  `hasOperator` is not: the subtitle is never empty, because `category` is on
  all 3,795 records, so the fallback always resolves. §7.4 says explicitly that
  this is why there is no boolean for it.
- **Link text.** Figma draws "More information", which is the exact string §10
  gives as its example of link text that says nothing out of context. §7.4's
  wording is used instead — "Contact and services" for QNPD, "About this
  resource" for FRANC — with the resource name appended in the accessible name.
  Verified from the accessibility tree: `"Contact and services, Her Care Inc"`.
- **Translucency is on the background, not the element.** Figma sets
  `opacity: .95` on the frame, which fades the text too. This sits over map
  imagery, and §10 already flags that "the composite is what matters" — fading
  the text makes its contrast a function of whatever tiles are underneath.
  `background: rgb(254 252 250 / 0.95)` keeps the look and the legibility.
  Revert to element opacity for literal fidelity.
- **A close control.** §10 requires a visible one — tapping the map is not
  enough and Escape is not reachable by touch. Figma draws none, so this is a
  44px hit area over a glyph, and it is the one piece of the popup that is not
  from the design.

#### The subtitle rule, measured

Operator where it differs from the name, category label otherwise — compared
case- and punctuation-insensitively with a substring test **in both
directions**, because the operator is sometimes a prefix of the name and
sometimes the reverse.

| | Handoff §7.4 | Actual |
|---|---|---|
| records | 3,905 | **3,795** |
| with an operator | 3,551 | **3,441** |
| suppressed by the rule | 1,989 | **1,888** |
| subtitle shows the operator | 1,562 | **1,553** |
| subtitle shows the category | 2,343 | **2,242** |
| operator repeats the name outright | 48% | **40%** |

The rule is right; §7.4's counts are one data refresh stale. `DATA_CONTRACT.md`
§4's 3,795 is the current figure. What the rule keeps is the informative half —
*Socrates Sculpture Park* under NYC Department of Parks and Recreation,
*P.S. 2 Alfred Zimberg* under Hanac Inc.

## The map

MapLibre GL JS, mounted client-only — a prerendered page has no DOM and no
WebGL context, so `Map.svelte` renders behind a `browser` guard.

**Set up once, mutate after.** Every source and layer is added on `load` and
hidden; `?layers=` only flips `visibility`. Re-creating the map on a toggle
would throw away the user's pan and zoom, and re-adding a source would
re-download its archive — 5.9 MB for the moderate stormwater layer alone.

The district frames itself from `bbox`, which is on `districts.json` (§2) and
**not** on the district payload (§3). The map route's server load already parses
`districts.json` for `entries()`, so the entry rides along in the page rather
than costing a second fetch.

`cdta.geojson` carries `promoteId: "cdta2020"` per §9, so `setFeatureState` can
push attributes without a per-feature lookup when the choropleth layers land.

### The bottom sheet

Lifted from d26's `Sidebar.svelte`, which §3 says is worth taking rather than
rebuilding. Both of the findings it names are carried over and marked in the
source:

1. **The sheet's live height is published as `--sheet-height` on `:root`** by a
   `ResizeObserver`. The map's controls and the popup have to sit above the
   sheet's top edge as it moves, including mid-transition — a media query
   cannot know where the edge is, and reading it per frame from the map would
   couple the two components.
2. **The reserved scrollbar gutter is measured at runtime.**
   `scrollbar-gutter: stable` stops the panel's width changing the moment a
   scrollbar appears; the compensating right-padding then needs the *actual*
   reserved width, which is 0 on overlay-scrollbar systems, ~15px with classic
   ones, and differs by input device on macOS. A hardcoded guess is wrong for
   whichever kind the device is not.

Drag to resize with a snap to peek or expanded on release, and — §10 — a
non-gesture path: the handle is a real `<button>` with `aria-expanded` that
toggles on tap and on Enter/Space. Swipe alone is insufficient. The transition
respects `prefers-reduced-motion`.

Measured: peek 123px, expanded 608px, `--sheet-height` tracking both.

### The map screen is one viewport, exactly

`.screen` is a flex column of `100svh`; the header is fixed-size and the stage
takes the rest. The stage was first written as `100svh` *below* the header,
which overflowed by the header's height and pushed the sheet off the bottom of
the screen — visible only in a screenshot, since nothing errored.

### Tabs

Real tabs, not styled buttons (§10): `role="tablist"`, `aria-selected`,
`aria-controls`, and arrow-key navigation with `tabindex="-1"` on the inactive
tab so Tab steps past the whole tablist in one press. Active is bold **and**
underlined — weight alone is not a reliable cue at 12px.

The active tab is local state, not a URL parameter: §5 names four parameters
and this is not one of them. It is a view preference, not something a shared
link should pin.

### The popup join, from a map click

The feature carries only `resource_id`, `name`, `category`, `source` and
`is_coad_member`. Clicking a point writes `?resource=` — the same permalink
§7.4 names — and the page resolves the rest: `address` and `operator` from
`resources/<slug>.json`, the category *label* from the district payload.

Verified end to end by dispatching real clicks across the canvas until one hit
a point: `?resource=facdb:e0fca2e0…` → "Richard Mott House" / "Parks and
environment" / "Far Rockaway, 11691". The address and the label are both
joined, neither is on the feature.

### The basemap is the only third-party runtime dependency

CARTO Positron, as d26 uses, fetched from `basemaps.cartocdn.com` on every map
load. Everything else — every payload, both PMTiles archives, the fonts — is
same-origin from Pages.

Worth being explicit about, for an emergency-preparedness tool: if CARTO is
down or blocked, the map renders with no streets, though the overlays and
district outline still draw because they are ours. It is also a third party
observing requests.

Neither the 04 Map frames nor the entry picker draw a street basemap, so "no
basemap" is a defensible reading of the design — and would make it much harder
to tell where a cooling centre actually is. The fix that keeps both is a
self-hosted **Protomaps** basemap: one `.pmtiles` file in `data/processed/`,
served through the protocol already registered for the stormwater layers. That
is a pipeline change, so it is flagged rather than done.

`src/lib/map/basemap.ts` is the single constant either way.

### Overlays

Four, the same four `listableLayers()` returns — the available `context` layers
with discrete geometry. Colours match the LayerRow swatches, so the key in the
sheet is the colour on the map. Hardcoded in `overlays.ts` rather than read
from a token: MapLibre paint properties are evaluated on a canvas and cannot
resolve a CSS custom property.

| Layer | Source | Draws |
|---|---|---|
| `stormwater_limited_1_77` | PMTiles | fill, opacity stepped by `Flooding_C` |
| `stormwater_moderate_2_13` | PMTiles | same |
| `hurricane_evac_zones` | GeoJSON | fill + outline |
| `surge_current` | GeoJSON | fill + outline |

`Flooding_C` takes two values — 1 is nuisance flooding, 2 is deep and
contiguous — so deep water draws at a higher opacity. The two GeoJSON polygon
layers get an outline as well as a fill because their **edge** is the
information: which zone you are in, where the surge stops.

Verified in a browser: PMTiles served **`206 Partial Content`** (range requests
are not optional for PMTiles), overlays render with `?layers=` and vanish
without it, no console errors.

One note for anyone debugging this: **MapLibre fetches GeoJSON in a worker**,
so those requests do not appear in CDP's page-level Network capture. Their
absence is not evidence they failed — the rendered canvas is.

### Map layers

`data/registry/map_layers.csv` is the catalogue and the vocabulary for hazard
content's `map_layers` — but **it is not in `data/processed/`**, so the browser
has no runtime source for layer labels or their available/blocked status.
`src/lib/server/registry.ts` reads the committed CSV at build time instead and
the available rows are serialised into the page.

That keeps one copy of the list. Hardcoding ten labels in TypeScript would be
the hand-maintained table that drifts, silently, the first time a layer is
retired. **The better fix is for the pipeline to emit the registry as
`data/processed/layers.json`** — that is a pipeline change and CI owns
`data/processed`, so it is flagged rather than done here. It would also let the
map show blocked layers as "not available yet" instead of omitting them.

Of the 10 available layers, the Layers tab currently lists **4**:

| Excluded | Count | Why |
|---|---|---|
| `kind: resource` | 3 | `cooling_centers`, `evacuation_centers`, `resources` are point layers driven by the Resources tab's categories. Listing them in both tabs would give one thing two switches. |
| `delivery: inline` choropleths | 3 | `hvi_choropleth`, `chem_businesses`, `pivi_choropleth` are graduated fills joined to `cdta.geojson`. A flat 16px swatch is the wrong legend for a ramp, and **no ramp legend is designed** — so they are omitted rather than given an invented colour. |

The four swatch colours are read off the Figma LayerRow instances:
`stormwater_limited_1_77` `#9bbde9`, `stormwater_moderate_2_13` `#3f6bb9`,
`hurricane_evac_zones` `#ebaa7d`, `surge_current` `#d8b663`. Those are exactly
the available context layers with discrete geometry, which is not a coincidence.

Two things to settle:

- **Labels differ between the registry and Figma.** Registry: "Stormwater
  flooding (limited rain)". Figma: "Stormwater Flooding (Limited)". The
  registry is used, being the vocabulary the pipeline asserts against.
- **`?layers=` absent means *none on*.** Absent means default for both
  parameters (§5), but the defaults differ: everything for categories, nothing
  for overlays — a bare map stacking storm surge over two stormwater layers
  over evacuation zones is unreadable, and §5's own example has the hazard page
  supply `?layers=`. §5 says a bare `/q14/map` "has one fixed default" without
  naming it, so this is a reading rather than a quotation.

### The toggle off state

Figma expresses it as a boolean visibility property on `ResourceRow` and
`LayerRow`. The effect is **weight and colour across the whole row** — label,
count, mark and the mark's border together:

| | Weight | Colour |
|---|---|---|
| On | 611 | `#0a0a0a` |
| Off | 433 | `#707070` |

`currentColor` on the mark's border means one declaration moves all four.

Neither weight nor colour is programmatically detectable, which is exactly why
§10 makes `aria-pressed` mandatory here rather than optional.

`#707070` measures **4.84:1** on `--color-surface` — it passes AA for text under
24px, but it is thinner than the palette was checked at and will not hold where
the sheet is translucent over map imagery. Being addressed separately; Figma's
behaviour is kept as-is for now.

LayerRow's coloured swatches are *not* states — they are the layers' own map
colours, a legend key. Its boolean property **dims the swatch to 35%** rather
than recolouring it, so an off row still reads as that layer; the label takes
the same weight-and-colour change as `ResourceRow`.

Every LayerRow instance in the frames is drawn `visible: true`, so the label
half of that is inherited from the sibling component rather than read off an
off-state instance.

The swatch carries a `0.75px` **inset** hairline. `#9bbde9` against
`--color-surface` is far below the 3:1 that WCAG 1.4.11 wants for a UI
component, and without it the palest layer's key disappears into the sheet.
Inset so it dims with the swatch, rather than outlining a faded square.

## Screens

`01 Entry` and `02 District` are built. The district screen is complete. **The
entry screen deliberately omits three of the frame's elements**, all of which
belong to finding your district by *location* rather than by name:

| Omitted | Why |
|---|---|
| `AlertBanner` | Never renders in v1 (§7.7) — no endpoint, no poller, and §7.7 says not to reserve layout space. `ALERTS_SERVICE.md` is the brief. |
| Map picker | Named "MapPlaceholder" in the frame too. Needs MapLibre, `cdta.geojson` and the PMTiles protocol — build step 8. |
| Address field, "Use my location" | The field needs a geocoder, which neither the pipeline nor the contract provides. The button needs the Geolocation API plus point-in-polygon against `cdta.geojson`, which arrives with the map. |

The 14 cards are a complete picker on their own. Three dead controls above them
would promise what the build cannot do, which is worse than a shorter screen.

When they land, note that Figma draws the address field's border in `#707070`
at 4.84:1 — not `--color-border` at 1.35:1 — so it already clears the 3:1
WCAG 1.4.11 needs for an input boundary. The placeholder is the only label in
the frame, so it will need a visually-hidden `<label>`: a placeholder
disappears on first keystroke.

### Blocks render ~11px taller than the frame

Figma applies `text-box-trim: trim-both` with `text-box-edge: cap alphabetic`
to its text, which crops each line box to the cap height. CSS uses the full
line box by default, leading included, so any block whose height is
content-driven comes out taller — a `CdtaCard` measures **63px against the
frame's 52px**, roughly 5.5px per line of trimmed leading.

Where Figma sets an explicit height or min-height this does not arise, and
those components match exactly — `CategoryRow` is 46.7px against a drawn
46.67px.

`text-box-trim` is the real fix and would match the frame everywhere, at the
cost of a baseline of Chrome 133 / Safari 18.4. Older browsers degrade to
what the build does today. Not applied unilaterally — it changes every
vertical rhythm in the app.

### Two notes on fidelity

**Three corner radii, one token.** `radius/sm` (2px) on the rank chip and the
mark box, `space/100` (4px) on CategoryRow — a spacing value borrowed as a
radius — and a bare `3px` on CdtaCard with no variable behind it at all.
Transcribed as drawn rather than normalised.

**The Figma sheet mocks 13 categories; the pipeline produces 12.** "Education
and jobs" appears in the map-sheet frame and in no district payload, and the
mock's counts are illustrative (261 against q14's real 134). The components
derive from the payload, per §6's "do not hardcode the list", so this is mock
drift rather than a defect — worth knowing before comparing a screen to the
frame.

### Query parameters are client-side, always

SvelteKit refuses `url.searchParams` in a `load` on a prerendered page:

```
Error: Cannot access url.searchParams on a page with prerendering enabled
```

It is right to. The page is built once with no query string in existence, so
whatever a load read would be baked into the HTML that every combination then
receives. **All four of §5's map parameters — `categories`, `layers`, `hazard`,
`resource` — are read in the component, guarded by `browser` from
`$app/environment`.**

That is the correct split for a static site rather than a workaround: the
prerendered HTML is the default view, the shared link still renders a real page
without JS, and the state it carries is layered on at hydration. `null` and `[]`
stay distinct — absent means default, an unrecognised id is dropped rather than
fatal.

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
