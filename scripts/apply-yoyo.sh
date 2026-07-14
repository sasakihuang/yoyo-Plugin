#!/usr/bin/env bash
# YOYO Plugin — build-time patch applied to a clean checkout BEFORE building.
# Applied ephemerally (never committed) so the repo keeps tracking its base.
# Every patch is ASSERTED afterwards: if the base restructures and a step stops
# matching, the build FAILS LOUDLY instead of shipping an inconsistent app.
# Anchors are single-line / whitespace-tolerant so Windows (CRLF) is safe.
# Usage: REPO_SLUG="you/yoyo-Plugin" BRAND="YOYO Plugin" bash scripts/apply-yoyo.sh
set -euo pipefail

REPO_SLUG="${REPO_SLUG:-${GITHUB_REPOSITORY:-OWNER/yoyo-Plugin}}"
BRAND="${BRAND:-YOYO Plugin}"
ASSET_PREFIX="${ASSET_PREFIX:-YOYOPlugin}"
APP=apps/codex-plus-manager/src/App.tsx
UPD=crates/codex-plus-core/src/update.rs
CMD=apps/codex-plus-manager/src-tauri/src/commands.rs
INJ=assets/inject/renderer-inject.js

ROOT="${GITHUB_WORKSPACE:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
cd "$ROOT"

_rep() {  # <file> <FROM> <TO> : literal, global, anchor-checked
  local f="$1"
  [ -f "$f" ] || { echo "MISSING FILE: $f" >&2; exit 2; }
  FROM="$2" TO="$3" FILE="$f" perl -0777 -i -pe '
    BEGIN { $from=$ENV{FROM}; $to=$ENV{TO}; $file=$ENV{FILE}; }
    if (index($_,$from)>=0) { s/\Q$from\E/$to/g; }
    elsif (index($_,$to)>=0) { }
    else { die "ANCHOR MISSING in $file: $from\n"; }
  ' "$f"
}
_gone() { ! grep -qF "$2" "$1" || { echo "REMOVAL FAILED in $1 (still present): $2" >&2; exit 7; }; }

echo ">> [1/11] patch: core service defaults"
_rep crates/codex-plus-core/src/ads.rs \
  '    fetch_ad_list_from_urls(&DEFAULT_AD_LIST_URLS).await' \
  '    Ok(serde_json::json!({ "version": 1, "ads": [] }))'

echo ">> [2/11] patch: repo links -> $REPO_SLUG"
grep -rlIF 'BigPizzaV3/CodexPlusPlus' apps crates assets scripts \
  | grep -vE '/node_modules/|/target/|package-lock\.json' \
  | while IFS= read -r f; do
      SLUG="$REPO_SLUG" perl -0777 -i -pe 's{BigPizzaV3/CodexPlusPlus(?!ScriptMarket)}{$ENV{SLUG}}g' "$f"
    done
_gone "$UPD" 'BigPizzaV3/CodexPlusPlus'

echo ">> [3/11] patch: updater asset matching"
perl -0777 -i -pe 's/\Qname.contains("codex")\E/true/g; s/\Qname.contains("plus")\E/true/g' "$UPD"
_gone "$UPD" 'name.contains("codex")'
_gone "$UPD" 'name.contains("plus")'

echo ">> [4/11] patch: provider test message"
grep -qF '发送 hi，HTTP' "$CMD" || { echo "ANCHOR MISSING: provider test message" >&2; exit 5; }
perl -0777 -i -pe 's/message: format!\(\s*"已向[^"]*",\s*result\.http_status\s*\)/message: if result.http_status < 400 { format!("连接正常（HTTP {}）", result.http_status) } else { format!("连接失败（HTTP {}）", result.http_status) }/s' "$CMD"
_gone "$CMD" '发送 hi，HTTP'
grep -qF 'message: if result.http_status < 400' "$CMD" || { echo "provider test simplify FAILED" >&2; exit 7; }

echo ">> [5/11] patch: installer filenames"
_rep scripts/installer/windows/CodexPlusPlus.nsi 'CodexPlusPlus-' "$ASSET_PREFIX-"
_rep scripts/installer/macos/package-dmg.sh 'CodexPlusPlus-' "$ASSET_PREFIX-"

echo ">> [6/11] patch: nav entries"
grep -qF '{ id: "recommendations",' "$APP" || { echo "ANCHOR MISSING: recommendations nav" >&2; exit 5; }
perl -0777 -i -pe 's/\n[ \t]*\{ id: "recommendations",[^}]*\},//g' "$APP"
_gone "$APP" '{ id: "recommendations",'

echo ">> [7/11] patch: overview cards"
grep -qF 'jojocode-overview' "$APP" || { echo "ANCHOR MISSING: jojocode-overview" >&2; exit 5; }
perl -0777 -i -pe 's{\s*<Panel className="jojocode-overview">.*?</Panel>}{}s' "$APP"
_gone "$APP" 'jojocode-overview'

echo ">> [8/11] patch: promo links & CTAs (about panel, community links, star CTA)"
# Script market: upstream turned the script homepage button into a GitHub
# "Star 支持作者" CTA (#1494). Force the neutral 主页 variant — the homepage
# link stays functional, the star solicitation never renders.
_rep "$APP" \
  'const isGitHubHomepage = script.homepage ? isGitHubRepositoryHomepage(script.homepage) : false;' \
  'const isGitHubHomepage = false;'
grep -qF 'const isGitHubHomepage = false;' "$APP" || { echo "star CTA neutralize FAILED" >&2; exit 7; }
# injected menu: drop rows by stable data-attr (text-agnostic)
for KEY in discord telegram issue; do
  perl -0777 -i -pe 's{\s*<div class="codex-plus-row">\s*<div><div class="codex-plus-row-title">[^<]*</div><div class="codex-plus-row-description">[^<]*</div></div>\s*<button[^>]*data-codex-plus-'"$KEY"'[^>]*>[^<]*</button>\s*</div>}{}sg' "$INJ"
done
perl -0777 -i -pe 's{<br>Discord: <a[^>]*>[^<]*</a><br>Telegram: <a[^>]*>[^<]*</a>}{}sg' "$INJ"
_gone "$INJ" 'Discord 社区'
_gone "$INJ" 'Telegram 频道'
# manager About: drop external-link buttons (keep project home -> fork)
perl -0777 -i -pe 's!\s*<Button onClick=\{[^}]*openExternalUrl\("https://github\.com/[^"]*/issues"\)[^}]*\}[^>]*>.*?</Button>!!s' "$APP"
perl -0777 -i -pe 's!\s*<Button onClick=\{[^}]*discord\.gg[^}]*\}[^>]*>.*?</Button>!!s' "$APP"
perl -0777 -i -pe 's!\s*<Button onClick=\{[^}]*t\.me/[^}]*\}[^>]*>.*?</Button>!!s' "$APP"
_gone "$APP" 'discord.gg'
_gone "$APP" 't.me/'
_gone "$APP" '/issues"'

echo ">> [9/11] patch: brand badge"
# Upstream removed the brand-mark badge (2026-07-14); the visible title is now
# plain "Codex++" text, which step 10 rebrands. Keep a guard: "C++" is NOT
# "Codex++", so if the badge ever comes back step 10 would miss it and the
# sidebar would ship a C++ badge — fail loudly instead.
if grep -qF '"brand-mark"' "$APP"; then
  echo "ANCHOR CHANGED: brand-mark badge is back in App.tsx — re-add the badge patch (step 9)" >&2
  exit 5
fi

echo ">> [10/11] patch: updater CN mirrors + sha256 verification"
# GitHub is unreachable for many users in mainland China without a proxy, so
# the updater falls back to public gh-proxy style accelerators for BOTH
# latest.json and the installer download. Because a third-party mirror could
# tamper with an unsigned installer, latest.json now carries per-asset sha256
# (generated in the release job) and the updater refuses a mismatched file.
# Must run BEFORE the brand rebrand: anchors below contain "Codex++".
grep -qF 'pub async fn fetch_latest_release(latest_json_url: &str)' "$UPD" || { echo "ANCHOR MISSING: fetch_latest_release" >&2; exit 5; }
grep -qF 'pub asset_url: Option<String>,' "$UPD" || { echo "ANCHOR MISSING: Release.asset_url" >&2; exit 5; }
# 10a. Release struct gains asset_sha256 (serde: Option => optional on input)
perl -0777 -i -pe 's/(pub struct Release \{[^}]*pub asset_url: Option<String>,)/$1\n    pub asset_sha256: Option<String>,/s' "$UPD"
# 10b. GitHub-API constructor: no digest available there
perl -0777 -i -pe 's/(fn release_from_github_payload.*?asset_url: selected\.map\(\|asset\| asset\.browser_download_url\),)/$1\n        asset_sha256: None,/s' "$UPD"
# 10c. latest.json constructor: look up the selected asset's sha256
perl -0777 -i -pe 's/(fn release_from_latest_json_payload.*?)(    let selected = select_update_asset\(&assets\);)/$1$2\n    let asset_sha256 = selected.as_ref().and_then(|sel| {\n        payload.get("assets")?.as_array()?.iter().find_map(|asset| {\n            if asset.get("name")?.as_str()? == sel.name {\n                asset.get("sha256")?.as_str().map(str::to_string)\n            } else {\n                None\n            }\n        })\n    });/s' "$UPD"
perl -0777 -i -pe 's/(fn release_from_latest_json_payload.*?asset_url: selected\.map\(\|asset\| asset\.browser_download_url\),)/$1\n        asset_sha256,/s' "$UPD"
# 10d. fetch_latest_release -> mirror-aware helper (also used for downloads)
perl -0777 -i -pe 's#pub async fn fetch_latest_release\(latest_json_url: &str\) -> anyhow::Result<Release> \{.*?\n\}#const YOYO_MIRROR_PREFIXES: [\&str; 4] = [\n    "",\n    "https://gh-proxy.com/",\n    "https://ghfast.top/",\n    "https://gh.llkk.cc/",\n];\n\nasync fn yoyo_get_with_mirrors(url: \&str, accept_json: bool) -> anyhow::Result<reqwest::Response> {\n    let client =\n        crate::http_client::proxied_client(\&format!("Codex++/{}", crate::version::VERSION))?;\n    let mut last_err: Option<anyhow::Error> = None;\n    for prefix in YOYO_MIRROR_PREFIXES {\n        let full = format!("{prefix}{url}");\n        let mut req = client.get(\&full);\n        if accept_json {\n            req = req.header(reqwest::header::ACCEPT, "application/json");\n        }\n        match req.send().await {\n            Ok(resp) => match resp.error_for_status() {\n                Ok(resp) => return Ok(resp),\n                Err(err) => last_err = Some(err.into()),\n            },\n            Err(err) => last_err = Some(err.into()),\n        }\n    }\n    Err(last_err.unwrap_or_else(|| anyhow::anyhow!("no update mirror reachable")))\n}\n\npub async fn fetch_latest_release(latest_json_url: \&str) -> anyhow::Result<Release> {\n    let payload = yoyo_get_with_mirrors(latest_json_url, true)\n        .await?\n        .json::<Value>()\n        .await?;\n    release_from_latest_json_payload(\&payload)\n}#s' "$UPD"
# 10e. installer download goes through the same mirror ladder + sha256 check
perl -0777 -i -pe 's#let bytes =\s*crate::http_client::proxied_client\(&format!\("Codex\+\+/\{\}", crate::version::VERSION\)\)\?\s*\.get\(url\)\s*\.send\(\)\s*\.await\?\s*\.error_for_status\(\)\?\s*\.bytes\(\)\s*\.await\?;#let bytes = yoyo_get_with_mirrors(url, false).await?.bytes().await?;\n    if let Some(expected) = release.asset_sha256.as_deref() {\n        use sha2::Digest;\n        let digest = format!("{:x}", sha2::Sha256::digest(\&bytes));\n        if !digest.eq_ignore_ascii_case(expected.trim()) {\n            anyhow::bail!("安装包校验失败（sha256 不匹配），已取消安装，请稍后重试");\n        }\n    }#s' "$UPD"
grep -qF 'YOYO_MIRROR_PREFIXES' "$UPD" || { echo "mirror helper insert FAILED" >&2; exit 7; }
grep -qF 'sha2::Sha256::digest' "$UPD" || { echo "sha256 check insert FAILED" >&2; exit 7; }
[ "$(grep -c 'yoyo_get_with_mirrors' "$UPD")" -ge 3 ] || { echo "mirror helper not wired to all fetch paths" >&2; exit 7; }
_gone "$UPD" '.get(latest_json_url)'

echo ">> [11/11] patch: brand strings -> $BRAND"
grep -rlIF 'Codex++' apps crates assets scripts \
  | grep -vE '/node_modules/|/target/|package-lock\.json' \
  | while IFS= read -r f; do
      TO="$BRAND" perl -0777 -i -pe 's/\QCodex++\E/$ENV{TO}/g' "$f"
    done

echo "OK: build patch applied (REPO_SLUG=$REPO_SLUG BRAND=$BRAND)"
