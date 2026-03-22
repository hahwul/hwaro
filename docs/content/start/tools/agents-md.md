+++
title = "agents-md"
description = "Generate or update AGENTS.md file"
weight = 8
+++

Generate or update the AGENTS.md file for AI agent instructions. Useful for updating existing projects to the latest AGENTS.md or switching between content modes.

```bash
# Print local (full embedded) version to stdout
hwaro tool agents-md

# Print remote (lightweight) version to stdout
hwaro tool agents-md --remote

# Write to AGENTS.md file
hwaro tool agents-md --write

# Write remote version to file
hwaro tool agents-md --remote --write

# Overwrite without confirmation
hwaro tool agents-md --write --force
```

## Content Modes

| Mode | Description |
|------|-------------|
| `--local` (default) | Full embedded reference (~260 lines). Includes content format, template variables, configuration reference, and AI agent notes. Best for offline or local LLM environments. |
| `--remote` | Lightweight version (~50 lines). Includes project structure, essential commands, and AI agent notes with links to [online documentation](https://hwaro.hahwul.com) and [LLM reference](https://hwaro.hahwul.com/llms-full.txt). |

Both modes include a **Site-Specific Instructions** section where you can add your own project rules and conventions.

## Options

| Flag | Description |
|------|-------------|
| --remote | Generate lightweight version with links to online docs |
| --local | Generate full embedded reference (default) |
| --write | Write to AGENTS.md file instead of stdout |
| -f, --force | Overwrite existing file without confirmation |
| -h, --help | Show help |

By default, the command prints to stdout so you can inspect the content before saving. Use `--write` to save to file. If `AGENTS.md` already exists, you'll be prompted for confirmation unless `--force` is used.

## Relation to `hwaro init`

When creating a new project, `hwaro init` also generates an AGENTS.md file. You can control the content mode with the `--agents` flag:

```bash
hwaro init my-site                  # default: remote (lightweight)
hwaro init my-site --agents local   # full embedded reference
hwaro init my-site --skip-agents-md # skip AGENTS.md entirely
```

## See Also

- [CLI Reference](/start/cli/#init) — Init command options
- [CLI Reference](/start/cli/#tool) — All tool commands
