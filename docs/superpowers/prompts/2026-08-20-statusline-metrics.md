# Start prompt: reset times, context percentage, and no path segment

Executing this prompt requires separate, explicit user authorization. This
document describes proposed work and does not authorize implementation, commit,
push, or PR creation.

## Objective

Three changes to the Claude Code status line, in `claude/statusline.sh`:

1. Add rate-limit reset times to the existing limits segment.
2. Add a context-window usage segment.
3. Remove the directory path segment.

Target line, in order:

```text
opus-5 | worktree-my-feature | ctx 34% | 5h 2% (3h) · 7d 99% (2d)
```

## Working setup

Create a fresh worktree off `origin/main`. Do not work in the main checkout at
`~/Apps/wezterm-tmux-dotfiles`, and do not reuse the `cc-statusline` worktree,
which belongs to the work that produced this prompt.

Remotes are asymmetric and easy to get wrong:

- `origin` is `ajason13/terminal-dotfiles`. You have **no push access**.
- `fork` is `ajason14/terminal-dotfiles`. Push here.
- PRs go to `ajason13/terminal-dotfiles`, base `main`, head `ajason14:<branch>`.

`~/.claude/statusline.sh` is a symlink into the **main checkout**, not into any
worktree, so nothing you do takes effect live until the change merges and
`~/Apps/wezterm-tmux-dotfiles` is pulled.

## Current state

`claude/statusline.sh` is 90 lines at `origin/main` (983ed1f). It reads a JSON
payload on stdin and joins non-empty segments with `|`. Present segments:
`MODEL`, `BRANCH`, `RELPATH`, `LIMITS`.

Three segments were deliberately removed in the last few days:

- the session objective (PR #58), plus the whole capture subsystem behind it
- the PR number (PR #60), plus its backgrounded `gh pr view` cache
- the Salesforce org indicator (PR #61), plus its `PreToolUse` hook

All three went because the tmux window name already carried the information, and
the workflow is one window per task. **Do not re-add any of them**, and hold new
segments to the same test: does something already in view say this?

## Task 1: rate-limit reset times

The payload carries `rate_limits.five_hour.resets_at` and
`rate_limits.seven_day.resets_at` as **unix epoch seconds**. The script already
renders the percentages beside them and ignores the reset fields.

Render the time remaining, not a wall-clock time, so the number is readable
without arithmetic: `5h 2% (3h)`, `7d 99% (2d)`. Round to whole hours below a
day and whole days above it.

- This is macOS. `date -r <epoch>` works; `date -d` is GNU and does not.
  Computing `(( resets_at - $(date +%s) ))` avoids `date` entirely and is
  preferred.
- Omit the parenthetical when the field is absent, or when the delta is zero or
  negative, rather than printing `(0h)` or a negative span.
- Keep the existing `·` separator between the 5h and 7d halves.

## Task 2: context percentage

Add a segment from `context_window.used_percentage`, which Claude Code
pre-calculates. Render as `ctx 34%`. Place it **before** the limits segment.

Two documented behaviours the code must handle, both real and both easy to miss:

- `used_percentage` is `null` before the first API call in a session, and again
  after `/compact` until the next API call.
- The status line runs on every render, including those early nulls.

Omit the segment entirely when the value is absent, matching how every other
segment in the file already behaves. Do not print `ctx 0%` as a stand-in.

Do not compute the percentage yourself from `current_usage`. If you ever need
to, the documented formula is input-only: `input_tokens +
cache_creation_input_tokens + cache_read_input_tokens`, excluding
`output_tokens`.

## Task 3: remove the path segment

Delete `RELPATH`, its construction block, and its `SEGMENTS` entry. It renders a
bare `.` whenever `cwd` is the worktree root, which under one window per task is
nearly always.

`ROOT` exists only to build `RELPATH`, so remove it too. `CWD` must stay: the
branch fallback uses it.

## Conventions

From `~/.claude/CLAUDE.md` and this repo's history:

- **Atomic commits.** Three logical changes means at least three commits, each
  passing shellcheck on its own. Do not batch.
- **No em dashes** anywhere, in code, comments, commit messages, or the PR.
  Use a plain `-`.
- **Comment blocks stay 1-2 lines.** Keep the load-bearing "why", drop what the
  code already shows.
- **Invoke the `pr-description` skill before creating the PR.** Do not write the
  description by hand.

## Verification

Required before claiming completion:

```sh
bash -n claude/statusline.sh
shellcheck claude/statusline.sh
```

Then render against real payload shapes and paste the output into the PR. Build
the JSON in a temp file rather than a heredoc inside a compound command.

Cover at least these four cases, since three of them are the ones that break:

1. Full payload: both `resets_at` values present, `used_percentage` set.
2. `context_window` absent entirely, which is a fresh session before the first
   API call.
3. `used_percentage: null`, which is the state right after `/compact`.
4. `rate_limits` present but `resets_at` absent.

Cases 2 through 4 must render a clean line with the affected segment simply
missing, never an empty `| |` gap or a stray separator.

## Also update

- `README.md`, section **Claude Code Status Line**. The segment table lists every
  segment and must match. The section also carries `**No PR state.**` and
  `**No Salesforce org.**` notes explaining prior removals; add a matching note
  for the path segment rather than deleting its row silently. One paragraph, the
  reason, no history.
- The bullet near the top of the README summarising what the line shows.

## Optional, only if it stays cheap

`.github/workflows/ci.yml` shellchecks a hand-maintained file list that does
**not** include `claude/statusline.sh`. The file has been edited four times this
week without CI ever linting it. Adding it to the `bash -n` and `shellcheck`
lists is a one-line change per list. Flag it if you would rather not widen the
diff, but do not leave it unmentioned.

## Out of scope

- Any new segment beyond context percentage. `cost.*`, `agent.name`, `vim.mode`,
  `exceeds_200k_tokens`, `fast_mode`, `thinking.enabled`, and `version` were all
  considered and rejected as either already visible elsewhere or too static to
  read.
- `effort.level` was the borderline case. Left out on purpose. Raise it if you
  disagree, do not just add it.
- Restoring anything removed in PRs #58, #60, or #61.
