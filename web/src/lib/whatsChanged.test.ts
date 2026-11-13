import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { describe, expect, it } from 'vitest';
import * as route from '../routes/whats-changed/+page';

/**
 * The What's changed page (BetaNYC's What's changed standard). The fragment is
 * generated from WHATS-CHANGED.md; CI's whats-changed workflow checks it is
 * current. These pin the parts a later edit could quietly break.
 */
const root = process.cwd();
const read = (p: string) => readFileSync(join(root, p), 'utf8');

describe("What's changed page", () => {
  it('ships as plain HTML so the fragment script runs', () => {
    expect(route.prerender).toBe(true);
    expect(route.csr).toBe(false);
  });

  it('uses a fragment without its own h1 (PageHeader supplies it)', () => {
    const fragment = read('src/lib/whats-changed.html');
    expect(fragment).toContain('data-whats-changed');
    expect(fragment).not.toMatch(/<h1[\s>]/);
    expect(read('src/routes/whats-changed/+page.svelte')).toContain('title="What\'s changed"');
  });

  it('is linked from the home page with a full page load', () => {
    expect(read('src/routes/+page.svelte')).toMatch(
      /<a href="\{base\}\/whats-changed" data-sveltekit-reload>/
    );
  });

  it('gives the page a skip link to <main>', () => {
    const layout = read('src/routes/+layout.svelte');
    expect(layout).toMatch(/\{#if noClient\}\s*<a class="skip" href="#main">/);
    expect(layout).toContain("<main id={noClient ? 'main' : undefined}>");
  });

  it('leaves the docked map out of the no-client route', () => {
    const layout = read('src/routes/+layout.svelte');
    expect(layout).toContain("page.route.id === '/whats-changed'");
    expect(layout).toContain('{#if !noClient}');
  });
});
