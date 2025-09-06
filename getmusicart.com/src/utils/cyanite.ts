

export async function uploadTrack() {}

export async function createLibraryTrack() {}

export async function enqueueLibraryTrack(libraryTrackId: string) {
  console.log({ libraryTrackId });
}

export async function enqueueYoutubeTrack(videoUrl: string) {
  console.log({ videoUrl });
}

export async function enqueueSpotifyTrack(spotifyTrackId: string) {
  const res = await fetch(`/api/enqueue_spotify?spotifyTrackId=${spotifyTrackId}`);

  if (res.status !== 200) {
    console.log({ status: res.status, message: res.statusText });
    return;
  }

  return await res.json();
}
