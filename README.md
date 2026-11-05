# Reproducible Workspace

This repository is the source of truth for the portable parts of a macOS workspace: shell dotfiles, application configuration, dependency requirements, and references to reusable repositories.

It is deliberately conservative. It never moves, edits, replaces, backs up, or updates an existing path on a machine. You manually add your own configuration files to this repository; the bootstrap only creates a symlink or clones an external repository when its destination does not yet exist.

## Repository layout

| Path | Purpose |
| --- | --- |
| `home/` | Files and directories to link directly under `$HOME`, such as `.zshrc` and `.profile`. |
| `config/` | Files and directories to link under `$HOME/.config`, such as Starship configuration. |
| `manifests/links.conf` | Explicit mapping from a repository source to its destination under `$HOME`. |
| `manifests/dependencies.conf` | Tools and applications to validate and document. |
| `manifests/repositories.conf` | Reusable repositories to clone into `~/workspace`. |
| `scripts/bootstrap.sh` | Safe validation, linking, and repository-cloning entry point. |

## Prerequisites

- macOS
- Bash
- Git

Homebrew is optional. The check command reports whether it is available and prints the installation hint recorded for missing optional dependencies.

## Add a configuration item

1. Manually copy or create the configuration inside `home/` or `config/`.
2. Add one pipe-separated row to `manifests/links.conf`:

   ```text
   config/starship.toml | .config/starship.toml
   ```

3. Confirm that the target path does not already exist on the machine.
4. Run `./scripts/bootstrap.sh --link`.

The first field is a repository-relative source path. The second is a path relative to `$HOME`. Absolute paths and parent-directory traversal are rejected.

For Herdr, its portable configuration belongs in `config/herdr/config.toml` and should be linked to `.config/herdr/config.toml`. Herdr reads this file on macOS and Linux. Install the terminal application with `brew install herdr`.

## Commands

```sh
./scripts/bootstrap.sh --check
./scripts/bootstrap.sh --link
./scripts/bootstrap.sh --repos
```

- `--check` is read-only. It validates macOS, Git, Homebrew, and declared dependencies.
- `--link` creates only missing destination symlinks and accepts an already-correct link without changing it. It stops before changing anything when a listed destination exists but is not the expected link, or when a source is missing.
- `--repos` clones only missing repositories from `manifests/repositories.tsv` into `~/workspace`. It does not fetch, pull, reset, or otherwise change an existing directory or repository.

Run one action at a time. Use `--help` to print the command reference.

## Dependency manifest

`manifests/dependencies.conf` has four pipe-separated fields:

```text
kind | name | check | installation_hint
```

- `cli`: `check` is an executable name resolved with `command -v`.
- `app`: `check` is an application bundle path, normally below `/Applications`.
- `manual`: reported as informational because no reliable local check is defined; set `check` to `-`.

The manifest is intentionally not an installer. It gives each machine a reproducible requirements list without changing its package state.

## External repositories

`manifests/repositories.conf` has three pipe-separated fields:

```text
name | url | destination_relative_to_workspace
```

For example:

```text
ai-resources | git@github.com:example/ai-resources.git | ai-resources
```

External repositories remain independent Git repositories. This workspace repository does not use submodules and does not duplicate their contents.

## Safety and secrets

- Never commit API keys, tokens, private keys, credentials, or machine-specific secrets.
- Put local-only values in ignored files such as `.env`, `.env.<resource>`, or `.workspace-local/`.
- Commit safe templates for those files as `.env.example` or `.env.<resource>.example`; leave secrets and real values out of every template.
- Resolve every destination conflict manually. The bootstrap will not rename or back up an existing item for you.
- Review `git status` before committing configuration changes.

## Extending the workspace

When adding a new tool, add its portable configuration manually under `home/` or `config/`, declare its link in `links.conf`, declare its validation/install hint in `dependencies.conf`, and document any tool-specific manual setup in this README or a dedicated English document.
