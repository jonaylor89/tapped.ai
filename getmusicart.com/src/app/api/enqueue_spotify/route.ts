

const cyaniteAccessToken = process.env.CYANITE_ACCESS_TOKEN;

export async function GET(req: Request) {
  const url = new URL(req.url);
  const spotifyTrackId = url.searchParams.get('spotifyTrackId');

  console.log({ spotifyTrackId });


  const query = `
    mutation SpotifyTrackEnqueueMutation($input: SpotifyTrackEnqueueInput!) {
        spotifyTrackEnqueue(input: $input) {
          __typename
          ... on SpotifyTrackEnqueueSuccess {
            enqueuedSpotifyTrack {
              id
            }
          }
          ... on Error {
            message
          }
        }
      } 
    `;

  const res = await fetch('https://api.cyanite.ai/graphql', {
    method: 'POST',
    body: JSON.stringify({
      query: {
        query,
        variables: {
          input: {
            spotifyTrackId,
          },
        },
      },
    }),
    headers: {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${cyaniteAccessToken}`,
    },
  });

  if (res.status !== 200) {
    console.log({ status: res.status, message: res.statusText });
    return Response.error();
  }

  const json = await res.json();
  console.log({ json });

  return Response.json(json);
}
