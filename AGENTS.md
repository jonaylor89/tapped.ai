# Tapped Monorepo

## Quick Commands (via Just)

```bash
just --list          # Show all commands
just install         # pnpm install across all packages
just lint            # Lint everything
just lint-fix        # Auto-fix lint issues
just build-all       # Build Node.js + Rust projects
just dev-app         # Start app.tapped.ai dev server
just dev <package>   # Start dev server for specific package
```

## Project Structure

This is a Turborepo monorepo. Frontend apps live in `apps/`, backend services in `services/`.

| Directory | Tech | Description |
|-----------|------|-------------|
| `apps/app.tapped.ai/` | Next.js | Main web application |
| `apps/getmusicart.com/` | Next.js | Music art generator |
| `apps/getmusicepk.com/` | Next.js | EPK generator |
| `apps/getmusicviralchecker.com/` | Astro | Viral checker tool |
| `apps/linktree.tapped.ai/` | Astro | Link tree page |
| `apps/marketer.tapped.ai/` | Next.js | Marketing tools |
| `apps/viralsocialmediaideas.com/` | Astro | Social media ideas |
| `services/api.tapped.ai/` | Rust | Backend API |
| `services/event-crawler/` | Node.js | Event scraping service |
| `services/ticket-crawler/` | Node.js | Ticket scraping service |
| `services/venue-enrichment/` | Rust | Venue data enrichment |
| `services/midia-to-threads/` | Python | Midia to threads |
| `com.intheloopstudio/` | Flutter | Mobile app |
| `platform/` | Terraform | Infrastructure |
| `packages/` | TypeScript | Shared code |

## Shared Packages

- `@tapped/firebase-config` - Firebase initialization
- `@tapped/domain` - Shared TypeScript types
- `@tapped/ui` - Shared UI components

## Code Style

- **Formatter**: Biome (2-space indent, 120 line width)
- **Quotes**: Double quotes, semicolons always
- **Linting**: Biome with recommended rules

## CI/CD

- `node.yml` - Lint, typecheck, build all Node.js packages
- `rust.yml` - Build and clippy for Rust projects  
- `flutter.yml` - Test and build Flutter app
