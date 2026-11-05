# Workframe

[![Validate Workframe](https://github.com/lc-rezende/Workframe/actions/workflows/validate.yml/badge.svg)](https://github.com/lc-rezende/Workframe/actions/workflows/validate.yml)

> Version your Mac workspace once. Reproduce it anywhere.

A macOS workspace template and bootstrap utility for reproducing your setup on any new Mac or user account.

This template deliberately does not include personal configuration. Create a private repository from it, then manually add your own files. The bootstrap never moves, edits, replaces, backs up, or updates an existing path on a machine.

## Repository layout

| Path | Purpose |
| --- | --- |
| `home/` | Files and directories to link directly under `$HOME`, such as `.zshrc`. |
| `config/` | Files and directories to link under `$HOME/.config`. |
| `manifests/links.conf` | Explicit mapping from a repository source to its destination under `$HOME`. |
| `manifests/dependencies.conf` | Tools and applications to validate and document. |
| `manifests/repositories.conf` | Reusable repositories to clone into `~/workspace`. |
| `scripts/bootstrap.sh` | Safe validation, linking, and repository-cloning entry point. |

## Prerequisites

- macOS
- Bash
- Git

Homebrew is optional. The template validates Git only by default; add your own optional tools to the dependency manifest.

## Add a configuration item

1. Manually copy or create the configuration inside `home/` or `config/`.
2. Add one pipe-separated row to `manifests/links.conf`:

   ```text
   config/starship.toml | .config/starship.toml
   ```

3. Confirm that the target path does not already exist on the machine.
4. Run `./scripts/bootstrap.sh --link`.

The first field is a repository-relative source path. The second is a path relative to `$HOME`. Absolute paths and parent-directory traversal are rejected.

## Commands

```sh
./scripts/bootstrap.sh --check
./scripts/bootstrap.sh --link
./scripts/bootstrap.sh --repos
```

- `--check` is read-only. It validates macOS, Git, Homebrew, and declared dependencies.
- `--link` creates only missing destination symlinks and accepts an already-correct link without changing it. It stops before changing anything when a listed destination exists but is not the expected link, or when a source is missing.
- `--repos` clones only missing repositories from `manifests/repositories.conf` into `~/workspace`. It does not fetch, pull, reset, or otherwise change an existing directory or repository.

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

## Optional tool examples

Add only the tools you use. For example:

```text
# manifests/dependencies.conf
cli | starship | starship | brew install starship
cli | herdr | herdr | brew install herdr
app | Visual Studio Code | /Applications/Visual Studio Code.app | brew install --cask visual-studio-code
app | iTerm | /Applications/iTerm.app | brew install --cask iterm2
```

```text
# manifests/links.conf
config/starship.toml | .config/starship.toml
config/herdr/config.toml | .config/herdr/config.toml
```

The sources in those examples must be manually added to this repository before running `--link`.

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

## Create your private workspace

Use GitHub's **Use this template** action to create a private repository. Keep personal dotfiles, private repository references, and real environment values only in that private repository. The public template should contain only generic tooling, documentation, and safe examples.

To adopt public-template improvements later, add this repository as an `upstream` remote in your private repository and merge or cherry-pick changes deliberately after reviewing them.

## Contributing

Contributions should improve the generic template without adding personal configuration, credentials, user-specific paths, or private repository URLs. Test the bootstrap commands and keep documentation in English before opening a pull request.

## Continuous integration

GitHub Actions runs the functional bootstrap test suite on macOS for every pull request and every push to `main`. The suite validates shell syntax, manifest parsing, safe link creation, idempotent links, conflict protection, repository cloning, and existing-destination protection.

Run the same checks locally with:

```sh
bash tests/bootstrap_test.sh
```

## Extending the workspace

When adding a new tool, add its portable configuration manually under `home/` or `config/`, declare its link in `links.conf`, declare its validation/install hint in `dependencies.conf`, and document any tool-specific manual setup in this README or a dedicated English document.
