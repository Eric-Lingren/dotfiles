---
name: how-to
description: Look up dev commands for the Standard Metrics / Quaestor-Web dev environment. Use when user asks "how do I X", "how to X", wants a command for something, or invokes /how-to <topic>.
model: haiku
effort: low
---

Read `resources/commands.md` from this skill directory. Find the section(s) most relevant to the argument.

## Rules

- Match on topic keyword(s) against section headers and inline command descriptions.
- Return only the matching section(s), verbatim. One-line section header. No added explanation unless a command has a noted prerequisite.
- If multiple sections match, return all of them.
- If no match found: reply "Not in how-to references. Check dev docs: https://standard-metrics-quaestor-web.readthedocs-hosted.com/en/latest/mkdocs/dev_environment/" and offer to add the command once the user provides it.

## Adding commands

If the user provides a new command to add, append it to the correct domain section in `resources/commands.md` and confirm.
