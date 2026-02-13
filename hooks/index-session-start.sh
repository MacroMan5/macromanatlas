#!/bin/bash
# MacroManAtlas — Inject lightweight index summary into Claude's context at session start
INPUT=$(cat)
CWD=$(echo "$INPUT" | jq -r '.cwd')
SUMMARY="$CWD/.claude/index.summary.md"
[ -f "$SUMMARY" ] && head -c 4096 "$SUMMARY"
exit 0
