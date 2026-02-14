#!/bin/bash
INPUT=$(cat)

# Use node instead of jq for JSON parsing (cross-platform)
eval "$(node -e "
const d = JSON.parse(process.argv[1]);
console.log('SESSION_ID=' + JSON.stringify(d.session_id || ''));
console.log('TOOL_NAME=' + JSON.stringify(d.tool_name || ''));
" "$INPUT")"

TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)

TELEMETRY_DIR="$HOME/.macromanatlas/telemetry"
mkdir -p "$TELEMETRY_DIR" 2>/dev/null

echo "{\"ts\":\"$TIMESTAMP\",\"tool\":\"$TOOL_NAME\"}" \
  >> "$TELEMETRY_DIR/${SESSION_ID}.tools.jsonl"
exit 0
