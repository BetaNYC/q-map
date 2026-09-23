import adapter from '@sveltejs/adapter-static';
import { vitePreprocess } from '@sveltejs/vite-plugin-svelte';

/** @type {import('@sveltejs/kit').Config} */
export default {
  // Svelte 5. vitePreprocess enables <script lang="ts"> in components.
  preprocess: vitePreprocess(),

  kit: {
    // adapter-static writes one HTML file per prerendered route. `strict: true`
    // is the default and is what we want: it fails the build if any route is
    // NOT prerenderable, rather than silently omitting it. With 389 routes and
    // no server, a route that quietly failed to prerender is a 404 in
    // production that nothing catches.
    adapter: adapter(),

    paths: {
      // GitHub Pages project site: https://betanyc.github.io/q-map/ — so every
      // URL sits under /q-map/. Set once, here; never hardcoded in a component.
      //
      // Read from the environment so a future custom domain is a one-line
      // change (BASE_PATH='') rather than a find-and-replace. Unused today —
      // no custom domain is planned.
      //
      // NOTE this is deliberately NOT d26's `base: './'`. d26 is a single HTML
      // file at the root, where a relative data path has exactly one meaning.
      // q-map has 389 HTML files at four depths, and './data/x.json' resolves
      // differently on /q-map/q14/ than on /q-map/q14/resource/qnpd/her-care-inc/.
      base: process.env.BASE_PATH ?? '/q-map'
    },

    prerender: {
      // A dead internal link should fail the build, not ship. The route set is
      // closed and enumerable, so there is no legitimate reason for one.
      handleHttpError: 'fail',

      // Prerendering visits every entry and follows the links it finds. Routes
      // with parameters additionally export `entries()` (see
      // src/routes/[district]/+page.server.ts) so the set is generated from
      // districts.json rather than hand-maintained.
      entries: ['*']
    }
  }
};
