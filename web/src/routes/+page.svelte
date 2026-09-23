<script lang="ts">
  import { base } from '$app/paths';

  let { data } = $props();
</script>

<!-- SCAFFOLD ONLY. The entry screen — alert banner, map picker, address input,
     14 CDTA cards — is built in step 5 from the Figma frames. What is here
     exists to prove the data path end to end and to give the prerenderer links
     to crawl. No layout is being invented. -->

<h1>Queens Resource Map</h1>
<p>{data.queens.length} Queens districts of {data.all.length} citywide.</p>

<ul>
  {#each data.queens as district (district.slug)}
    <li>
      <!-- District cards navigate, so they are <a href>, never buttons
           (handoff §10) — middle-click and open-in-new-tab have to work.
           The href is built from the STORED slug; it is never derived from
           cdta2020, so a published link cannot drift. -->
      <a href="{base}/{district.slug}">
        {district.display_name} — {district.cd_label}
      </a>
    </li>
  {/each}
</ul>
