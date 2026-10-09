#!/usr/bin/env bash
# Ask Grok via the official xAI CLI (Grok Build), using the logged-in
# SuperGrok / X Premium+ subscription rather than an API key.
#
# Usage: ask.sh [-s NAME] [-m MODEL] [-e EFFORT] [--json] PROMPT...
#        ask.sh [-s NAME] < prompt.txt
#   -s NAME   named conversation; reuse the same NAME to continue it
set -euo pipefail

name="" model="" effort="" fmt="plain"
while [[ $# -gt 0 ]]; do
  case "$1" in
    -s) name="$2"; shift 2 ;;
    -m) model="$2"; shift 2 ;;
    -e) effort="$2"; shift 2 ;;
    --json) fmt="json"; shift ;;
    --) shift; break ;;
    *) break ;;
  esac
done

prompt="$*"
if [[ -z "$prompt" && ! -t 0 ]]; then
  prompt="$(cat)"
fi
if [[ -z "$prompt" ]]; then
  echo "usage: ask.sh [-s NAME] [-m MODEL] [-e EFFORT] [--json] PROMPT  (or pipe the prompt on stdin)" >&2
  exit 2
fi
if [[ -n "$name" && ! "$name" =~ ^[A-Za-z0-9._-]+$ ]]; then
  echo "session name may only contain letters, digits, '.', '_' and '-'" >&2
  exit 2
fi

grok="$(command -v grok || true)"
[[ -z "$grok" && -x "$HOME/.grok/bin/grok" ]] && grok="$HOME/.grok/bin/grok"
if [[ -z "$grok" ]]; then
  echo "grok CLI not installed. Install: curl -fsSL https://x.ai/cli/install.sh | bash   then: grok login" >&2
  exit 127
fi

# Fixed empty working dir: Grok sessions are keyed by cwd, and nothing of the
# caller's project is in reach.
work="${XDG_CACHE_HOME:-$HOME/.cache}/grok-skill"
mkdir -p "$work/sessions"

prompt_file="$(mktemp "$work/prompt.XXXXXX")"
trap 'rm -f "$prompt_file"' EXIT
printf '%s' "$prompt" > "$prompt_file"

# Chat only: web tools, no shell/file tools, no subagents.
# Always ask for JSON: plain mode once printed only the opening line with no
# stop reason. For plain, print .text and surface any early stop.
args=(--prompt-file "$prompt_file" --verbatim --output-format json
      --tools web_search,web_fetch --disallowed-tools Agent --no-subagents --no-plan
      --max-turns 20 --no-auto-update --no-alt-screen --cwd "$work")
[[ -n "$model" ]] && args+=(-m "$model")
[[ -n "$effort" ]] && args+=(--reasoning-effort "$effort")

# -s only creates a session (and needs a UUID); -r resumes one.
new_session=""
if [[ -n "$name" ]]; then
  if [[ -s "$work/sessions/$name" ]]; then
    args+=(-r "$(cat "$work/sessions/$name")")
  else
    new_session="$( (uuidgen 2>/dev/null || python3 -c 'import uuid; print(uuid.uuid4())') | tr 'A-Z' 'a-z')"
    args+=(-s "$new_session")
  fi
fi

# No XAI_API_KEY so the subscription login is used, never API billing; and
# don't import the user's Claude config (CLAUDE.md, skills, MCPs, hooks).
out="$(env -u XAI_API_KEY \
  GROK_CLAUDE_AGENTS_ENABLED=false GROK_CLAUDE_SKILLS_ENABLED=false \
  GROK_CLAUDE_MCPS_ENABLED=false GROK_CLAUDE_HOOKS_ENABLED=false \
  GROK_CLAUDE_RULES_ENABLED=false \
  "$grok" "${args[@]}")" || { rc=$?; [[ -n "${out:-}" ]] && printf '%s\n' "$out"; exit "$rc"; }

if [[ "$fmt" == json ]]; then
  printf '%s\n' "$out"
else
  printf '%s' "$out" | python3 -c '
import json, sys
raw = sys.stdin.read()
try:
    d = json.loads(raw)
except ValueError:
    sys.stdout.write(raw + "\n"); sys.exit(0)
print(d.get("text", ""))
stop, turns = d.get("stopReason"), d.get("num_turns")
if stop != "end_turn":
    print(f"[grok stopped early: stopReason={stop}, turns={turns}]", file=sys.stderr)
'
fi

[[ -n "$new_session" ]] && printf '%s\n' "$new_session" > "$work/sessions/$name"
exit 0
