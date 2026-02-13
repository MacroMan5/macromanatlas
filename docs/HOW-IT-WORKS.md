# How It Works

Architecture and design decisions behind MacroManAtlas.

## System Overview

```
                          Claude Code Session
                                 |
            +--------------------+--------------------+
            |                    |                    |
       SessionStart         PostToolUse            Stop
            |                    |                    |
     Read summary.md      Write/Edit only?      Check unsynced
     Inject <4KB             |                   files, warn user
     into context         Extract path
            |             Determine module
       PreCompact            |
            |            Debounce 30s
     Re-inject before        |
     compression         flock -n module
                             |
                      Background claude -p
                             |
                      Update README.md
                      Update index.md
                      Regenerate summary.md
```

## Two-Level Index

MacroManAtlas maintains two index files to balance completeness with context efficiency:

### `.claude/index.md` -- Full Index

The complete index containing:

- Project metadata (type, root, timestamp)
- Module table with purposes, file counts, and dependency lists
- Per-module file listings with tags and descriptions
- Cross-reference tag index (tag -> modules that use it)
- Dependency graph summary

This file is read by the sync daemon and used for full rebuilds. It is **not** injected into Claude's context (too large).

### `.claude/index.summary.md` -- Compact Summary

A <4 KB projection of the full index, containing:

- Project type and stats (modules, files, last updated)
- Module overview table (name, purpose, key files)
- Top-level tag overview

This file is injected into Claude's context via `head -c 4096` at session start and before context compaction. The 4 KB limit ensures it fits within Claude's system prompt budget without crowding out user instructions.

## Hook Lifecycle

### SessionStart

**Trigger:** Session start, resume, clear, compact (matcher: `startup|resume|clear|compact`)

**Script:** `hooks/index-session-start.sh`

**Behavior:**

1. Reads `cwd` from hook input JSON
2. Checks if `.claude/index.summary.md` exists
3. If found, outputs the first 4096 bytes via `head -c 4096`
4. Claude receives this as context at the start of the session

**Design notes:**

- Uses `head -c` (byte limit) rather than `head -n` (line limit) for predictable size control.
- Exits 0 even if the file doesn't exist -- the plugin is silent until initialized.

### PostToolUse

**Trigger:** `Write` or `Edit` tool calls only (matcher: `Write|Edit`)

**Script:** `hooks/index-sync-daemon.sh`

**Behavior:**

1. Reads `tool_name`, `tool_input.file_path`, and `cwd` from hook input JSON
2. Validates: index must exist, path must be non-empty, not a sensitive file, not an index/README file
3. Determines the affected module from the first path component
4. Checks debounce (30-second cooldown per module)
5. Acquires a non-blocking `flock` for the module
6. Spawns a background `claude -p` daemon with a structured prompt and restricted tools
7. Daemon updates the module README and regenerates the summary
8. Logs output to `~/.claude/logs/index-sync.log`

**Why not Bash?** The hook only fires on `Write` and `Edit`, not on `Bash` tool calls. This is a deliberate design decision:

- `Write` and `Edit` provide structured `file_path` input -- reliable, unambiguous.
- `Bash` output would require parsing shell commands to guess which files were affected -- fragile, error-prone, and a security risk (command injection in parsed output).
- The tradeoff is that files created via shell commands (scaffolding scripts, `touch`, `mkdir`) won't trigger auto-sync. Users should run `/index-rebuild` after batch shell operations.

### PreCompact

**Trigger:** Before Claude compresses the context window

**Script:** `hooks/index-precompact.sh`

**Behavior:** Identical to SessionStart -- reads and outputs `index.summary.md` (first 4096 bytes).

**Purpose:** Context compaction discards earlier messages. By re-injecting the summary right before compression, Claude retains the project map in the compressed context. Without this, Claude would lose orientation after compaction.

### Stop

**Trigger:** Session end

**Script:** `hooks/index-stop-check.sh`

**Behavior:**

1. Reads `cwd` from hook input
2. If no `index.md` exists, exits silently
3. Gets modified files from `git diff --name-only HEAD` and `git status --porcelain` (untracked)
4. For each modified file (up to 30), checks if it appears in the corresponding module README
5. If files are modified but missing from the index, prints a warning with the file list
6. Suggests running `/index-rebuild`

**Purpose:** Catches files that were changed via `Bash` (not auto-synced) or during periods when the daemon was debounced/locked.

## Background Daemon

The sync daemon is the core of auto-sync. It is a `claude -p` (programmatic mode) invocation with strict constraints.

### Prompt Design

The daemon receives a structured prompt containing:

- Project root path
- Changed file path (sanitized)
- Change type (`created_or_modified` for Write, `modified` for Edit)
- Affected module name (sanitized)
- Explicit task list (read README, update file table, update tags, regenerate summary)
- Rules (no source modification, no sensitive files, style matching, atomic writes)

### Tool Restrictions

```bash
--tools "Read,Write,Edit,Glob,Grep"
--allowedTools "Read,Write,Edit,Glob,Grep"
```

The daemon cannot use `Bash`, `WebFetch`, `WebSearch`, or any other tool. This prevents:

- Accidental source code modification via shell commands
- Network access or data exfiltration
- Uncontrolled file operations

### Turn Limit

```bash
--max-turns 10
```

The daemon gets at most 10 tool calls. This is sufficient for reading the README, listing files, updating the table, and writing the result. It prevents runaway sessions.

### Logging

All daemon output (stdout and stderr) is appended to:

```
~/.claude/logs/index-sync.log
```

## Debounce Mechanism

Rapid file edits (e.g., Claude editing 5 files in the same module within seconds) would spawn 5 daemon instances. The debounce mechanism prevents this.

### Implementation

```
/tmp/.macromanatlas-<project-hash>/
  <module>.debounce    # Timestamp file (epoch seconds)
  <module>.flock       # Lock file for flock
```

- **Project hash:** `cksum` of the `cwd` path, ensuring separate namespaces for different projects.
- **Debounce file:** Contains the epoch timestamp of the last sync for that module. If `now - last < 30`, the hook exits immediately.
- **Cooldown:** 30 seconds per module. This means the last edit in a burst triggers the sync, and earlier edits are effectively batched.

### Example Timeline

```
T=0s   Edit src/Foo.cpp          -> Sync fires for module "src"
T=5s   Edit src/Bar.cpp          -> Debounced (only 5s since last sync)
T=10s  Edit src/Baz.cpp          -> Debounced (only 10s since last sync)
T=35s  Edit tests/TestFoo.cpp    -> Sync fires for module "tests" (different module)
T=40s  Edit src/Qux.cpp          -> Sync fires for module "src" (30s+ since T=0)
```

## Concurrency

### Module-Level Locking

Each module gets its own `flock` lockfile:

```
/tmp/.macromanatlas-<hash>/<module>.flock
```

`flock -n` (non-blocking) is used. If another daemon is already updating the same module, the new invocation exits immediately rather than queuing. This prevents:

- Lock contention and queuing delays
- Multiple daemons writing to the same README simultaneously
- Stale updates overwriting newer ones

### Atomic Writes

The daemon prompt instructs it to:

1. Write to a temporary file
2. Move (`mv`) the temp file to the final path

This ensures that readers (SessionStart, PreCompact) never see a partially-written file.

## Security Model

### Path Sanitization

Applied to every file path before processing:

1. **Backslash normalization:** `\` -> `/` for Windows compatibility
2. **Traversal blocking:** Paths containing `../` are rejected
3. **Sensitive file blocking:** Patterns matched and rejected:
   - `.env*`, `.git/*`, `credentials`, `secret*`, `*.key`, `*.pem`
   - `.npmrc`, `.pypirc`, `.aws/*`, `.ssh/*`, `*token*`
4. **Self-reference blocking:** Paths matching `*/.claude/*` or `*/README.md` are skipped to prevent infinite loops
5. **Module name sanitization:** `tr -cd 'a-zA-Z0-9_.-'` strips all characters except alphanumeric, dash, underscore, and dot

### Prompt Escaping

Before interpolation into the daemon prompt:

```bash
SAFE_REL_PATH=$(echo "$REL_PATH" | tr -d '`$"'"'")
SAFE_MODULE=$(echo "$MODULE" | tr -d '`$"'"'")
```

Backticks, dollar signs, and quotes are stripped to prevent prompt injection via crafted filenames.

### Tool Restriction

The daemon runs with `--tools` and `--allowedTools` set to only `Read`, `Write`, `Edit`, `Glob`, `Grep`. Even if the prompt were manipulated, the daemon cannot execute shell commands or access the network.

## AUTO-GENERATED / CUSTOM Delimiter System

Each module README uses HTML comment delimiters to separate machine-managed content from human notes:

```markdown
<!-- AUTO-GENERATED by MacroManAtlas -- do not edit above this line -->
... machine-managed file table, dependencies, API ...
<!-- AUTO-GENERATED end -->

<!-- CUSTOM -->
... your permanent notes ...
<!-- /CUSTOM -->
```

**Rules enforced by the daemon:**

- Everything between `AUTO-GENERATED` markers is regenerated on each sync
- Everything between `CUSTOM` markers is read, preserved, and written back unchanged
- If no CUSTOM section exists, one is appended as an empty block
- The daemon never deletes or modifies content inside CUSTOM markers

## File Listing

Module files are discovered via:

```bash
git ls-files <module>/
```

This respects `.gitignore` and only indexes tracked (or staged) files. Untracked files, build artifacts, and generated files are excluded automatically.

For repositories not using git, the daemon falls back to `Glob` patterns filtered by the project type's known extensions.

## Project Type Detection

Detection is performed in priority order (first match wins):

| Priority | Type | Signal |
|----------|------|--------|
| 1 | cpp-cmake | `CMakeLists.txt` in root |
| 2 | rust-cargo | `Cargo.toml` in root |
| 3 | go | `go.mod` in root |
| 4 | node-workspaces | `package.json` with `workspaces` field |
| 5 | dotnet | `*.sln` or `*.csproj` in root |
| 6 | java-maven | `pom.xml` in root |
| 7 | java-gradle | `build.gradle` or `build.gradle.kts` in root |
| 8 | python | `pyproject.toml`, `setup.py`, or `setup.cfg` in root |
| 9 | dart-flutter | `pubspec.yaml` in root |
| 10 | generic | Fallback -- indexes all top-level directories |

See [SUPPORTED-PROJECTS.md](SUPPORTED-PROJECTS.md) for detailed extraction strategies per type.

## Tag and Description Generation

The daemon generates tags and descriptions by analyzing file content:

- **Tags:** Derived from directory names, file purposes (test, config, interface, entity), and content patterns (e.g., `class I*` -> `interface` tag).
- **Descriptions:** Generated from the first documentation comment, class declaration, or module-level docstring. Truncated to 80 characters.
- **Public API:** Extracted from exported symbols, interface definitions, or public class declarations depending on language.

Tags are cross-referenced in `index.md` to enable queries like "which modules deal with detection?" by looking up the `detection` tag.
