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

# Search only. Grok's X search (x_keyword_search, x_semantic_search, ...) is
# server-side and only survives without --tools: any --tools allowlist drops
# it, and an unrecognized name there silently grants the full toolset. So deny
# every client tool except web_search/web_fetch, and the driver below refuses
# to run if Grok still announces anything else.
deny=run_terminal_cmd,read_file,search_replace,list_dir,grep,todo_write,task,write
deny+=,monitor,workflow,enter_plan_mode,exit_plan_mode,ask_user_question,send_feedback
deny+=,image_gen,image_edit,image_to_video,reference_to_video,search_tool,use_tool,Agent
args=(--prompt-file "$prompt_file" --verbatim --output-format streaming-json
      --disallowed-tools "$deny" --no-subagents --no-plan
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

# Reads Grok's event stream: kills it if it exposes a non-allowlisted tool,
# prints the answer (or the final JSON object with --json), reports early stops.
driver='
import json, subprocess, sys
ALLOWED = {"web_search", "web_fetch"}
fmt, cmd = sys.argv[1], sys.argv[2:]
p = subprocess.Popen(cmd, stdout=subprocess.PIPE, text=True)
text, end = [], None
for line in p.stdout:
    try:
        e = json.loads(line)
    except ValueError:
        continue
    t = e.get("type")
    if t == "available_commands":
        extra = sorted(set(e.get("tools") or []) - ALLOWED)
        if extra:
            p.kill()
            sys.exit("ask.sh: refusing to run, grok exposed non-search tools: " + ", ".join(extra))
    elif t == "text":
        text.append(e.get("data", ""))
    elif t == "end":
        end = e
    elif t == "error":
        print("grok: " + str(e.get("message")), file=sys.stderr)
rc = p.wait()
if end is None:
    sys.exit(rc or 1)
answer = "".join(text)
if fmt == "json":
    end["text"] = answer
    print(json.dumps(end, indent=2))
else:
    print(answer)
    if end.get("stopReason") != "end_turn":
        print("[grok stopped early: stopReason=%s, turns=%s]" % (end.get("stopReason"), end.get("num_turns")), file=sys.stderr)
'

# No XAI_API_KEY so the subscription login is used, never API billing; and
# don't import the user's Claude config (CLAUDE.md, skills, MCPs, hooks).
env -u XAI_API_KEY \
  GROK_CLAUDE_AGENTS_ENABLED=false GROK_CLAUDE_SKILLS_ENABLED=false \
  GROK_CLAUDE_MCPS_ENABLED=false GROK_CLAUDE_HOOKS_ENABLED=false \
  GROK_CLAUDE_RULES_ENABLED=false \
  python3 -c "$driver" "$fmt" "$grok" "${args[@]}"

[[ -n "$new_session" ]] && printf '%s\n' "$new_session" > "$work/sessions/$name"
exit 0
