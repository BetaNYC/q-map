// Prerender everything. Declared once at the root so it is inherited by every
// route rather than repeated 389 times; a route that needs to opt out says so
// locally, and none does.
//
// Paired with adapter-static's `strict: true` (svelte.config.js), this means a
// route that cannot be prerendered fails the build instead of quietly becoming
// a 404 in production.
export const prerender = true;

// No client-side router state to hydrate on the server beyond the page payload,
// and every page is static — but SSR must stay on, because prerendering IS
// server rendering. Stated explicitly so nobody turns it off looking for a
// "static site" switch.
export const ssr = true;
