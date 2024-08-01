import { writable } from "svelte/store";
import { Podcast } from "../../../declarations/ic-rss-backend/ic-rss-backend.did";
import { backend } from "$lib/canisters";


export const podcastStore = (() => {
    const { subscribe, set } = writable<Podcast[] | undefined>();
    const refetch = async () => {

        let podcasts = await backend.get_podcasts();
        set(podcasts);
    };


    refetch();

    return {
        refetch,
        subscribe,
    };
})();


