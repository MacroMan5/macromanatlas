#!/bin/bash
# MacroManAtlas — Check for unsynced changes when session ends
INPUT=$(cat)
CWD=$(echo "$INPUT" | jq -r '.cwd')
INDEX_FILE="$CWD/.claude/index.md"

[ -f "$INDEX_FILE" ] || exit 0

# Get modified tracked files + new untracked files
MODIFIED=$(cd "$CWD" && {
  git diff --name-only HEAD 2>/dev/null
  git status --porcelain 2>/dev/null | grep '^?' | cut -c4-
} | sort -u | head -30)

if [ -n "$MODIFIED" ]; then
  UNSYNCED=""
  while IFS= read -r file; do
    # Skip sensitive files
    case "$file" in
      .env*|.git/*|*.key|*.pem|.npmrc|.pypirc|.aws/*|.ssh/*|*credentials*|*secret*|*token*) continue ;;
    esac
    MODULE=$(echo "$file" | cut -d'/' -f1)
    README="$CWD/$MODULE/README.md"
    if [ -f "$README" ] && ! grep -q "$file" "$README" 2>/dev/null; then
      UNSYNCED="$UNSYNCED  - $file\n"
    fi
  done <<< "$MODIFIED"

  if [ -n "$UNSYNCED" ]; then
    echo "[MacroManAtlas] Files modified but not yet in index (daemon may still be syncing):"
    echo -e "$UNSYNCED"
    echo "Run /index-rebuild if the index seems stale."
  fi
fi

exit 0
