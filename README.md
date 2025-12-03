# Debian System Setup Script

## USAGE: 

```bash
curl -sL https://raw.githubusercontent.com/Eris-Margeta/debian-system-setup/master/system-setup.sh -o setup.sh && chmod +x setup.sh && sudo ./setup.sh
```

This script automates the setup of a complete development environment on a fresh Debian or Ubuntu-based server. It installs everything from build tools and programming languages (Go, Rust, Node, Python) to modern tools like Docker, Neovim (with a LazyVim starter config), and Zsh.

It is designed to be idempotent, configurable, and includes a complete uninstallation routine.

## Features

- **Automated Setup**: Installs a wide range of development tools with a single command.
- **Smart Installation Order**: Prioritizes setting up the Zsh shell environment first to ensure all subsequent tools are configured correctly.
- **Automatic Shell Switching**: After a full installation, the script automatically switches your session to the new Zsh shell.
- **`.bashrc` Migration**: Intelligently copies existing configurations from `.bashrc` to `.zshrc` so you don't lose important paths (like for `cargo`).
- **Easy to Update**: Key software versions are defined in a configuration section at the top of the script for easy future updates.
- **Interactive Menu**: Choose exactly what you want to install, or run the full setup.
- **Full Uninstallation**: A single command can revert all changes made by the script, cleaning up packages, configuration files, and installed binaries.
- **User-Context Aware**: Safely installs user-specific tools (like NVM and Rust) for the user who invokes the script, even when run with `sudo`.

## The "Install ALL" Process

When you choose option `0` to install everything, the script follows a specific, logical sequence for the best results:
1.  **System Prep**: Updates packages and installs essential build tools and utilities like `curl`.
2.  **Shell Setup**: **Immediately installs Zsh** and sets it as the default login shell for your user.
3.  **Tool Installation**: Installs all other development tools (NVM, Rust, Go, etc.). Because Zsh is already the default, these tools correctly add their path configurations to `~/.zshrc`.
4.  **Finalization**: Migrates any leftover settings from `~/.bashrc`, verifies the new shell is set correctly, and automatically runs `exec zsh` to drop you into your new, fully configured environment.

## Easy Updates & Configuration

This script is designed to be easily maintainable. Instead of hardcoding versions deep inside functions, all major software versions are defined in a `CONFIGURATION` section at the top of `system-setup.sh`.

**Example:**

To upgrade the script to install a newer version of Go, simply edit the `GO_VERSION` variable:

```bash
# --- CONFIGURATION ---
# Easily update software versions here in the future.

GO_VERSION="1.25.4" # Change this to "1.26.0" when it's released
PYTHON_VERSION="3.12.3"
NVM_VERSION="0.39.7"
TMUX_VERSION="3.5a"
NEOVIM_URL="https://github.com/neovim/neovim/releases/latest/download/nvim-linux-x86_64.tar.gz"
```

After changing the version, save the script and re-run it. The script will handle the download and installation of the new version.

## Running the Script (Root vs. `sudo`)

The script must be run with root privileges.

- **If you run as a non-root user:** `sudo ./setup.sh`
- **If you are already logged in as `root`:** `./setup.sh`

The script automatically detects the original user who ran the command (e.g., `eris` in `sudo -u eris ...`). It ensures that user-level installations (like NVM, Rust, and config files in the home directory) are placed correctly for that user, while system-wide package installations are handled by `root`. This is the recommended and safest way to operate.

