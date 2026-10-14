
# Tapped Ai

make it possible for any performer to create a world tour from their phone

[https://tapped.ai](https://tapped.ai)

## Local development

From the repository root:

```sh
pnpm install --frozen-lockfile
cp apps/app.tapped.ai/.env.example apps/app.tapped.ai/.env.local
# Fill the public Firebase and Mapbox values in .env.local.
pnpm --filter app.tapped.ai dev
```

Open http://localhost:3000/map. Root `pnpm dev` starts all workspace dev servers;
use the filtered command above when you only need the main app.

The public client values are in Vercel's `app-tapped-ai` Development environment.
Use a public Mapbox token (`pk.`, never `sk.`). Keep `.env.local` ignored and do not
copy server credentials, service-account keys, or legacy search keys into it.
Next.js loads env files from this app directory, not the monorepo root. Restart
the dev server after changing them.

Missing Mapbox configuration causes the map SDK to throw in the browser even
though the dev server reports Ready. Firebase configuration is needed for sign-in.
PostHog is optional and stays disabled when its key is empty.

The API defaults to `https://api.tapped.ai`: public reads use live data, and
signed-in mutations affect real accounts. Set `NEXT_PUBLIC_TAPPED_API_URL` to your
local/test API for isolated development.

## MCP sign-in page

`/oauth/authorize` is the sign-in and consent page for the Tapped MCP server, which
lives in the Rust API (`services/api.tapped.ai`, see its README). The API validates
the MCP client's request and redirects here with `?request=<id>`; the user signs in
with Firebase (Google, Apple or email) and approves, and the page sends their
Firebase ID token to the API, which redirects back to the client. The page keeps no
session (in-memory Firebase persistence) and cannot be framed.

The app's domain must be an authorized domain in Firebase Auth for the Google and
Apple popups.
