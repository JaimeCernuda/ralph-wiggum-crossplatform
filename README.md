# Ralph Wiggum - Windows Port

Windows-compatible port of the [Ralph Wiggum](https://github.com/anthropics/claude-plugins-official/tree/main/plugins/ralph-wiggum) Claude Code plugin.

Uses **PowerShell** instead of bash for full Windows compatibility.

## What is Ralph Wiggum?

The Ralph Wiggum technique is an iterative development methodology based on continuous AI loops. The same prompt is fed to Claude repeatedly, with Claude seeing its previous work in files and git history, enabling iterative refinement until task completion.

> "Ralph is a Bash loop" - Geoffrey Huntley

## Requirements

- Windows 10 or later
- PowerShell 5.1+ (included with Windows)
- Claude Code CLI

## Installation

### Option 1: Direct install (recommended)

```powershell
claude plugin add JaimeCernuda/ralph-wiggum-windows
```

### Option 2: Add marketplace and install

```powershell
# Add the marketplace
claude plugin marketplace add JaimeCernuda/ralph-wiggum-windows

# Install the plugin
claude plugin install ralph-wiggum-windows
```

### Option 3: Clone and add locally

```powershell
git clone https://github.com/JaimeCernuda/ralph-wiggum-windows.git
claude plugin add ./ralph-wiggum-windows
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

1. `/ralph-loop` creates a state file at `.claude\ralph-loop.local.md`
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

## Original Plugin

This is a Windows port of the official Anthropic plugin:
- **Original**: [anthropics/claude-plugins-official/plugins/ralph-wiggum](https://github.com/anthropics/claude-plugins-official/tree/main/plugins/ralph-wiggum)
- **Technique**: [ghuntley.com/ralph](https://ghuntley.com/ralph/)

## License

Same as the original plugin.
