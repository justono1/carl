# Adding or Updating a Tool

Use this guide when adding a new tool/service to CARL, or when changing the pinned version of an existing one.

## Updating a pinned version

1. Open the relevant `<domain>/env` file (e.g., `codex/env`, `br/env`).
2. Change the version value to the new pin (no `latest`, no `stable` except for `CLAUDE_CODE_VERSION`).
3. Commit.
4. On the target Mac: `git pull && ./bootstrap.sh`.

The script will detect the version mismatch and install the new version. No other changes needed.

## Adding a brand-new tool

### 1. Create the domain directory

```bash
mkdir -p <service>
```

Naming rules: lowercase, short, tool-aligned (`node`, `pnpm`, `playwright`, `codex`).

### 2. Add domain files

Whichever apply:

- `<service>/env` for CARL-managed non-secret variables (e.g., `<SERVICE>_VERSION=1.2.3`).
- Canonical tool config files using their real names (`config.toml`, `settings.json`, `.somerc`, `core.zsh`).

If no env variables apply yet, still add `<service>/env` with a comment placeholder so ownership is explicit.

### 3. Wire it into `bootstrap.sh`

1. Add `<service>/env` to the `domain_envs` array inside `load_domain_env`.
2. Add any new required version variable to the `pinned` array in `load_domain_env`.
3. Add the install step (a new function) and call it from `main`. Place it after `install_baseline_config_files` if it needs canonical config copied first, or wherever ordering demands.
4. Add a `command -v <tool>` check to `verify_versions`.
5. If the tool needs a canonical config file installed, add an `install -m 0644 …` line to `install_baseline_config_files` and (if it's JSON) a `jq -e` validation.

### 4. Idempotency expectations

The install step must be safe to re-run:

- Check whether the right version is already installed before doing anything (e.g., parse `--version` and compare).
- Overwrite config files unconditionally (they're authoritative).
- Don't duplicate lines in shell rc files — use marker-bounded blocks (see `ensure_carl_zshrc_source_block`).
- Fail loudly with `die` on validation errors, never silently.

### 5. Brewfile changes (if needed)

If the tool is available via Homebrew, add it to the embedded Brewfile inside `write_embedded_brewfile`. The Brewfile is the simplest path; only use a custom installer (npm global, GitHub release, `curl | bash`) when brew doesn't ship the tool or doesn't pin the version you need.

### 6. Documentation

Update at minimum:

- `README.md` — add the new domain to the repository layout.
- `docs/config-architecture.md` — add the new domain to the list and the install table.

### 7. Validate

```bash
bash -n bootstrap.sh
./bootstrap.sh
```

Confirm:

- `verify_versions` passes.
- The new tool runs from a fresh shell.
- A second `./bootstrap.sh` run is fast (everything reports "already satisfied").

## PR/commit checklist

- [ ] Added `<service>/env` and any canonical config files
- [ ] Wired the install + verification into `bootstrap.sh`
- [ ] Updated `README.md` and `docs/config-architecture.md`
- [ ] Confirmed `./bootstrap.sh` is idempotent (second run does no work)
