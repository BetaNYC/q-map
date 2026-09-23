import { sveltekit } from '@sveltejs/kit/vite';
import { defineConfig } from 'vite';

export default defineConfig({
  plugins: [sveltekit()]

  // No publicDir override. SvelteKit owns `static/`, and `static/data` is a
  // symlink to ../../data/processed — see web/README.md for why, and
  // scripts/check-data.mjs for the guard that fires when it is missing.
  //
  // No `define` for the data version either: Vite already exposes any
  // VITE_-prefixed environment variable on import.meta.env, and CI sets
  // VITE_DATA_VERSION to the commit SHA. src/lib/data.ts is the only place
  // that reads it.
});
