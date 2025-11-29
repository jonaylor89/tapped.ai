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

| Directory | Tech | Description |
|-----------|------|-------------|
| `app.tapped.ai/` | Next.js | Main web application |
| `api.tapped.ai/` | Rust | Backend API |
| `com.intheloopstudio/` | Flutter | Mobile app |
| `event-crawler/` | Node.js | Event scraping service |
| `ticket-crawler/` | Node.js | Ticket scraping service |
| `venue-enrichment/` | Rust | Venue data enrichment |
| `getmusicart.com/` | Next.js | Music art generator |
| `getmusicepk.com/` | Next.js | EPK generator |
| `getmusicviralchecker.com/` | Next.js | Viral checker tool |
| `linktree.tapped.ai/` | Astro | Link tree page |
| `marketer.tapped.ai/` | Next.js | Marketing tools |
| `viralsocialmediaideas.com/` | Next.js | Social media ideas |
| `armada.tapped.ai/` | Node.js | Armada deployment |
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
