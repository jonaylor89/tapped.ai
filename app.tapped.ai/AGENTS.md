# Repository Guidelines

## Project Structure & Module Organization
- `src/app` holds Next.js App Router routes and layout entry points.
- `src/components` contains shared UI components; feature folders live under `src/components/*`.
- `src/context`, `src/hooks`, `src/lib`, `src/utils`, and `src/domain` organize state, helpers, and domain logic.
- `public/` stores static assets (images, icons, etc.).
- Config lives at the repo root (`next.config.mjs`, `tailwind.config.ts`, `biome.json`, `.eslintrc.js`).

## Build, Test, and Development Commands
- `npm run dev`: start the Next.js dev server (Turbopack).
- `npm run build`: build the production bundle.
- `npm run start`: run the production server after a build.
- `npm run typecheck`: run TypeScript without emitting files.
- `npm run lint`: run ESLint checks.
- `npm run lint:fix`: auto-fix lint issues where possible.

## Coding Style & Naming Conventions
- Indentation is 2 spaces; line width targets 120 characters.
- Use double quotes and semicolons (see `biome.json` and `.eslintrc.js`).
- Prefer existing folder/file conventions: many components are `PascalCase.tsx`, while some utility files are lower/snake case. Match the local pattern in each folder.
- Tailwind CSS is configured; keep class usage consistent with existing components.

## Testing Guidelines
- No test framework or scripts are configured in this repo.
- If you add tests, also add the matching npm script(s) and document them here.

## Commit & Pull Request Guidelines
- Git history is not available in this checkout, so no enforced commit format is known.
- Use concise, imperative commit subjects (e.g., "Add booking summary card").
- PRs should describe the change, link relevant issues, and include screenshots for UI updates.

## Security & Configuration Tips
- Keep secrets in `.env.local` (Next.js convention) and avoid committing credentials.
- Review `firebase.json` and any production config changes carefully before release.
