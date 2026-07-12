# YOYO Plugin

> **YOYO Plugin** is an ad-free, rebranded fork of CodexPlusPlus that auto-syncs with upstream daily.

<p align="center">
  <img src="docs/images/codex-plus-plus.png" alt="YOYO Plugin icon" width="160">
</p>

<p align="center">
  <a href="README.md">中文</a> | English
</p>

<p align="center">
  <img alt="Release" src="https://img.shields.io/github/v/release/sasakihuang/yoyo-Plugin">
  <img alt="Stars" src="https://img.shields.io/github/stars/sasakihuang/yoyo-Plugin">
  <img alt="License" src="https://img.shields.io/github/license/sasakihuang/yoyo-Plugin">
  <img alt="Rust" src="https://img.shields.io/badge/rust-1.85%2B-orange">
  <img alt="Tauri" src="https://img.shields.io/badge/tauri-2.x-24C8DB">
</p>

YOYO Plugin is an external enhancement launcher and manager for the Codex App. It does not modify the original Codex installation. Instead, it starts Codex externally and injects enhancements through the Chromium DevTools Protocol.

## Quick Start

Download the latest installer from [GitHub Releases](https://github.com/sasakihuang/yoyo-Plugin/releases):

- Windows: `YOYOPlugin-*-windows-x64-setup.exe`
- macOS Intel: `YOYOPlugin-*-macos-x64.dmg`
- macOS Apple Silicon: `YOYOPlugin-*-macos-arm64.dmg`

After installation, two entry points are available:

- `YOYO Plugin`: a silent launcher. It does not show the manager UI and only starts Codex with YOYO Plugin injection.
- `YOYO Plugin Manager`: a Tauri control panel for launch, diagnostics, repair, updates, relay injection, enhancements, and user scripts.

The Windows installer creates desktop and Start Menu shortcuts. The macOS DMG installs `/Applications/YOYO Plugin.app` and `/Applications/YOYO Plugin 管理工具.app`.

<table>
  <tr>
    <td align="center" width="55%">
      <strong>Support the Project</strong><br><br>
      <img src="docs/images/sponsor-alipay.jpg" alt="Alipay sponsor QR code" width="220">
      <img src="docs/images/sponsor-wechat.jpg" alt="WeChat sponsor QR code" width="220">
    </td>
    <td align="center" width="45%">
      <strong>Join the Community</strong><br><br>
      <img src="docs/images/discussion-group-qr.jpg" alt="Codex++ WeChat group QR code" width="220"><br><br>
      QQ group: <code>830629290</code><br>
      WeChat: <a href="https://docs.qq.com/doc/DQ2VOanZTTFZJcUpZ#">latest group QR code</a><br>
      Telegram: <a href="https://t.me/CodexPlusPlus">CodexPlusPlus</a><br>
      Friendly link: <a href="https://linux.do">LINUX DO</a>
    </td>
  </tr>
</table>

- Rust backend and silent launcher with no extra runtime requirement.
- Tauri + React manager with dark/light theme support.
- External CDP injection. No `app.asar` patching and no DLL writes into the Codex installation.
- Relay injection mode with multiple relay profiles, `CodexPlusPlus` provider configuration, and a one-click switch back to official ChatGPT login mode.
- Traditional enhancement mode with plugin marketplace unlock, session delete, Markdown export, project move, and more.
- Paste fix: when pasting from Word or other rich-text sources into the Codex composer, only keep the plain text so Codex does not treat the clipboard content as an image or file attachment. Off by default; requires a Codex relaunch to take effect.
  - **Usage note**: after toggling in the manager, click the "保存增强设置" / "Save enhancement settings" button to persist, then restart YOYO Plugin for the change to take effect.
- Independent user script management with startup injection.
- Provider Sync to keep historical sessions visible after switching providers.
- Zed open entry detects remote SSH context and opens the matching remote file in Zed Remote Development from Codex.
- Per-model context window configuration: the "Model list" is split into two columns, model name on the left and context window (e.g. `1M`, `200K`, or `1000000`) on the right. Codex++ auto-generates `model_catalog_json` and injects it into `config.toml`; the matching window is applied when you switch models. Leave the window empty to use Codex's default length.
- Upstream worktree creation: create new worktrees from `upstream/<base-branch>` after fetching the remote branch, reducing conflicts caused by stale local HEAD state.
- GitHub Release updates. Both the manager and silent launcher can detect available updates.
- Windows single instance, no console window, administrator manifest, and system Desktop path detection.
- Separate macOS x64 and arm64 DMGs. The silent launcher hides its Dock icon.

| Area | Capabilities |
| --- | --- |
| Provider configuration | Official login, official login plus API, pure API, and aggregate providers; Responses / Chat Completions; model tests, model discovery, Provider Doctor, cc-switch and deep-link imports |
| Models and context | Per-model context windows, auto-compact limits, `model_catalog_json`, shared config, and per-provider MCP, Skill, and Plugin selection |
| Session management | Local session scanning, bulk deletion, Markdown export, token usage history, Provider metadata sync, and backups |
| Codex enhancements | Plugin marketplace and model whitelist handling, session actions, paste fix, Chinese locale, fast startup, conversation width and scroll restore, service-tier controls, Goals, Stepwise, and image overlay |
| Development workflow | Project move, Upstream worktree creation, thread IDs, and Zed Remote project discovery and opening |
| Scripts and maintenance | User script installation and toggles, app detection, shortcuts, Watcher, environment cleanup, logs, diagnostics, health checks, and Release updates |

Every UI enhancement is independently configurable. Disabling the global enhancement switch still leaves Codex++ available as a provider and launch manager.

## Provider Modes

Official login, mixed API, and pure API are stored and switched separately:

| Mode | Purpose | Authentication boundary |
| --- | --- | --- |
| Official login | Use only the official ChatGPT / Codex account | Removes custom providers and API keys while preserving official login state |
| Official login + API | Keep official account features and plugins while routing model requests to a compatible API | Stores the key as a provider bearer token, not in pure API `auth.json` |
| Pure API | Use a custom Base URL and key without an official account | Maintains independent `config.toml` and API-key auth without mixing official credentials |
| Aggregate provider | Route across multiple ordinary API providers | Supports failover, conversation round-robin, request round-robin, and weighted round-robin |

Each provider can configure Responses or Chat Completions, model lists, a test model, User-Agent, context windows, auto-compact limits, and enabled MCP servers, Skills, and Plugins. Chat Completions can be converted locally into the Responses protocol used by Codex.

Per-model windows accept values such as `1M`, `200K`, or plain integers. Codex++ generates a dedicated `model_catalog_json` for Codex.

1. Make sure ChatGPT login status is detected.
2. Add one or more relay profiles with Base URL and Key.
3. Select the active profile and apply relay injection.
4. Launch `YOYO Plugin`.

YOYO Plugin writes configuration similar to this into `~/.codex/config.toml`:

- Session delete, bulk delete, Markdown export, and project move actions.
- Plugin marketplace unlock, plugin auto-expand, and model whitelist handling.
- Plain-text paste, forced Chinese locale, startup acceleration, and native menu localization.
- Conversation width, scroll restoration, thread IDs, service-tier controls, and Goals.
- Stepwise suggestions with a separate API, model, item count, and timeout.
- Upstream worktrees, Zed Remote, custom image overlays, and user scripts.

[model_providers.CodexPlusPlus]
name = "CodexPlusPlus"
wire_api = "responses"
requires_openai_auth = true
base_url = "https://example.com/v1"
experimental_bearer_token = "sk-..."
```

To return to the official login mode, use the clear API mode button in the Relay Injection page. This removes `OPENAI_API_KEY` related configuration and switches Codex back to official ChatGPT authentication.

## Enhancements

Enhancements are controlled in the manager. Enhancement injection is enabled by default. When disabled, YOYO Plugin will not inject its menu or scripts.

When relay injection mode is active, plugin marketplace unlock is unnecessary, and the UI will say so. Other enhancements, including session delete, export, move, paste fix, recommendations, and user scripts, can still be used.

## Updates and Packages

YOYO Plugin publishes installers through GitHub Releases. Windows builds an NSIS installer, while macOS builds separate Intel x64 and Apple Silicon arm64 DMGs.

The manager's About page can check and start updates. When the silent launcher finds a new version, it opens the manager directly on the update prompt.

## Data Locations

- Codex config: `~/.codex/config.toml`
- Codex auth state: `~/.codex/auth.json`
- Codex local database: prefers `~/.codex/sqlite/*.db`, falls back to legacy `~/.codex/state_5.sqlite`
- YOYO Plugin state and logs: `~/.codex-session-delete/`
- Provider Sync backups: `~/.codex/backups_state/provider-sync`

## FAQ

### The YOYO Plugin menu does not appear

Make sure Codex was launched from the `YOYO Plugin` entry instead of the original Codex entry. You can also inspect the Diagnostics and Logs pages in the manager.

### Requests fail after switching providers

First test the helper endpoint:

```powershell
Invoke-RestMethod -Method Post -Uri http://127.0.0.1:57321/backend/status -Body "{}" -ContentType "application/json"
```

If the endpoint works but the plugin still times out, it is usually a Codex page CDP bridge or script cache issue. Restart YOYO Plugin, or check manager logs for `renderer.script_loaded`, `bridge.request`, and `bridge.response`.

### How is Upstream worktree different from Codex native creation?

YOYO Plugin updates the remote branch first, then creates the worktree as if you ran:

```bash
git worktree add -b <new-branch> <worktree-path> upstream/<base-branch>
```

The new worktree starts from the fresh remote tracking branch instead of the local HEAD used by the current session. If YOYO Plugin cannot safely recognize the current Codex version's native worktree form, use the YOYO Plugin menu entry and enter the repository path, branch name, worktree path, remote, and base branch manually.

### macOS says the app cannot be opened or is damaged

Unsigned and unnotarized builds may be blocked by Gatekeeper. Allow the app in System Settings -> Privacy & Security. For formal distribution, configure Apple Developer ID signing and notarization.

### Does it support Intel Macs?

Yes. Releases provide both `macos-x64.dmg` and `macos-arm64.dmg`. Intel Macs should use the x64 package, while Apple Silicon Macs should use the arm64 package.

## Development

```bash
cd apps/codex-plus-manager
npm ci
npm run check
npm run vite:build

cd ../..
cargo fmt --all -- --check
cargo test
cargo build --release
```

Project structure:

```text
apps/
  codex-plus-launcher/          Silent launcher
  codex-plus-manager/           Tauri manager
assets/inject/
  renderer-inject.js            Enhancement script injected into Codex
crates/
  codex-plus-core/              Launch, injection, config, update, install, bridge
  codex-plus-data/              Session data, export, Provider Sync
scripts/installer/
  windows/CodexPlusPlus.nsi     Windows NSIS installer
  macos/package-dmg.sh          macOS DMG packager
```

## Notes

YOYO Plugin is an external enhancement tool and does not modify original Codex App files. If a future Codex App update changes page structure, the injection script may need updates.
