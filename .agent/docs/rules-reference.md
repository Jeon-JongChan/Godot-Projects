# Path-Specific Rules

Rules in `.agent/rules/` carry `paths:` frontmatter. Claude Code loads a
path-scoped rule **when it READS a file matching one of those globs** ??not on
every tool use, and not when it creates one.

Three consequences, and none of them are optional reading:

1. **Reading, not editing.** A rule scoped to a gameplay folder reaches the
   model when a file there is opened. An agent that writes a brand-new file in that
   directory without opening an existing one never sees it. Most work in this
   framework creates files rather than reads them, so this is the common case,
   not the corner case.
2. **Context, not enforcement.** A loaded rule is guidance the model weighs, the
   same as `CLAUDE.md`. Anything that must hold regardless of what the model
   decides belongs in a hook ??`.agent/hooks/` already enforces JSON validity
   and commit shape that way.
3. **A rule with no `paths:` loads every session**, at the same priority as
   `.agent/CLAUDE.md`. That is the lever for a rule that must always apply; it
   costs context in every session, so it is a deliberate trade, not a default.

Where a rule duplicates guidance an agent definition already carries, the two
must agree. Contradicting instructions are resolved arbitrarily, so a rule and
an agent stating different versions of the same standard is worse than either
alone.

To see which rules actually load, and why, wire the `InstructionsLoaded` hook ??`.agent/hooks/log-instructions.sh` records every instruction file and its load
reason (`session_start`, `path_glob_match`, `nested_traversal`, `include`,
`compact`) to `production/session-logs/instructions-loaded.log`.

**Globs match regardless of case.** Claude Code 2.1.282 matches `paths:`
gitignore-style and case-insensitively (observed; the docs do not say), so
`Assets/**/UI/**` also matches a Godot project's `assets/ui/` art. That is why
the Unity and Unreal code globs below name their file types.

Paths are listed Godot 쨌 Unity 쨌 Unreal. Folder names are shown in one case;
each rule's own globs list the case variants (`{AI,Ai,ai}`).

| Rule File | Path Pattern | Enforces |
| ---- | ---- | ---- |
| `gameplay-code.md` | `src/gameplay/**` 쨌 `Assets/**/Gameplay/**/*.cs` 쨌 `Source/**/Gameplay/**/*.{h,cpp}` | Data-driven values, delta time, no UI references |
| `engine-code.md` | `src/core/**` 쨌 `Assets/**/Core/**/*.cs` 쨌 `Source/**/Core/**/*.{h,cpp}` | Zero allocs in hot paths, thread safety, API stability |
| `ai-code.md` | `src/ai/**` 쨌 `Assets/**/AI/**/*.cs` 쨌 `Source/**/AI/**/*.{h,cpp}` | Performance budgets, debuggability, data-driven params |
| `network-code.md` | `src/networking/**` 쨌 `Assets/**/Network(ing)/**/*.cs` 쨌 `Source/**/Network(ing)/**/*.{h,cpp}` | Server-authoritative, versioned messages, security |
| `ui-code.md` | `src/ui/**` 쨌 `Assets/**/UI/**/*.cs` 쨌 `Source/**/UI/**/*.{h,cpp}` | No game state ownership, localization-ready, accessibility |
| `design-docs.md` | `design/gdd/**` | Required sections per `modes.workflow` (8 at `full`, 5 at `standard`), formula format, edge cases |
| `narrative.md` | `design/narrative/**` | Lore consistency, character voice, canon levels |
| `data-files.md` | `assets/data/**/*.json` 쨌 `Assets/**/Data/**/*.json` 쨌 `Content/**/Data/**/*.json` | JSON validity, naming conventions, schema rules |
| `test-standards.md` | `tests/**` 쨌 `Assets/Tests/**/*.cs` 쨌 `Source/**/Tests/**/*.{h,cpp}` | Test naming, coverage requirements, fixture patterns |
| `prototype-code.md` | `prototypes/**` | One-shot browser games (values in `config.js`, seeded randomness, plays offline) and throwaway engine or paper prototypes (relaxed standards, README, hypothesis documented) |
| `shader-code.md` | `assets/shaders/**`, `**/*.gdshader` 쨌 `Assets/**/*.{shader,hlsl,cginc,compute,shadergraph}` 쨌 `Shaders/**`, `**/*.{usf,ush}` | Naming conventions, performance targets, cross-platform rules |
| `scene-files.md` | `**/*.tscn`, `**/*.tres` 쨌 `**/*.unity`, `**/*.prefab`, `Assets/**/*.asset` 쨌 ??| Hand-edit limits for editor-written scene and asset files; Unreal `.uasset`/`.umap` are binary, and `settings.json` denies edits to them |
| `agent-memory.md` | `.agent/agent-memory/**` | The one place an agent may write unasked ??and why a temporary absence must never be recorded as a durable fact |
| `skill-authoring.md` | `.agent/skills/**`, `.agent/agents/**` | A check must be able to report that it did not run ??the five obligations for verdicts, defaults, skips, sourcing and derived coverage |

Each engine-facing rule loads on all three engines:

- **Code rules** (`gameplay`, `engine`, `ai`, `network`, `ui`) match
  `Assets/**/<System>/**/*.cs` and `Source/**/<System>/**/*.{h,cpp}` (`Core`,
  `AI`, `Networking`/`Network`, `UI` for the others).
- **`data-files.md`** matches `Assets/**/Data/**/*.json` and `Content/**/Data/**/*.json`
  ??JSON only, so C# or C++ in a `Data/` folder does not pick up its file-naming rule.
- **`shader-code.md`** matches shader files by type: `.gdshader`, `.shader`,
  `.hlsl`, `.cginc`, `.compute`, `.shadergraph`, `.usf`, `.ush`, plus `Shaders/**`.
- **`test-standards.md`** matches `Assets/Tests/**/*.cs` and `Source/**/Tests/**/*.{h,cpp}`.
- **`scene-files.md`** is the exception: Godot and Unity scene and asset files are text and have
  rules; Unreal's are binary, so a deny rule blocks edits instead of a rule guiding them.

> **`skill-authoring.md` is the odd one out and deliberately so.** Every other
> rule here scopes a *game* directory; that one scopes the **framework's own**
> authoring paths. It exists because one failure shape kept recurring across
> unrelated subsystems ??a step that could not run producing output
> indistinguishable from a step that ran and found nothing. The same mistake in
> nine places is a missing design rule, not nine mistakes.

