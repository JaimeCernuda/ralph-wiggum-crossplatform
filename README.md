# Ralph Wiggum - Cross-Platform

Cross-platform port of the [Ralph Wiggum](https://github.com/anthropics/claude-plugins-official/tree/main/plugins/ralph-wiggum) Claude Code plugin.

Uses **Python** for reliable cross-platform execution (Windows, macOS, Linux).

## What is Ralph Wiggum?

The Ralph Wiggum technique is an iterative development methodology based on continuous AI loops. The same prompt is fed to Claude repeatedly, with Claude seeing its previous work in files and git history, enabling iterative refinement until task completion.

> "Ralph is a Bash loop" - Geoffrey Huntley

## Why This Port?

The official plugin uses bash scripts which don't execute reliably on Windows. Claude Code hooks are bash-centric, so PowerShell scripts also have issues. This port uses Python which:

- Works on all platforms (Windows, macOS, Linux)
- Executes reliably via Claude Code's hook system
- Has robust error handling to prevent crashes

## Requirements

- Python 3.8+ (usually pre-installed on macOS/Linux, install from python.org on Windows)
- Claude Code CLI

## Installation

**From inside Claude Code:**
```
/plugin marketplace add JaimeCernuda/ralph-wiggum-crossplatform
/plugin install ralph-wiggum-crossplatform
```

## Usage

### Start a Ralph loop

```
/ralph-loop "Build a REST API for todos" --max-iterations 20 --completion-promise "DONE"
```

**Options:**
- `--max-iterations <n>` - Stop after N iterations (recommended!)
- `--completion-promise '<text>'` - Phrase to signal completion

### Cancel a running loop

```
/cancel-ralph
```

### Get help

```
/help
```

## How It Works

1. `/ralph-loop` creates a state file at `.claude/ralph-loop.local.md`
2. When Claude tries to exit, the stop hook intercepts
3. The same prompt is fed back to Claude
4. Claude sees its previous work in files
5. Loop continues until:
   - Max iterations reached, OR
   - Claude outputs `<promise>YOUR_PHRASE</promise>`

## Example

```
/ralph-loop "Fix the authentication bug in auth.ts. Run tests after each change. Output <promise>ALL TESTS PASS</promise> when done." --completion-promise "ALL TESTS PASS" --max-iterations 15
```

## Troubleshooting

**Hook not executing?**
- Ensure Python is in your PATH: `python --version`
- Check Claude Code logs for hook errors

**Loop not stopping?**
- Manually delete `.claude/ralph-loop.local.md`
- Or run `/cancel-ralph`

## Original Plugin

This is a cross-platform port of the official Anthropic plugin:
- **Original**: [anthropics/claude-plugins-official/plugins/ralph-wiggum](https://github.com/anthropics/claude-plugins-official/tree/main/plugins/ralph-wiggum)
- **Technique**: [ghuntley.com/ralph](https://ghuntley.com/ralph/)

## License

Same as the original plugin.
