---
name: index-status
description: "Show the current state of the project index: staleness, module coverage, hook health, and recent sync activity. Use to diagnose index issues."
disable-model-invocation: true
allowed-tools: ["Read", "Glob", "Grep", "Bash"]
---

# /index-status

Show the health and status of the project index.

## Step 1: Announce

Say: "Checking MacroManAtlas index status..."

## Step 2: Check index existence

Read `.claude/index.md`. If it doesn't exist, report:
```
MacroManAtlas Status
────────────────
⚠ No index found. Run /index-init to generate one.
```
And stop.

## Step 3: Parse index metadata

From `.claude/index.md`, extract:
- Generation timestamp
- Project type
- Module count
- File count

## Step 4: Check each module

For each module listed in the index:
1. Check if `<Module>/README.md` exists
2. Get the README's last modification time (use `git log -1 --format=%ci -- <Module>/README.md` or Bash `stat`)
3. Get the latest file modification in the module (use `git log -1 --format=%ci -- <Module>/`)
4. Count files in filesystem: `git ls-files <Module>/ | wc -l` (or Glob fallback)
5. Count files listed in the README's Files table
6. Compare: if filesystem has more files than README, mark as stale

Status symbols:
- ✓ = README exists and is fresh (no newer files than README)
- ⚠ = README exists but stale (newer files not indexed)
- ✗ = No README.md found

## Step 5: Check hooks

Read the plugin's hooks.json to verify hook registration. Check for:
- SessionStart hook
- PostToolUse hook
- PreCompact hook
- Stop hook

## Step 6: Check recent sync activity

Read last 20 lines of `~/.claude/logs/index-sync.log` (if exists).
Extract the most recent sync: module name and timestamp.

## Step 7: Present dashboard

Format output as:

```
MacroManAtlas Status
────────────────
Index: .claude/index.md (generated <time ago>)
Type: <project-type> | Modules: <N> | Indexed files: <N>

Module Health:
  ✓ ModuleName          — <N> files, README fresh
  ⚠ ModuleName          — <N> files, README stale (<N> new files not indexed)
  ✗ ModuleName          — no README.md

Hooks: SessionStart ✓ | PostToolUse ✓ | PreCompact ✓ | Stop ✓
Last sync: <module> (<time ago>) — <change_type>
```

If no sync log exists, show: `Last sync: no activity recorded`
