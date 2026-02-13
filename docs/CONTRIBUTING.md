# Contributing to MacroManAtlas

Thank you for your interest in improving MacroManAtlas. This guide covers how to contribute new project type detectors, improve existing ones, report bugs, and request features.

## Adding a New Project Type Detector

MacroManAtlas discovers project types by checking for specific files in the repository root. To add support for a new project type:

### 1. Define the Detection Logic

Add your project type to the detection priority table in the skill's SKILL.md file. Choose an appropriate priority number (higher = lower priority, checked later).

Your detector needs:

- **Type ID:** A short, lowercase identifier (e.g., `elixir-mix`, `zig-build`)
- **Detection signal:** The file or pattern that identifies this project type (e.g., `mix.exs`, `build.zig`)
- **Module discovery strategy:** How to find submodules/packages within the project
- **Purpose extraction:** Where to read descriptions (manifest files, comments, etc.)
- **Dependency extraction:** Which files contain dependency declarations
- **Public API extraction:** How to identify exported/public interfaces
- **File extensions:** Which extensions to index
- **Config files:** Which config files to include

### 2. Document in SUPPORTED-PROJECTS.md

Add a new section to `docs/SUPPORTED-PROJECTS.md` following the existing format:

```markdown
## your-type-id

**Detection:** `your-signal-file` exists in the repository root.

**Module discovery:** ...
**Purpose extraction:** ...
**Dependency extraction:** ...
**Public API extraction:** ...
**Extensions indexed:** ...
**Config files included:** ...

**Example output:**

(include a realistic example)
```

### 3. Test with a Sample Project

Before submitting:

1. Find or create a small project of the target type
2. Run `/index-init` and verify:
   - Correct project type detection
   - All modules discovered
   - File listings are complete and accurate
   - Tags and descriptions are reasonable
   - Dependencies are correctly extracted
   - Public API entries are meaningful
3. Run `/index-rebuild` and verify the output is stable (no unnecessary changes)
4. Verify the summary fits within 4 KB

### 4. Submit a PR

Your pull request should include:

- Updated detection logic in the skill's SKILL.md
- New section in `docs/SUPPORTED-PROJECTS.md`
- Example output from a real project (sanitized if necessary)
- Brief description of any edge cases or limitations

## Improving Existing Detectors

Common improvements:

- **Better module discovery:** Handle edge cases like nested modules, unconventional layouts, or monorepo tooling (Nx, Turborepo, Lerna, Melos)
- **Richer API extraction:** Capture more public symbols, improve description quality, handle language-specific patterns
- **More accurate tags:** Refine tag generation to be more useful for navigation
- **Additional config files:** Include config files that were previously missed

When improving a detector:

1. Describe the current behavior and why it's insufficient
2. Test the improvement against at least two real projects of that type
3. Verify the change doesn't break existing indexed projects (run `/index-rebuild` on a previously-indexed project)

## Bug Reports

Open an issue with:

- **Environment:** OS, shell (bash version), Claude Code version
- **Project type:** What kind of project you were indexing
- **Expected behavior:** What you expected to happen
- **Actual behavior:** What actually happened
- **Logs:** Relevant output from `~/.claude/logs/index-sync.log`
- **Steps to reproduce:** Minimal steps to trigger the issue

Common areas where bugs occur:

- Path handling on Windows (WSL vs Git Bash vs native)
- Large repositories (>1000 files) timing out
- Unusual directory structures not matching expected patterns
- flock/debounce race conditions
- Character encoding in file paths or content

## Feature Requests

Open an issue with:

- **Use case:** What problem are you trying to solve?
- **Proposed solution:** How you think it should work
- **Alternatives considered:** Other approaches you thought about

Feature requests that align with the project's goals (keeping Claude oriented in codebases) are most likely to be accepted.

## Development Setup

### Fork and Clone

```bash
gh repo fork MacroMan5/macromanatlas --clone
cd macromanatlas
```

### Project Structure

```
macromanatlas/
  .claude-plugin/
    plugin.json         # Plugin manifest
    marketplace.json    # Marketplace metadata
  hooks/
    hooks.json          # Hook registration
    index-session-start.sh
    index-sync-daemon.sh
    index-precompact.sh
    index-stop-check.sh
  skills/               # Skill definitions (index-init, index-status, index-rebuild)
  docs/                 # Documentation
  LICENSE
  README.md
```

### Testing Locally

1. Install the plugin from your local fork:
   ```bash
   claude plugin install /path/to/your/macromanatlas
   ```

2. Open a Claude Code session in a test project

3. Run `/index-init` and verify the output

4. Make edits and verify auto-sync fires (check `~/.claude/logs/index-sync.log`)

5. Test edge cases:
   - Empty modules
   - Binary files in the repo
   - Very large modules (100+ files)
   - Nested module structures
   - Mixed project types

### Testing Hooks

To test hooks in isolation:

```bash
# Simulate SessionStart
echo '{"cwd":"/path/to/project"}' | bash hooks/index-session-start.sh

# Simulate PostToolUse (Write)
echo '{"tool_name":"Write","tool_input":{"file_path":"/path/to/project/src/foo.cpp"},"cwd":"/path/to/project"}' | bash hooks/index-sync-daemon.sh

# Simulate Stop
echo '{"cwd":"/path/to/project"}' | bash hooks/index-stop-check.sh
```

### Verifying Changes

Before submitting a PR:

- [ ] All four hooks execute without errors
- [ ] `/index-init` completes successfully on a test project
- [ ] `/index-status` reports correct state
- [ ] `/index-rebuild` produces stable output (running twice gives the same result)
- [ ] Auto-sync fires on Write/Edit and updates the correct module
- [ ] CUSTOM sections are preserved across rebuilds
- [ ] Summary stays under 4 KB
- [ ] No sensitive files are indexed (test with a `.env` file present)
- [ ] Documentation is updated if behavior changed

## Code of Conduct

- Be respectful and constructive in all interactions
- Focus on the technical merits of contributions
- Accept feedback gracefully and provide it kindly
- Help newcomers feel welcome
- Respect the project's design decisions, or propose changes with clear reasoning

## Questions?

Open a discussion on the GitHub repository or reach out via issues. We're happy to help you get started with your contribution.
