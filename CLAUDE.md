# xion-mainnet-1 — CLAUDE.md

Configuration, release notes, and upgrade tooling for the Xion mainnet (`xion-mainnet-1`).

## Repository Structure

```
config/           # Node configuration files (app.toml, config.toml, genesis.json)
proposals/        # On-chain governance proposal JSON files
release_notes/    # Per-version release notes (v*.md) and upgrade_path.md
releases/         # Cosmovisor upgrade binary JSON files (v*.json)
scripts/          # Release orchestration scripts
```

## GitHub Workflows

### `create-release.yml`

**Triggered by:**
- `workflow_call` from **`burnt-labs/xion`** `release-downstream.yaml` — fires on every **stable** (non-rc) xion release
- `workflow_dispatch` — manual trigger with inputs: `release_tag`, `deposit`, `expedited`

**What it does:**
- Runs `./scripts/orchestrate-release.sh` to create a governance upgrade proposal PR

## Upstream Triggers

| Source | Workflow | Condition |
|--------|----------|-----------|
| `burnt-labs/xion` | `release-downstream.yaml` | Stable release published (tag without `-rc`) |

## Downstream Triggers

None — this repo does not trigger other repos.

## Release Files

When a new xion version is released:
1. Add `releases/v<MAJOR>.json` with binary URLs + sha256 checksums
2. Add `release_notes/v<MAJOR>.md` with upgrade details
3. Update `release_notes/upgrade_path.md` with the new entry

Binary JSON format:
```json
{
  "binaries": {
    "darwin/amd64": "https://github.com/burnt-labs/xion/releases/download/vX.Y.Z/xiond_X.Y.Z_darwin_amd64.tar.gz?checksum=sha256:<hash>",
    "darwin/arm64": "...",
    "linux/amd64": "...",
    "linux/arm64": "..."
  }
}
```

## Secrets Required

| Secret | Purpose |
|--------|---------|
| `BURNT_CLAUDE_API_KEY` | Claude Code orchestration |
| `GITHUB_TOKEN` | PR creation |
