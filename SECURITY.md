# Security

## What the app reads

Every 2 seconds the app reads `~/.omlx/settings.json` with your user's permissions, and uses exactly two values from it:

- `server.port` — to build the request URL;
- `auth.api_key` — sent as `Authorization: Bearer …` to `127.0.0.1` only.

The key is held in memory for the lifetime of one request. It is never written to disk, never included in log output, never rendered in the window, and never sent to another host.

## Boundaries

| Boundary | Behaviour |
| --- | --- |
| Network | The app contacts `127.0.0.1` at the configured port and nothing else. No telemetry, analytics, update checks, or DNS lookups. |
| Redirects | HTTP redirects are refused outright, so a credential cannot be bounced to a third-party origin. |
| Writing | The app never modifies oMLX settings, models, caches, or limits. It only issues `GET /admin/api/activity`. |
| Persistence | Only UI preferences (width, text size, language, position) are stored, in the standard `UserDefaults` domain for `local.workbuddy.omlx-monitor`. No status data is persisted. |
| Processes | No helper daemons, no launch agents, no privileged operations. |

## Residual risks

These follow from the architecture and are worth stating plainly rather than implying they do not exist:

1. **Local process observation.** Any process running as your user that can bind or sniff the configured port could see the request, including the bearer token. This is inherent to loopback HTTP and applies to every local client of the oMLX admin API, including the official dashboard.
2. **Settings file readability.** The key is only as protected as `~/.omlx/settings.json`. Confirm its permissions if other accounts share the machine.
3. **Ad-hoc signature.** Builds from source are signed ad-hoc, not notarized. That is why Gatekeeper asks for confirmation on first launch. If you prefer, inspect `Sources/` and `build.sh` — the entire program is one readable Swift file.

## Reporting

Open a GitHub issue for anything that appears to contradict the table above. Please do not include real API keys or request identifiers in reports.
