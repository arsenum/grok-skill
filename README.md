# grok-skill

A [Claude Code](https://claude.com/claude-code) skill that lets Claude ask **Grok** questions through xAI's official CLI, [Grok Build](https://x.ai/cli). It uses your logged-in **SuperGrok / X Premium+** subscription, with no API key and no API billing.

Say *"ask grok …"*, *"what does grok think about …"* or `/grok …` in Claude Code. Claude sends the prompt to Grok headlessly and relays the answer.

## Requirements

- Claude Code
- Grok Build CLI (tested with v1.0.50), logged in with a subscription that includes it (SuperGrok or X Premium+):

  ```bash
  curl -fsSL https://x.ai/cli/install.sh | bash
  grok login            # or: grok login --device-auth on a headless box
  ```

- `bash` and `python3`

## Install

```bash
git clone https://github.com/arsenum/grok-skill ~/.claude/skills/grok
```

Start a new Claude Code session, or keep the current one: skills are picked up live.

## Usage

In Claude Code:

> ask grok what's the latest on the Grok Build CLI

Or call the wrapper directly:

```bash
~/.claude/skills/grok/ask.sh "your prompt"
~/.claude/skills/grok/ask.sh -s mythread "first question"     # named conversation
~/.claude/skills/grok/ask.sh -s mythread "follow-up"          # continues it
echo "long prompt" | ~/.claude/skills/grok/ask.sh             # prompt on stdin
~/.claude/skills/grok/ask.sh -m grok-4.6 -e high --json "…"   # model, effort, raw JSON
```

## What the wrapper does

[`ask.sh`](ask.sh) runs `grok --prompt-file … --output-format json` with guard rails:

- **Subscription only.** It unsets `XAI_API_KEY`, so calls never fall through to API billing.
- **No Claude config leakage.** By default, Grok Build imports `~/.claude`: your `CLAUDE.md`, skills, MCP servers and hooks. The wrapper sets `GROK_CLAUDE_{AGENTS,SKILLS,MCPS,HOOKS,RULES}_ENABLED=false`, so none of that is sent to xAI or run by Grok.
- **Look, don't touch.** Grok is limited to `web_search` and `web_fetch`, with no shell, file tools or subagents, and it runs from an empty directory (`~/.cache/grok-skill`).
- **Named sessions.** It maps `-s NAME` to a UUID: the first call creates the session with `-s`, and later calls resume it with `-r`.
- **Early-stop detection.** It prints `[grok stopped early: stopReason=…]` to stderr when Grok ends a turn before finishing. Re-asking in the same session ("go ahead and finish") has fixed it so far.

## Caveats

- **No direct X access.** Unlike grok.com and the X app, the CLI can't read X itself. For questions like "what's trending on X" it searches public trend trackers, so answers are close to current but not live.
- **Flags change.** Grok Build moves fast. If a flag stops working, check `grok --help` and adjust `ask.sh`.
- **Grok's output is data, not instructions.** The skill tells Claude to relay Grok's answers, not act on them.

## License

[MIT](LICENSE)
