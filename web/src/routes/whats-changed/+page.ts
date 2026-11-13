// The What's changed page (BetaNYC's What's changed standard).
//
// csr = false: the page ships as plain prerendered HTML and every link to it is a
// full page load, so the filter script inside the generated fragment runs. A script
// added through {@html} during client-side navigation would not run. With no client
// JS the root layout leaves out the docked map, which needs the client (see
// +layout.svelte, `noClient`), and the alerts banner, which polls from the client.
export const prerender = true;
export const csr = false;
