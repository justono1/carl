# Adding a Service Domain

Use this guide when introducing a new tool/service to CARL.

## 1. Create Domain Directory

Create a top-level directory named for the service:

```bash
mkdir -p <service>
```

Naming rules:

- lowercase letters and digits only when possible
- keep names short and tool-aligned (`node`, `pnpm`, `playwright`, `codex`)

## 2. Add Domain Files

Add whichever of these apply:

- `<service>/env` for CARL-managed non-secret variables
- canonical tool config file(s) using real names (examples: `config.toml`, `settings.json`, `.npmrc`, `.toolrc`)

If no env variables are needed yet, still add `<service>/env` with a comment placeholder so ownership is explicit.

## 3. Wire Script Consumption

Update scripts that should consume the new domain:

1. Source `scripts/load-domain-env.sh` if not already sourced.
2. Load file with `carl_load_env_file`.
3. Validate required keys with `carl_require_env_keys`.
4. Replace hardcoded/default values with loaded keys.

## 4. Wire Render Consumption (if bootstrap-relevant)

If the service affects Linux/macOS bootstrap artifacts:

1. Update `scripts/render-bootstrap-artifacts.sh`:
   - load `<service>/env`
   - validate required keys
   - add template substitutions
2. Update `linux/cloud-init.yaml.in` and/or `macos/bootstrap-mac.sh.in`:
   - add placeholders/variables
   - install canonical files during bootstrap if needed
3. Re-render artifacts:

```bash
./scripts/render-bootstrap-artifacts.sh
```

## 5. Idempotency Expectations

Ensure reruns are safe:

- copy/install operations overwrite deterministically
- config wiring does not duplicate entries
- validation fails with actionable errors

## 6. Documentation Updates (Required)

Update at minimum:

- `README.md`: add domain to layout/config map
- `docs/config-architecture.md`: add ownership + load path
- this file if the pattern evolves

If secrets handling changes, also update `docs/secrets.md`.

## 7. Validation Checklist

Run before opening a PR:

```bash
./scripts/render-bootstrap-artifacts.sh
./macos/update-checksums.sh --check
bash -n digitalOcean/*.sh scripts/*.sh macos/*.sh
```

And confirm:

- new domain files are committed
- rendered artifacts updated
- checksum file updated
- no root `.env` dependency introduced

## PR Checklist Snippet

```md
- [ ] Added `<service>/env` and canonical config files (if needed)
- [ ] Wired service into scripts via `load-domain-env.sh`
- [ ] Updated render/template wiring (if bootstrap-affecting)
- [ ] Re-rendered artifacts and validated checksums
- [ ] Updated README + docs/config-architecture.md
```
