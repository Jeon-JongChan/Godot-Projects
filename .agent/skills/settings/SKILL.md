---
name: settings
description: "Old name of /project-settings. Prints one line, then runs /project-settings."
argument-hint: "[key | key=value | --local key=value]"
user-invocable: true
allowed-tools: Read, Skill(project-settings)
model: sonnet
---

# /settings — old name of /project-settings

Several AI tools keep `/settings` for a command of their own, so this skill is now
`/project-settings`.

1. Print this line exactly, as the first line of your reply:

   /settings is now /project-settings. Running /project-settings.

2. Read `.agent/skills/project-settings/SKILL.md` and execute the `project-settings` skill workflow directly (or via the Skill tool if available), passing these arguments unchanged
   (none, if this is empty): $ARGUMENTS

Do nothing else here: `/project-settings` does the work.
