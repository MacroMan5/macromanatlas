#!/bin/bash
# MacroManAtlas — Auto-sync daemon, spawns background claude -p after file changes
# Requirements: bash, jq, flock
# Triggered async by hooks.json on Write/Edit only (no Bash parsing)

INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name')
CWD=$(echo "$INPUT" | jq -r '.cwd')
INDEX_FILE="$CWD/.claude/index.md"

# Exit early if no index exists (project not initialized)
[ -f "$INDEX_FILE" ] || exit 0

# --- Determine file path and change type (Write/Edit only, structured) ---
FILE_PATH=""
CHANGE_TYPE=""

case "$TOOL_NAME" in
  Write)
    FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path')
    CHANGE_TYPE="created_or_modified"
    ;;
  Edit)
    FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path')
    CHANGE_TYPE="modified"
    ;;
  *)
    exit 0
    ;;
esac

[ -z "$FILE_PATH" ] && exit 0

# --- Security: sanitize and validate path ---
# Normalize path separators
FILE_PATH=$(echo "$FILE_PATH" | tr '\\' '/')

# Block path traversal and sensitive files
case "$FILE_PATH" in
  *../*|*/.git/*|*/.env*|*credentials*|*secret*|*.key|*.pem|*/.npmrc|*/.pypirc|*/.aws/*|*/.ssh/*|*token*) exit 0 ;;
esac

# Skip index/hook/README files (avoid infinite loop)
case "$FILE_PATH" in
  */.claude/*|*/README.md) exit 0 ;;
esac

# --- Determine affected module ---
REL_PATH="${FILE_PATH#$CWD/}"
REL_PATH="${REL_PATH#$CWD\\}"
REL_PATH=$(echo "$REL_PATH" | tr '\\' '/')
MODULE=$(echo "$REL_PATH" | cut -d'/' -f1)

# Sanitize MODULE name (alphanumeric, dash, underscore, dot only)
MODULE=$(echo "$MODULE" | tr -cd 'a-zA-Z0-9_.-')
[ -z "$MODULE" ] && exit 0

# --- Debounce: 30 second cooldown per module, namespaced per project ---
PROJECT_HASH=$(cksum <<< "$CWD" | awk '{print $1}')
LOCK_DIR="/tmp/.macromanatlas-${PROJECT_HASH}"
mkdir -p "$LOCK_DIR" 2>/dev/null
DEBOUNCE_FILE="$LOCK_DIR/${MODULE}.debounce"
NOW=$(date +%s)

if [ -f "$DEBOUNCE_FILE" ]; then
  LAST=$(cat "$DEBOUNCE_FILE" 2>/dev/null || echo "0")
  [ $((NOW - LAST)) -lt 30 ] && exit 0
fi
echo "$NOW" > "$DEBOUNCE_FILE"

# --- Concurrency: flock per module to prevent corruption ---
MODULE_LOCK="$LOCK_DIR/${MODULE}.flock"
LOG_DIR="$HOME/.claude/logs"
mkdir -p "$LOG_DIR" 2>/dev/null

# Escape REL_PATH for safe prompt interpolation (remove quotes, backticks, $)
SAFE_REL_PATH=$(echo "$REL_PATH" | tr -d '`$"'"'")
SAFE_MODULE=$(echo "$MODULE" | tr -d '`$"'"'")

(
  flock -n 200 || exit 0  # Skip if another sync for this module is running

  claude -p "You are an index maintenance daemon. Update the project index after a file change. Be fast and precise.

Project root: $CWD
File changed: $SAFE_REL_PATH
Change type: $CHANGE_TYPE
Module affected: $SAFE_MODULE

Tasks:
1. Read $SAFE_MODULE/README.md (if exists)
2. If CREATED: use git ls-files to list module files, add new file to Files table with tags + description
3. If MODIFIED: Re-read file, update tags/description if public API changed
4. Update .claude/index.md tag index if tags changed
5. Regenerate .claude/index.summary.md from .claude/index.md (keep under 4KB)
6. PRESERVE everything between <!-- CUSTOM --> and end of file
7. PRESERVE AUTO-GENERATED delimiters
8. Write to temp file first, then move into place (atomic write)

Rules:
- Do NOT modify source code files
- Do NOT read or index .env, .git/, .npmrc, .pypirc, .aws/, .ssh/, credentials, secrets, key files
- Keep descriptions under 80 chars
- Match existing style
- Only use Read, Write, Edit, Glob, Grep tools" \
    --tools "Read,Write,Edit,Glob,Grep" \
    --allowedTools "Read,Write,Edit,Glob,Grep" \
    --max-turns 10 \
    >> "$LOG_DIR/index-sync.log" 2>&1

) 200>"$MODULE_LOCK"

exit 0
