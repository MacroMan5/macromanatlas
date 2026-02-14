---
name: index-rebuild
description: "Rebuild the index for a specific module or the entire project. Accepts --module flag for targeted rebuild and --m flag for custom instructions."
disable-model-invocation: true
allowed-tools: ["Read", "Write", "Edit", "Glob", "Grep", "Bash", "AskUserQuestion"]
---

# /index-rebuild

Rebuild the project index, optionally targeting a specific module with custom instructions.

## Usage

```
/index-rebuild                              Full rebuild (all modules + index)
/index-rebuild --module MacroMan-Tracking   Rebuild only Tracking README + update index
/index-rebuild --module MacroMan-Tracking --m "Focus on TrackState machine transitions"
```

## Step 1: Parse arguments

Parse `$ARGUMENTS` for:
- `--module <name>` — target a specific module (optional)
- `--m "<instructions>"` or `--m <instructions>` — custom emphasis instructions (optional)

If no arguments: full rebuild of all modules.

## Step 2: Announce

If `--module` specified:
  Say: "Rebuilding index for module: <name>"
If full rebuild:
  Say: "Rebuilding complete project index..."

## Step 3a: Targeted rebuild (--module specified)

1. Verify the module directory exists. If not, list available modules and ask user to pick one.
2. Scan the module:
   - List files with `git ls-files <module>/` (or Glob fallback)
   - Read interface/header/export files for public API
   - Extract dependencies from build files (CMakeLists.txt, package.json, Cargo.toml, etc.)
   - Generate tags from file names, class names, function names
3. Read existing `<Module>/README.md`
4. Preserve the `<!-- CUSTOM -->` section content
5. Regenerate the `<!-- AUTO-GENERATED -->` section using the same template as /index-init Step 3
6. If `--m` instructions provided:
   - Use them to guide emphasis in the README generation (what classes to detail, what patterns to document)
   - Save the instructions in the CUSTOM section as: `**Index instructions**: <instructions>`
7. Write the updated README
8. Update `.claude/index.md`:
   - Update the module's row in the Modules table
   - Update the Tag Index for this module's tags only
9. Regenerate `.claude/index.summary.md` from `.claude/index.md` (keep under 4KB)

## Step 3b: Full rebuild (no --module flag)

Perform the same steps as `/index-init` Steps 2-4, but:
- PRESERVE all `<!-- CUSTOM -->` sections in existing READMEs
- PRESERVE the `<!-- CUSTOM -->` section in `.claude/index.md`
- Do NOT re-add the CLAUDE.md section if it already exists (look for "Code Navigation" or "Code Index")
- Do NOT modify hooks (they're managed by the plugin)
- Regenerate the "How to Use" section in `.claude/index.md` with the navigation strategy (tags → README → targeted grep)

## Step 4: Report

Summarize:
- Modules rebuilt (count or specific name)
- Files indexed
- Tags updated
- Custom instructions applied (if --m was used)

If targeted rebuild, suggest: "Run `/index-status` to verify the rebuild."
