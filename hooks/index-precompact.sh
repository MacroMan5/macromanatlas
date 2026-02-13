#!/bin/bash
# MacroManAtlas — Re-inject index summary before context compression
INPUT=$(cat)
CWD=$(echo "$INPUT" | jq -r '.cwd')
SUMMARY="$CWD/.claude/index.summary.md"
[ -f "$SUMMARY" ] && head -c 4096 "$SUMMARY"
exit 0
