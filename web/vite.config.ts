import { sveltekit } from '@sveltejs/kit/vite';
import { defineConfig } from 'vitest/config';

export default defineConfig({
  plugins: [sveltekit()],

  // Vitest reads this same config, so $lib and import.meta.env resolve in
  // tests exactly as in the app. Unit tests live beside the module they test.
  // No DOM environment: nothing tested so far renders.
  test: {
    include: ['src/**/*.test.ts']
  }

  // No publicDir override. SvelteKit owns `static/`, and `static/data` is a
  // symlink to ../../data/processed — see web/README.md for why, and
  // scripts/check-data.mjs for the guard that fires when it is missing.
  //
  // No `define` for the data version either: Vite already exposes any
  // VITE_-prefixed environment variable on import.meta.env, and CI sets
  // VITE_DATA_VERSION to the commit SHA. src/lib/data.ts is the only place
  // that reads it.
});
