# TAPPED MCP / ChatGPT Plugin Plan

> **Pre-requisite:** Clean up the backend API first. This work comes after.

## Goal

Expose Tapped's live music discovery and booking data to AI assistants via:
1. **ChatGPT Custom GPT** (Actions / OpenAPI) — broad reach
2. **Claude MCP Server** — deep integration for Claude workflows

---

## What Already Exists

| Asset | Location |
|---|---|
| OpenAPI spec | `GET /swagger/json` |
| Public search | `GET /v1/performer/search` |
| Location discovery | `GET /v1/location/:latlng` |
| Performer lookup | `GET /v1/performer/:id`, `/v1/performer/username/:username` |
| Auth mechanism | `tapped-api-key` header |

---

## Phase 1: ChatGPT Custom GPT

1. Verify `/swagger/json` is accurate and complete
2. Create a GPT at chat.openai.com → Configure → Add Actions → paste OpenAPI URL
3. Set authentication type to API Key
4. Write a system prompt describing Tapped's purpose (live music discovery, booking, venue search)

**Effort:** ~1-2 hours once the API is clean and publicly deployed.

---

## Phase 2: Claude MCP Server

Create a new package `packages/mcp-server/` using `@modelcontextprotocol/sdk`.

### Tools to expose

- `search_performers(query, location?)` → wraps `GET /v1/performer/search`
- `get_performer(username_or_id)` → wraps `GET /v1/performer/:id` or `/username/:username`
- `search_by_location(lat, lng)` → wraps `GET /v1/location/:latlng`
- `get_opportunity(id)` → wraps opportunity endpoint (add if not yet public)
- `get_booking_history(user_id)` → wraps booking history (add if not yet public)

### Steps

1. `pnpm create` new package, add `@modelcontextprotocol/sdk` and `zod`
2. Implement tools as thin wrappers over the REST API
3. Run locally and add to Claude's MCP config (`~/.claude/claude_desktop_config.json`)
4. Optionally deploy for shared/team use

**Effort:** ~half a day of glue code.

---

## Notes

- Both integrations depend on the public API being clean, stable, and well-documented
- The MCP server is the better fit for internal/team Claude workflows
- The ChatGPT plugin is better for end-user discovery
