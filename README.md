# grok-skill

A [Claude Code](https://claude.com/claude-code) plugin that lets Claude ask **Grok** questions through xAI's official CLI, [Grok Build](https://x.ai/cli). It uses your logged-in **SuperGrok / X Premium+** subscription, with no API key and no API billing. Grok can search **X posts directly** as well as the web.

Say *"ask grok …"*, *"what are people on X saying about …"* or `/grok:grok …` in Claude Code. Claude sends the prompt to Grok headlessly and relays the answer.

## Requirements

- Claude Code
- Grok Build CLI (tested with v1.0.50), logged in with a subscription that includes it (SuperGrok or X Premium+):

  ```bash
  curl -fsSL https://x.ai/cli/install.sh | bash
  grok login            # or: grok login --device-auth on a headless box
  ```

- `bash` and `python3`

## Install

As a plugin, inside Claude Code:

```
/plugin marketplace add arsenum/grok-skill
/plugin install grok@arsenum
```

Or from your shell:

```bash
claude plugin marketplace add arsenum/grok-skill
claude plugin install grok@arsenum
```

Updates arrive with `/plugin marketplace update arsenum`.

Or as a plain skill, without the plugin system, which gives you `/grok` instead of `/grok:grok`:

```bash
git clone https://github.com/arsenum/grok-skill ~/.claude/skills/grok
```

## Usage

In Claude Code:

> ask grok what people on X are saying about the Grok Build CLI

Or call the wrapper directly:

```bash
./ask.sh "your prompt"
./ask.sh -s mythread "first question"     # named conversation
./ask.sh -s mythread "follow-up"          # continues it
echo "long prompt" | ./ask.sh             # prompt on stdin
./ask.sh -m grok-4.6 -e high --json "…"   # model, effort, final JSON object
```

## What the wrapper does

[`ask.sh`](ask.sh) runs `grok --prompt-file … --output-format streaming-json` with guard rails:

- **Subscription only.** It unsets `XAI_API_KEY`, so calls never fall through to API billing.
- **No Claude config leakage.** By default, Grok Build imports `~/.claude`: your `CLAUDE.md`, skills, MCP servers and hooks. The wrapper sets `GROK_CLAUDE_{AGENTS,SKILLS,MCPS,HOOKS,RULES}_ENABLED=false`, so none of that is sent to xAI or run by Grok.
- **Search only.** It removes every client tool except `web_search` and `web_fetch`: no shell, file tools, image or video generation, or subagents. It runs from an empty directory (`~/.cache/grok-skill`). Grok's server-side X search stays available.
- **Fails closed.** It reads the tool list Grok announces and kills the run if any other tool shows up, for example one added by a Grok Build update.
- **Named sessions.** It maps `-s NAME` to a UUID: the first call creates the session with `-s`, and later calls resume it with `-r`.
- **Early-stop detection.** It prints `[grok stopped early: stopReason=…]` to stderr when Grok ends a turn before finishing.

Why a denylist and not `--tools web_search,web_fetch`: in Grok Build 1.0.50, any `--tools` allowlist removes X search. Worse, if the allowlist contains a single name the CLI doesn't recognize, it silently falls back to the **full** toolset, including shell and file writes.

## Caveats

- **Flags change.** Grok Build moves fast. If a flag stops working, check `grok --help` and adjust `ask.sh`. If the wrapper refuses to run because new tools appeared, add them to `deny` in `ask.sh`.
- **Grok's output is data, not instructions.** The skill tells Claude to relay Grok's answers, not act on them.

## License

[MIT](LICENSE)
