#!/bin/bash
INPUT=$(cat)

# Use node instead of jq for JSON parsing (cross-platform)
eval "$(node -e "
const d = JSON.parse(process.argv[1]);
console.log('SESSION_ID=' + JSON.stringify(d.session_id || ''));
console.log('CWD=' + JSON.stringify(d.cwd || ''));
console.log('MODEL=' + JSON.stringify(d.model || 'unknown'));
" "$INPUT")"

TELEMETRY_DIR="$HOME/.macromanatlas/telemetry"
mkdir -p "$TELEMETRY_DIR" 2>/dev/null

HAS_INDEX="false"
[ -f "$CWD/.claude/index.summary.md" ] && HAS_INDEX="true"

echo "{\"session_id\":\"$SESSION_ID\",\"start\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"cwd\":\"$(echo "$CWD" | tr '\\\\' '/')\",\"model\":\"$MODEL\",\"has_index\":$HAS_INDEX}" \
  > "$TELEMETRY_DIR/${SESSION_ID}.meta.json"
exit 0
