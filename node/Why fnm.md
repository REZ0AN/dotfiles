# Node.js Version Management on Windows using fnm

## Overview

[fnm (Fast Node Manager)](https://github.com/Schniz/fnm) is a lightweight Node.js version manager that lets us install and switch between multiple Node.js versions.

### Why use fnm on Windows?

Different projects may require different Node.js versions. For example, a legacy application might need Node.js 14, while modern applications and development tools require Node.js 24.

Unlike **nvm-windows**, which switches Node.js versions through a shared system symlink, fnm supports independent versions per terminal session.

| Feature | nvm-windows | fnm |
|---|---|---|
| Multiple Node versions | Yes | Yes |
| Per-terminal isolation | No | Yes |
| Automatic project switching | No native support | Yes |
| `.nvmrc` support | No native support | Yes |
| Windows PowerShell support | Yes | Yes |

## Installation

Install fnm using Chocolatey:

```powershell
choco install fnm -y
```

Verify:

```powershell
fnm --version
```

## PowerShell Configuration

To automatically initialize fnm and switch Node.js versions when changing directories, open your PowerShell profile:

```powershell
notepad $PROFILE
```

Add:

```powershell
fnm env --use-on-cd --shell powershell | Out-String | Invoke-Expression
```

Restart PowerShell or reload the profile:

```powershell
. $PROFILE
```

## Basic Commands

| Command | Description |
|---|---|
| `fnm install 24.22.3` | Install Node.js 24.22.3 |
| `fnm install 14.21.3` | Install Node.js 14.21.3 |
| `fnm list` | List installed versions |
| `fnm list-remote` | List available Node.js versions |
| `fnm use 14.21.3` | Switch Node version in the current terminal |
| `fnm default 24.22.3` | Set the default Node version |
| `fnm current` | Show the active Node version |
| `fnm uninstall 14.21.3` | Remove an installed Node version |

## Project-Specific Node.js Versions

Create an `.nvmrc` file inside the project directory.

Example:

```text
hrm-erp-frontend/
├── .nvmrc
├── package.json
└── src/
```

Set the required version:

```powershell
cd D:\nsl-projects\hrm-erp-frontend

Set-Content .nvmrc "14.21.3"
```

With `--use-on-cd` configured, fnm automatically activates Node.js 14 when entering the project directory.

Verify:

```powershell
node -v
# v14.21.3
```

When moving to another project with a different `.nvmrc`, fnm automatically switches to that version. If no version file is found, it uses the configured default.

## Example Workflow

**Terminal 1 — Legacy project**

```powershell
cd D:\nsl-projects\hrm-erp-frontend
node -v
# v14.21.3
```

**Terminal 2 — Modern development**

```powershell
cd $HOME
node -v
# v24.22.3
```

Both terminals can use different Node.js versions simultaneously.

## Important Notes

- Keep `.nvmrc` in Git so other developers know which Node.js version the project requires.
- Use an actively supported Node.js version for general development.
- Node.js 14 is end-of-life and should only be used where required by legacy applications.
- Global npm packages are associated with their respective Node.js installations and may need separate installation.
- Prefer native installations for tools such as Codex CLI and Claude Code to avoid Node.js version compatibility issues.

## References

- [fnm — Official GitHub Repository](https://github.com/Schniz/fnm)
- [Node.js — Official Website](https://nodejs.org/)
- [Node.js Release Schedule](https://nodejs.org/en/about/previous-releases)
- [Chocolatey Package Manager](https://chocolatey.org/)
