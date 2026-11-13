---
name: help
description: "Old name of /next-step. Prints one line, then runs /next-step."
argument-hint: "[optional: what you just finished, e.g. 'finished design-review' or 'stuck on ADRs']"
user-invocable: true
allowed-tools: Read, Skill(next-step)
model: haiku
---

# /help — old name of /next-step

Most AI tools keep `/help` for a command of their own, so this skill is now
`/next-step`.

1. Print this line exactly, as the first line of your reply:

   /help is now /next-step. Running /next-step.

2. Read `.agent/skills/next-step/SKILL.md` and execute the `next-step` skill workflow directly (or via the Skill tool if available), passing these arguments unchanged
   (none, if this is empty): $ARGUMENTS

Do nothing else here: `/next-step` does the work.
