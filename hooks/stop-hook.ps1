#Requires -Version 5.0
<#
.SYNOPSIS
    Ralph Wiggum Stop Hook - Windows/PowerShell version
.DESCRIPTION
    Prevents session exit when a ralph-loop is active
    Feeds Claude's output back as input to continue the loop
#>

# Wrap entire script in try-catch to prevent crashes
try {
    $ErrorActionPreference = "SilentlyContinue"

    # Read hook input from stdin reliably (works with -File invocation)
    $hookInputRaw = ""
    try {
        # Use StreamReader for reliable stdin reading
        $reader = [System.IO.StreamReader]::new([Console]::OpenStandardInput())
        $hookInputRaw = $reader.ReadToEnd()
        $reader.Close()
    } catch {
        # If stdin reading fails, try $input as fallback
        try {
            $hookInputRaw = @($input) -join "`n"
        } catch {
            $hookInputRaw = ""
        }
    }

    # Check if ralph-loop is active
    $ralphStateFile = ".claude\ralph-loop.local.md"

    if (-not (Test-Path $ralphStateFile)) {
        # No active loop - allow exit
        exit 0
    }

    # Read state file
    $content = Get-Content $ralphStateFile -Raw -ErrorAction SilentlyContinue
    if (-not $content) {
        exit 0
    }

    # Parse markdown frontmatter (YAML between ---) and extract values
    $frontmatterMatch = [regex]::Match($content, '(?s)^---\r?\n(.+?)\r?\n---')
    if (-not $frontmatterMatch.Success) {
        Write-Host "Warning: Ralph loop: Failed to parse frontmatter" -ForegroundColor Yellow
        Remove-Item $ralphStateFile -Force -ErrorAction SilentlyContinue
        exit 0
    }

    $frontmatter = $frontmatterMatch.Groups[1].Value

    # Check if loop is active
    if ($frontmatter -match 'active:\s*(false|no)') {
        # Loop is inactive - allow exit
        exit 0
    }

    # Extract values from frontmatter
    $iteration = 0
    $maxIterations = 0
    $completionPromise = $null

    foreach ($line in $frontmatter -split '\r?\n') {
        if ($line -match '^iteration:\s*(\d+)') {
            $iteration = [int]$Matches[1]
        }
        elseif ($line -match '^max_iterations:\s*(\d+)') {
            $maxIterations = [int]$Matches[1]
        }
        elseif ($line -match '^completion_promise:\s*"?([^"]*)"?') {
            $completionPromise = $Matches[1]
            if ($completionPromise -eq "null" -or [string]::IsNullOrEmpty($completionPromise)) {
                $completionPromise = $null
            }
        }
    }

    # Validate numeric fields
    if ($iteration -le 0) {
        Write-Host "Warning: Ralph loop: State file corrupted" -ForegroundColor Yellow
        Write-Host "   File: $ralphStateFile"
        Write-Host "   Problem: 'iteration' field is not a valid number"
        Write-Host ""
        Write-Host "   This usually means the state file was manually edited or corrupted."
        Write-Host "   Ralph loop is stopping. Run /ralph-loop again to start fresh."
        Remove-Item $ralphStateFile -Force -ErrorAction SilentlyContinue
        exit 0
    }

    # Check if max iterations reached
    if ($maxIterations -gt 0 -and $iteration -ge $maxIterations) {
        Write-Host "Stop: Ralph loop: Max iterations ($maxIterations) reached."
        Remove-Item $ralphStateFile -Force -ErrorAction SilentlyContinue
        exit 0
    }

    # Parse hook input JSON
    $hookInput = $null
    if (-not [string]::IsNullOrWhiteSpace($hookInputRaw)) {
        try {
            $hookInput = $hookInputRaw | ConvertFrom-Json
        } catch {
            Write-Host "Warning: Ralph loop: Failed to parse hook input JSON" -ForegroundColor Yellow
            Remove-Item $ralphStateFile -Force -ErrorAction SilentlyContinue
            exit 0
        }
    }

    if (-not $hookInput) {
        Write-Host "Warning: Ralph loop: No hook input received" -ForegroundColor Yellow
        Remove-Item $ralphStateFile -Force -ErrorAction SilentlyContinue
        exit 0
    }

    $transcriptPath = $hookInput.transcript_path

    if (-not $transcriptPath -or -not (Test-Path $transcriptPath)) {
        Write-Host "Warning: Ralph loop: Transcript file not found" -ForegroundColor Yellow
        Write-Host "   Expected: $transcriptPath"
        Write-Host "   This is unusual and may indicate a Claude Code internal issue."
        Write-Host "   Ralph loop is stopping."
        Remove-Item $ralphStateFile -Force -ErrorAction SilentlyContinue
        exit 0
    }

    # Read transcript and find last assistant message (JSONL format)
    $transcriptLines = Get-Content $transcriptPath -ErrorAction SilentlyContinue
    $assistantLines = @($transcriptLines | Where-Object { $_ -match '"role":"assistant"' })

    if ($assistantLines.Count -eq 0) {
        Write-Host "Warning: Ralph loop: No assistant messages found in transcript" -ForegroundColor Yellow
        Write-Host "   Transcript: $transcriptPath"
        Write-Host "   This is unusual and may indicate a transcript format issue"
        Write-Host "   Ralph loop is stopping."
        Remove-Item $ralphStateFile -Force -ErrorAction SilentlyContinue
        exit 0
    }

    # Get last assistant message
    $lastLine = $assistantLines[-1]

    if (-not $lastLine) {
        Write-Host "Warning: Ralph loop: Failed to extract last assistant message" -ForegroundColor Yellow
        Write-Host "   Ralph loop is stopping."
        Remove-Item $ralphStateFile -Force -ErrorAction SilentlyContinue
        exit 0
    }

    # Parse JSON and extract text content
    $lastOutput = ""
    try {
        $lastMessage = $lastLine | ConvertFrom-Json
        $textContent = @($lastMessage.message.content | Where-Object { $_.type -eq "text" } | ForEach-Object { $_.text })
        $lastOutput = $textContent -join "`n"
    } catch {
        Write-Host "Warning: Ralph loop: Failed to parse assistant message JSON" -ForegroundColor Yellow
        Write-Host "   Error: $_"
        Write-Host "   This may indicate a transcript format issue"
        Write-Host "   Ralph loop is stopping."
        Remove-Item $ralphStateFile -Force -ErrorAction SilentlyContinue
        exit 0
    }

    if ([string]::IsNullOrEmpty($lastOutput)) {
        Write-Host "Warning: Ralph loop: Assistant message contained no text content" -ForegroundColor Yellow
        Write-Host "   Ralph loop is stopping."
        Remove-Item $ralphStateFile -Force -ErrorAction SilentlyContinue
        exit 0
    }

    # Check for completion promise (only if set)
    if ($completionPromise) {
        # Extract text from <promise> tags using regex with singleline mode
        $promiseMatch = [regex]::Match($lastOutput, '(?s)<promise>(.*?)</promise>')
        if ($promiseMatch.Success) {
            $promiseText = $promiseMatch.Groups[1].Value.Trim() -replace '\s+', ' '
            if ($promiseText -eq $completionPromise) {
                Write-Host "Done: Ralph loop: Detected <promise>$completionPromise</promise>"
                Remove-Item $ralphStateFile -Force -ErrorAction SilentlyContinue
                exit 0
            }
        }
    }

    # Not complete - continue loop with SAME PROMPT
    $nextIteration = $iteration + 1

    # Extract prompt (everything after the closing ---)
    $promptMatch = [regex]::Match($content, '(?s)^---\r?\n.+?\r?\n---\r?\n(.+)$')
    $promptText = ""
    if ($promptMatch.Success) {
        $promptText = $promptMatch.Groups[1].Value.Trim()
    }

    if ([string]::IsNullOrEmpty($promptText)) {
        Write-Host "Warning: Ralph loop: State file corrupted or incomplete" -ForegroundColor Yellow
        Write-Host "   File: $ralphStateFile"
        Write-Host "   Problem: No prompt text found"
        Write-Host ""
        Write-Host "   This usually means:"
        Write-Host "     - State file was manually edited"
        Write-Host "     - File was corrupted during writing"
        Write-Host ""
        Write-Host "   Ralph loop is stopping. Run /ralph-loop again to start fresh."
        Remove-Item $ralphStateFile -Force -ErrorAction SilentlyContinue
        exit 0
    }

    # Update iteration in state file
    $newContent = $content -replace 'iteration:\s*\d+', "iteration: $nextIteration"
    [System.IO.File]::WriteAllText($ralphStateFile, $newContent, [System.Text.UTF8Encoding]::new($false))

    # Build system message with iteration count and completion promise info
    if ($completionPromise) {
        $systemMsg = "Refresh: Ralph iteration $nextIteration | To stop: output <promise>$completionPromise</promise> (ONLY when statement is TRUE - do not lie to exit!)"
    } else {
        $systemMsg = "Refresh: Ralph iteration $nextIteration | No completion promise set - loop runs infinitely"
    }

    # Output JSON to block the stop and feed prompt back
    # Use manual JSON construction to avoid encoding issues
    $escapedPrompt = $promptText -replace '\\', '\\' -replace '"', '\"' -replace "`r`n", '\n' -replace "`n", '\n' -replace "`r", '\n' -replace "`t", '\t'
    $escapedMsg = $systemMsg -replace '\\', '\\' -replace '"', '\"'

    $jsonOutput = '{"decision":"block","reason":"' + $escapedPrompt + '","systemMessage":"' + $escapedMsg + '"}'

    [Console]::WriteLine($jsonOutput)

    exit 0

} catch {
    # Global error handler - log error and allow exit to prevent crash
    Write-Host "Error: Ralph loop: Unexpected error occurred" -ForegroundColor Red
    Write-Host "   Error: $_" -ForegroundColor Red
    Write-Host "   Ralph loop is stopping to prevent crash."

    # Try to clean up state file
    try {
        $ralphStateFile = ".claude\ralph-loop.local.md"
        if (Test-Path $ralphStateFile) {
            Remove-Item $ralphStateFile -Force -ErrorAction SilentlyContinue
        }
    } catch {}

    exit 0
}
