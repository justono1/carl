# Mac Bootstrap Plan v2

## Goal
Set up a fresh macOS `arm64` machine with a ready-to-use development toolchain using one manual command, with no SSH hardening, no background agents, and no management-layer features.

## Scope
- In scope: environment/toolchain bootstrap only
- Out of scope (for now): repo cloning, secrets migration, full dotfiles/state sync, MSP/management integrations

## Plan
1. Scope lock.
   Target macOS `arm64` only.

2. Add repo deliverables.
   Create:
   - `macos/bootstrap-mac.sh` (embedded fixed Homebrew package profile)
   - `README.md` Mac quick-start section

3. Define package ownership.
   Use Homebrew for system/runtime tools (including Node).
   Use npm global for npm CLIs (`@openai/codex`, optional `@playwright/mcp`, optional `pnpm` if not using corepack).
   Keep each tool owned by one install path.

4. Implement idempotent bootstrap flow.
   `bootstrap-mac.sh` should:
   - verify macOS + `arm64`
   - install Xcode CLT if missing
   - install Homebrew if missing
   - load `brew shellenv`
   - run `brew bundle check || brew bundle install` using embedded package list
   - install npm global CLIs
   - install Playwright browsers
   - run verification checks
   - write `~/.bootstrap_done` with timestamp/version metadata

5. Enforce idempotence.
   Do not rely on marker file alone.
   Always run safe checks/install commands that can be re-run without unnecessary work.

6. Add required verification phase.
   Script must fail on missing/invalid toolchain.
   Verify at minimum:
   - `brew --version`
   - `node --version`
   - `npm --version`
   - `pnpm --version` (if included)
   - `codex --version`
   - `playwright --version`
   - browser install presence check

7. Keep one-command first-run.
   Use `curl` bootstrap execution flow (no git prerequisite).

8. Set baseline curl security.
   Use HTTPS + pinned immutable source (commit SHA or release asset) + checksum verification (`.sha256`) before execution.

9. Defer migration concerns explicitly.
   Dotfiles/shell config sync and broader state transfer are a later phase after toolchain bootstrap is stable.

10. Definition of done.
    A fresh macOS `arm64` machine reaches a usable terminal toolchain from one command, and rerunning bootstrap performs only necessary work.
