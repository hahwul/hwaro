+++
title = "Tools & Completion"
description = "Utility tools for content management and shell completion"
weight = 5
toc = true
+++

Hwaro includes utility tools for content management and shell completion scripts for a better CLI experience.

## Tool Commands

The `hwaro tool` command provides utility subcommands for working with content files.

| Subcommand | Description |
|------------|-------------|
| [convert](/start/tools/convert/) | Convert frontmatter between YAML and TOML formats |
| [list](/start/tools/list/) | List content files by status |
| [check-links](/start/tools/check-links/) | Check for dead links in content files |
| [stats](/start/tools/stats/) | Show content statistics |
| [validate](/start/tools/validate/) | Validate content frontmatter and markup |
| [unused-assets](/start/tools/unused-assets/) | Find unreferenced static files |
| [doctor](/start/tools/doctor/) | Diagnose config, template, and structure issues |
| [platform](/start/tools/platform/) | Generate hosting platform config files |
| [import](/start/tools/import/) | Import content from various platforms |
| [export](/start/tools/export/) | Export content to other platforms |
| [ci](/start/tools/ci/) | Generate CI/CD workflow files |
| [agents-md](/start/tools/agents-md/) | Generate or update AGENTS.md file |

---

## Shell Completion

Hwaro can generate completion scripts for your shell, providing tab completion for commands, subcommands, and flags.

### Supported Shells

| Shell | Command |
|-------|---------|
| Bash | `hwaro completion bash` |
| Zsh | `hwaro completion zsh` |
| Fish | `hwaro completion fish` |

### Installation

#### Bash

Add to your `~/.bashrc`:

```bash
eval "$(hwaro completion bash)"
```

Or save to a file:

```bash
hwaro completion bash > /etc/bash_completion.d/hwaro
```

#### Zsh

Add to your `~/.zshrc`:

```bash
eval "$(hwaro completion zsh)"
```

Or save to your fpath:

```bash
hwaro completion zsh > ~/.zsh/completions/_hwaro
```

#### Fish

Add to your `~/.config/fish/config.fish`:

```fish
hwaro completion fish | source
```

Or save to the completions directory:

```bash
hwaro completion fish > ~/.config/fish/completions/hwaro.fish
```

### What Gets Completed

The completion scripts provide tab completion for:

- **Commands**: `hwaro <TAB>` → `init`, `build`, `serve`, `new`, `deploy`, `tool`, `completion`
- **Subcommands**: `hwaro tool <TAB>` → `convert`, `list`, `stats`, `validate`, `export`, etc.
- **Flags**: `hwaro build <TAB>` → `--output`, `--drafts`, `--minify`, etc.
- **Positional arguments**: `hwaro completion <TAB>` → `bash`, `zsh`, `fish`
- **Positional choices**: `hwaro tool convert <TAB>` → `to-yaml`, `to-toml`

### Automatic Updates

Completion scripts are generated dynamically from command metadata. When you update Hwaro to a new version with new commands or flags, regenerating the completion script will automatically include them.

```bash
# Regenerate after updating hwaro
eval "$(hwaro completion bash)"
```

## See Also

- [CLI](/start/cli/) — Full CLI command reference
- [Configuration](/start/config/) — Site configuration
- [Build Hooks](/features/build-hooks/) — Custom build commands
