# Vercel to Cloudflare Migration

## Current status

The following domains have been moved to Cloudflare DNS:

- `tapped.ai`
- `viralsocialmediaideas.com`

The remaining domains are still managed through their existing DNS providers because access was not available to move them:

- `getmusicart.com`
- `getmusicepk.com`
- `getmusicviralchecker.com`

Having `tapped.ai` active in Cloudflare is sufficient to configure Cloudflare Tunnel for:

- `api.tapped.ai`
- `search.tapped.ai`

Do not remove the VPS's public HTTP, HTTPS, or SSH access until the tunnel and Tailscale SSH have both been tested independently.

## Recommended target architecture

| Service | Target |
|---|---|
| `app.tapped.ai` | Cloudflare Workers using `vinext`, subject to compatibility testing |
| `tapped.ai` | Workers Static Assets |
| `marketer.tapped.ai` | Workers Static Assets |
| `viralsocialmediaideas.com` | Workers Static Assets |
| `getmusicart.com` | Workers Static Assets after DNS access is available |
| `getmusicepk.com` | Workers Static Assets after DNS access is available |
| `getmusicviralchecker.com` | Astro on Workers using `@astrojs/cloudflare` after DNS access is available |
| `api.tapped.ai` | Existing VPS through Cloudflare Tunnel |
| `search.tapped.ai` | Existing VPS through Cloudflare Tunnel |
| SSH | Tailscale SSH only |
| Firebase, Postmark, and Google Workspace | Remain on their existing platforms; preserve their DNS records |

Cloudflare Workers with Static Assets should be preferred for new static deployments rather than creating new Cloudflare Pages projects.

## Phase 1: Verify DNS migration

Before changing application hosting, verify the Cloudflare zones and imported records.

Important records include:

- Google Workspace MX records
- SPF, DKIM, and DMARC
- Postmark verification and inbound-mail records
- Firebase verification records
- Apple verification and associated-domain records
- Redirects and `www` aliases
- Existing Vercel records

Mail-related records must remain DNS-only. Do not proxy MX records or mail-provider verification records.

Initially, keep Vercel-backed records pointed at Vercel. This separates the DNS migration from the hosting migration and allows applications to move individually.

## Phase 2: Configure Tailscale SSH

Tailscale is installed on the VPS, but the node must be authenticated and verified before public SSH is removed.

1. Authenticate the VPS into the correct tailnet.
2. Enable Tailscale SSH.
3. Confirm the tailnet SSH policy permits the intended administrator account.
4. Test SSH from a second terminal using the Tailscale hostname or address.
5. Keep the existing public SSH session open during testing.

Only remove public port 22 after a fresh Tailscale SSH session succeeds.

## Phase 3: Configure Cloudflare Tunnel

Create a named tunnel such as `tapped-production` in Cloudflare Zero Trust.

Install `cloudflared` on the VPS and run it as a systemd service using a remotely managed tunnel token.

Configure these public hostnames:

| Public hostname | Origin service |
|---|---|
| `api.tapped.ai` | `http://127.0.0.1:3000` |
| `search.tapped.ai` | `http://127.0.0.1:8108` |

The Docker services must be published only on loopback before public ingress is disabled. For example:

```yaml
services:
  api:
    ports:
      - "127.0.0.1:3000:3000"

  typesense:
    ports:
      - "127.0.0.1:8108:8108"
```

Alternatively, `cloudflared` can run inside the Compose network and address the services by their Compose names. Running it as a host systemd service with loopback-only Docker bindings provides a simple separation between tunnel management and the application stack.

Do not put Cloudflare Access in front of endpoints required by public web or mobile clients. Continue enforcing Typesense API keys and application authentication, and add Cloudflare WAF and rate-limiting rules where appropriate.

### Tunnel verification

Before closing public ports, verify:

```bash
curl --fail https://api.tapped.ai/health
curl --fail https://search.tapped.ai/health
```

Also verify:

- Native and web application API requests
- Typesense search
- Postmark inbound webhooks
- Authentication flows
- Cloudflare Tunnel health and reconnect behavior
- VPS behavior after restarting `cloudflared`

## Phase 4: Lock down the VPS

After the tunnel and Tailscale SSH have both been verified:

1. Remove Caddy's public `80` and `443` port mappings, or remove Caddy if it is no longer needed.
2. Ensure API and Typesense ports are bound only to `127.0.0.1`.
3. Remove public firewall allowances for ports 22 and 8108.
4. Keep outbound traffic available for Cloudflare Tunnel, Tailscale, Firebase, Postmark, OpenAI, Stream, and Slack.
5. Tailscale can retain its direct UDP port (`41641/udp`) for better connectivity; it can also operate through relays if that port is closed.
6. Verify that the VPS public IPv4 and IPv6 addresses no longer accept HTTP, HTTPS, SSH, or Typesense connections.

Docker-published ports can bypass ordinary UFW input rules. Security must therefore be enforced by removing public Docker port mappings, not only by changing UFW.

## Phase 5: Migrate static applications

Migrate these first because they have the lowest deployment risk:

- `apps/getmusicart.com`
- `apps/getmusicepk.com`
- `apps/marketer.tapped.ai`
- `apps/linktree.tapped.ai`
- `apps/viralsocialmediaideas.com`

Deploy each as a Worker with Static Assets to a temporary `workers.dev` hostname. Test it before attaching its production custom domain.

Use GitHub Actions for deployment so the repository contains pinned Wrangler versions, explicit build commands, preview deployments, and repeatable production releases.

Only `tapped.ai`, its subdomains, and `viralsocialmediaideas.com` can be connected immediately. The other apex domains require access to their authoritative DNS providers first.

## Phase 6: Migrate the Astro SSR application

`getmusicviralchecker.com` currently uses the Vercel Astro adapter:

```js
import vercel from "@astrojs/vercel";
```

Replace it with a pinned Cloudflare adapter:

```js
import cloudflare from "@astrojs/cloudflare";
```

Add a Wrangler configuration and test all server-rendered routes on a preview deployment before changing production DNS. Its custom domain cannot be migrated until DNS access is available.

## Phase 7: Migrate `app.tapped.ai`

This is the highest-risk frontend because it uses Next.js 16, route handlers, dynamic rendering, proxy behavior, PostHog rewrites, Firebase, and Typesense.

Cloudflare currently recommends `vinext` for Next.js on Workers, but it remains a beta product. Start with a compatibility check:

```bash
cd apps/app.tapped.ai
pnpm dlx vinext check
```

Create a parallel preview deployment without changing the existing Vercel deployment. Test:

- Authentication and refresh persistence
- `/api/search`
- Dynamic search pages
- Firebase calls
- Typesense requests
- PostHog ingestion rewrites
- Redirect and proxy behavior
- RevenueCat
- Rive and other large client assets
- Mobile and desktop flows

If `vinext` has a blocking compatibility gap, evaluate Cloudflare's OpenNext adapter or temporarily leave `app.tapped.ai` on Vercel while the other services move.

Cloudflare's Next.js guide:

<https://developers.cloudflare.com/workers/framework-guides/web-apps/nextjs/>

## Phase 8: Retire Vercel gradually

After each application has run successfully on Cloudflare for an observation period:

1. Remove its Vercel domain assignment.
2. Keep the Vercel project available temporarily for rollback.
3. Review Worker logs, errors, analytics, and resource usage.
4. Delete the Vercel project only after the rollback period ends.

Do not cancel Vercel until all required applications and environment variables have been accounted for.

## Infrastructure management

Add Cloudflare infrastructure under a dedicated directory such as:

```text
platform/cloudflare/
```

Use a pinned Terraform Cloudflare provider for:

- DNS records
- Tunnel definitions
- Tunnel ingress
- WAF and rate-limiting configuration

Keep Worker build and deployment configuration with each application. Store Worker secrets through `wrangler secret` or GitHub environment secrets rather than Terraform state or committed files.

## Execution order

1. Verify the `tapped.ai` and `viralsocialmediaideas.com` Cloudflare zones and DNS records.
2. Complete and test Tailscale SSH authentication.
3. Create and verify the Cloudflare Tunnel for `api.tapped.ai` and `search.tapped.ai`.
4. Bind VPS services to loopback and remove public Docker port mappings.
5. Remove public VPS firewall access only after tunnel and Tailscale tests pass.
6. Deploy the static applications whose domains are available in Cloudflare.
7. Migrate the Astro SSR application after obtaining DNS access.
8. Compatibility-test and migrate `app.tapped.ai`.
9. Observe production behavior.
10. Retire Vercel after the rollback window.
