#!/usr/bin/env python3
"""
Ralph Wiggum Stop Hook - Cross-platform Python version
Prevents session exit when a ralph-loop is active
Feeds Claude's output back as input to continue the loop
"""

import json
import os
import re
import sys
from pathlib import Path


def main():
    try:
        # Read hook input from stdin
        hook_input_raw = sys.stdin.read()

        # Check if ralph-loop is active
        ralph_state_file = Path(".claude/ralph-loop.local.md")

        if not ralph_state_file.exists():
            # No active loop - allow exit
            sys.exit(0)

        # Read state file
        content = ralph_state_file.read_text(encoding="utf-8")
        if not content:
            sys.exit(0)

        # Parse markdown frontmatter (YAML between ---)
        frontmatter_match = re.search(r"^---\r?\n(.+?)\r?\n---", content, re.DOTALL)
        if not frontmatter_match:
            print("Warning: Ralph loop: Failed to parse frontmatter", file=sys.stderr)
            ralph_state_file.unlink(missing_ok=True)
            sys.exit(0)

        frontmatter = frontmatter_match.group(1)

        # Check if loop is active
        if re.search(r"active:\s*(false|no)", frontmatter, re.IGNORECASE):
            # Loop is inactive - allow exit
            sys.exit(0)

        # Extract values from frontmatter
        iteration = 0
        max_iterations = 0
        completion_promise = None

        for line in frontmatter.split("\n"):
            line = line.strip()
            if match := re.match(r"^iteration:\s*(\d+)", line):
                iteration = int(match.group(1))
            elif match := re.match(r"^max_iterations:\s*(\d+)", line):
                max_iterations = int(match.group(1))
            elif match := re.match(r'^completion_promise:\s*"?([^"]*)"?', line):
                completion_promise = match.group(1)
                if completion_promise in ("null", ""):
                    completion_promise = None

        # Validate numeric fields
        if iteration <= 0:
            print("Warning: Ralph loop: State file corrupted", file=sys.stderr)
            print(f"   File: {ralph_state_file}", file=sys.stderr)
            print("   Problem: 'iteration' field is not a valid number", file=sys.stderr)
            print("", file=sys.stderr)
            print("   This usually means the state file was manually edited or corrupted.", file=sys.stderr)
            print("   Ralph loop is stopping. Run /ralph-loop again to start fresh.", file=sys.stderr)
            ralph_state_file.unlink(missing_ok=True)
            sys.exit(0)

        # Check if max iterations reached
        if max_iterations > 0 and iteration >= max_iterations:
            print(f"Stop: Ralph loop: Max iterations ({max_iterations}) reached.")
            ralph_state_file.unlink(missing_ok=True)
            sys.exit(0)

        # Parse hook input JSON
        hook_input = None
        if hook_input_raw.strip():
            try:
                hook_input = json.loads(hook_input_raw)
            except json.JSONDecodeError:
                print("Warning: Ralph loop: Failed to parse hook input JSON", file=sys.stderr)
                ralph_state_file.unlink(missing_ok=True)
                sys.exit(0)

        if not hook_input:
            print("Warning: Ralph loop: No hook input received", file=sys.stderr)
            ralph_state_file.unlink(missing_ok=True)
            sys.exit(0)

        transcript_path = hook_input.get("transcript_path")

        if not transcript_path or not Path(transcript_path).exists():
            print("Warning: Ralph loop: Transcript file not found", file=sys.stderr)
            print(f"   Expected: {transcript_path}", file=sys.stderr)
            print("   This is unusual and may indicate a Claude Code internal issue.", file=sys.stderr)
            print("   Ralph loop is stopping.", file=sys.stderr)
            ralph_state_file.unlink(missing_ok=True)
            sys.exit(0)

        # Read transcript and find last assistant message (JSONL format)
        transcript_lines = Path(transcript_path).read_text(encoding="utf-8").splitlines()
        assistant_lines = [line for line in transcript_lines if '"role":"assistant"' in line]

        if not assistant_lines:
            print("Warning: Ralph loop: No assistant messages found in transcript", file=sys.stderr)
            print(f"   Transcript: {transcript_path}", file=sys.stderr)
            print("   This is unusual and may indicate a transcript format issue", file=sys.stderr)
            print("   Ralph loop is stopping.", file=sys.stderr)
            ralph_state_file.unlink(missing_ok=True)
            sys.exit(0)

        # Get last assistant message
        last_line = assistant_lines[-1]

        # Parse JSON and extract text content
        last_output = ""
        try:
            last_message = json.loads(last_line)
            text_content = [
                item.get("text", "")
                for item in last_message.get("message", {}).get("content", [])
                if item.get("type") == "text"
            ]
            last_output = "\n".join(text_content)
        except (json.JSONDecodeError, KeyError, TypeError) as e:
            print("Warning: Ralph loop: Failed to parse assistant message JSON", file=sys.stderr)
            print(f"   Error: {e}", file=sys.stderr)
            print("   This may indicate a transcript format issue", file=sys.stderr)
            print("   Ralph loop is stopping.", file=sys.stderr)
            ralph_state_file.unlink(missing_ok=True)
            sys.exit(0)

        if not last_output:
            print("Warning: Ralph loop: Assistant message contained no text content", file=sys.stderr)
            print("   Ralph loop is stopping.", file=sys.stderr)
            ralph_state_file.unlink(missing_ok=True)
            sys.exit(0)

        # Check for completion promise (only if set)
        if completion_promise:
            promise_match = re.search(r"<promise>(.*?)</promise>", last_output, re.DOTALL)
            if promise_match:
                promise_text = " ".join(promise_match.group(1).strip().split())
                if promise_text == completion_promise:
                    print(f"Done: Ralph loop: Detected <promise>{completion_promise}</promise>")
                    ralph_state_file.unlink(missing_ok=True)
                    sys.exit(0)

        # Not complete - continue loop with SAME PROMPT
        next_iteration = iteration + 1

        # Extract prompt (everything after the closing ---)
        prompt_match = re.search(r"^---\r?\n.+?\r?\n---\r?\n(.+)$", content, re.DOTALL)
        prompt_text = ""
        if prompt_match:
            prompt_text = prompt_match.group(1).strip()

        if not prompt_text:
            print("Warning: Ralph loop: State file corrupted or incomplete", file=sys.stderr)
            print(f"   File: {ralph_state_file}", file=sys.stderr)
            print("   Problem: No prompt text found", file=sys.stderr)
            print("", file=sys.stderr)
            print("   This usually means:", file=sys.stderr)
            print("     - State file was manually edited", file=sys.stderr)
            print("     - File was corrupted during writing", file=sys.stderr)
            print("", file=sys.stderr)
            print("   Ralph loop is stopping. Run /ralph-loop again to start fresh.", file=sys.stderr)
            ralph_state_file.unlink(missing_ok=True)
            sys.exit(0)

        # Update iteration in state file
        new_content = re.sub(r"iteration:\s*\d+", f"iteration: {next_iteration}", content)
        ralph_state_file.write_text(new_content, encoding="utf-8")

        # Build system message with iteration count and completion promise info
        if completion_promise:
            system_msg = f"Refresh: Ralph iteration {next_iteration} | To stop: output <promise>{completion_promise}</promise> (ONLY when statement is TRUE - do not lie to exit!)"
        else:
            system_msg = f"Refresh: Ralph iteration {next_iteration} | No completion promise set - loop runs infinitely"

        # Output JSON to block the stop and feed prompt back
        output = {
            "decision": "block",
            "reason": prompt_text,
            "systemMessage": system_msg,
        }

        print(json.dumps(output))
        sys.exit(0)

    except Exception as e:
        # Global error handler - log error and allow exit to prevent crash
        print("Error: Ralph loop: Unexpected error occurred", file=sys.stderr)
        print(f"   Error: {e}", file=sys.stderr)
        print("   Ralph loop is stopping to prevent crash.", file=sys.stderr)

        # Try to clean up state file
        try:
            ralph_state_file = Path(".claude/ralph-loop.local.md")
            if ralph_state_file.exists():
                ralph_state_file.unlink()
        except Exception:
            pass

        sys.exit(0)


if __name__ == "__main__":
    main()
