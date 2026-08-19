# ORTracker — OpenRouter Balance Tracker

A native macOS menu bar app that shows your OpenRouter balance, tracks usage, and detects top-ups automatically.

## Install

```bash
curl -fsSL https://ortracker.yates.id/install.sh | bash
```

Requires macOS 13+, an [OpenRouter API key](https://openrouter.ai/keys), and Xcode Command Line Tools (installs automatically if missing).

## Features

**Live balance** — Your real OpenRouter balance in the menu bar, updated every 60 seconds. No setup, no servers, no tracking.

**Three display modes** — Choose how you want to see your balance:
- **Quota Bar** — colored bar (green/orange/red) showing remaining credit at a glance
- **Balance** — dollar amount remaining
- **Percentage** — percentage remaining

**Usage analytics** — Click to see per-model breakdown, cost, API calls, and top models by usage.

**Top-up detection** — When you add credit to OpenRouter, the tracker automatically detects the increase and resets the quota to 100%. Use the **Reset Quota** button to sync manually.

**Auto-start** — Launches automatically on login (stays in your menu bar across restarts).

## How it works

The app fetches your balance from OpenRouter's [credits API](https://openrouter.ai/docs/api-reference/credits) every 60 seconds. It stores a local baseline (your balance after the last top-up or reset). When the balance jumps by more than $0.50, it registers as a top-up and the bar resets to 100%.

For the per-model usage breakdown, the app reads OpenRouter billing data from Hermes' session database (if available). The balance display works standalone — no Hermes required.

## Menu

| Item | Action |
|---|---|
| Balance display | Shows your selected view (quota bar, balance, or percentage) |
| OpenRouter usage | Cost, API calls, balance, remaining % for the selected period |
| Top models | Per-model cost and token breakdown |
| View | Switch between Quota Bar, Balance, and Percentage display |
| Period | 7 / 30 / 90 day usage window |
| Reset Quota | Sets the quota to 100% at the current balance |
| Refresh Now | Force a balance refresh |
| Quit | Exit the app |

## Security

Your OpenRouter API key is stored at `~/.ortracker/config` with 600 permissions (owner read/write only). The app sends a single HTTPS request to `openrouter.ai/api/v1/credits` with your key as a Bearer token — the same as every other OpenRouter client. No telemetry, analytics, or logs leave your machine.

## Uninstall

```bash
rm -rf /Applications/ORTracker.app ~/.ortracker
launchctl unload ~/Library/LaunchAgents/com.ortracker.menubar.plist 2>/dev/null
rm ~/Library/LaunchAgents/com.ortracker.menubar.plist 2>/dev/null
```

## Development

```bash
git clone https://github.com/mikeyates/ortracker.git
cd ortracker
swiftc -O ORTracker.swift -o ORTracker
./ORTracker
```

## Why?

OpenRouter doesn't show your balance in the menu bar. ORTracker fixes that — no browser tab, no dashboard, just the number.

Built with Swift, runs on macOS 13+. MIT license.