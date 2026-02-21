import type { Track } from "@/types/track";

const clientId = import.meta.env.SPOTIFY_CLIENT_ID ?? "";
const clientSecret = import.meta.env.SPOTIFY_CLIENT_SECRET ?? "";
const playlistIDs = (import.meta.env.SPOTIFY_PLAYLIST_IDS?.split(",") ?? []) as string[];

export async function connectSpotify(): Promise<string> {
	const base64Auth = Buffer.from(`${clientId}:${clientSecret}`).toString("base64");

	const res = await fetch("https://accounts.spotify.com/api/token", {
		method: "POST",
		headers: {
			Authorization: `Basic ${base64Auth}`,
			"Content-Type": "application/x-www-form-urlencoded",
		},
		body: "grant_type=client_credentials",
	});

	if (res.status !== 200) {
		throw new Error(`Failed to connect to Spotify: ${res.statusText}`);
	}

	const { access_token } = await res.json();
	return access_token;
}

export async function searchSong(song: string, accessToken: string) {
	const query = encodeURIComponent(song);
	const url = `https://api.spotify.com/v1/search?q=track%3A${query}&type=track&include_external=true`;

	const res = await fetch(url, {
		headers: {
			Authorization: `Bearer ${accessToken}`,
			"Content-Type": "application/json",
		},
	});

	const json = await res.json();
	const tracks: Track[] = json.tracks.items;

	return tracks
		.map((track) => {
			if (track === null) return null;
			return {
				name: track.name,
				artist: track.artists[0].name,
				id: track.id,
			};
		})
		.filter((track) => track !== null);
}

export async function checkViral(id: string | string[], accessToken: string) {
	const playlists = await getViralTracks(accessToken);
	const temp = playlists
		.map((e: Track) => e?.id)
		.filter((e: string) => e !== undefined && e !== null);

	if (Array.isArray(id)) {
		const filteredArray = temp.filter((value) => id.includes(value));
		return filteredArray.length > 0;
	}
	return temp.includes(id);
}

export async function getViralTracks(accessToken: string): Promise<Track[]> {
	const listOfListOfSongs = await Promise.all(
		playlistIDs.map(async (playlistID) => {
			const urlPlaylist = `https://api.spotify.com/v1/playlists/${playlistID}`;

			const res = await fetch(urlPlaylist, {
				headers: {
					Authorization: `Bearer ${accessToken}`,
					"Content-Type": "application/json",
				},
			});

			const { tracks } = await res.json();
			const songs = tracks.items.map((song: { track: Track }) => song.track);
			return songs;
		})
	);

	return listOfListOfSongs.flat(1);
}
