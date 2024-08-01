<script lang="ts">
  import "../index.scss";
  import { podcastStore } from "../stores/PodcastStore";

  $: podcasts = $podcastStore;
</script>

<main>
  {#if podcasts !== undefined}
    {#each podcasts as podcast}
      <div>
        <h2>{podcast.title}</h2>
        <p>{podcast.description}</p>
      </div>
    {/each}
  {/if}
</main>
