import type { Song } from "@/types/song";

export const removeDuplicates = (orig: Song[]) => {
	const names = orig.map((song) => song.name);
	const deduped = orig.filter((song, index) => {
		return names.indexOf(song.name) === index;
	});
	return deduped;
};

export const obtainDuplicates = (songs: Song[], searchSong: Song) => {
	const out = songs
		.filter((item) => searchSong.name === item.name && searchSong.artist === item.artist)
		.map((item) => item.id);
	return out;
};
