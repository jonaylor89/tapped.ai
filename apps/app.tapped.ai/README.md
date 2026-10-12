
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
