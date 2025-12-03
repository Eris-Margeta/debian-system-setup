# Debian System Setup Script

## USAGE: 

```bash
curl -sL https://raw.githubusercontent.com/Eris-Margeta/debian-system-setup/master/system-setup.sh -o setup.sh && chmod +x setup.sh && sudo ./setup.sh
```

This script automates the setup of a complete and secure development environment on a fresh Debian or Ubuntu-based server. It installs everything from essential security tools (firewall, anti-brute-force) and a modern shell (Zsh, Starship) to a full suite of development tools (Docker, Go, Rust, Node, Neovim).

It is designed to be idempotent, configurable, and includes a complete uninstallation routine.

## Features

-   **Comprehensive Security**: Installs and configures UFW (firewall) and Fail2ban (brute-force protection) from the very start.
-   **Modern Shell Environment**: Sets up Zsh with a rich plugin configuration, the beautiful and informative Starship prompt, and installs Nerd Fonts.
-   **Smart Installation Order**: Hardens the server with security tools first, then configures the shell environment *before* installing development tools to ensure all paths and aliases are set correctly.
-   **Automatic Shell Switching & Migration**: After a full installation, the script automatically switches your session to the new Zsh shell and intelligently migrates existing settings from `.bashrc`.
-   **Easy to Update**: Key software versions are defined in a configuration section at the top of the script for easy future updates.
-   **Full Development Suite**: Installs Docker, Go, Rust, Node.js (via NVM), Python (via source), Poetry, and Neovim with a LazyVim starter config.
-   **Full Uninstallation**: A single command can revert all changes made by the script, cleanly removing packages, configuration files, and installed binaries.
-   **User-Context Aware**: Safely installs user-specific tools (like NVM and Rust) for the correct user, even when run with `sudo`.

## The "Install ALL" Process

When you choose option `0`, the script follows a specific, logical sequence for the best results:
1.  **System Prep**: Updates packages and installs essential build tools and utilities like `curl` and `git`.
2.  **Security Hardening**: **Immediately installs and enables UFW and Fail2ban** to secure the server.
3.  **Shell Setup**: **Installs Zsh** and sets it as the default login shell. It then installs Starship and Nerd Fonts.
4.  **Tool Installation**: Installs all other development tools (NVM, Rust, Go, etc.). Because Zsh is already the default, these tools correctly add their path configurations to `~/.zshrc`.
5.  **Finalization**: Generates a `setup-report.txt` and a `compile-zsh.sh` script, then automatically runs `exec zsh` to drop you into your new, fully configured environment.

## After Installation

After running the full setup, two new files will be available in your home directory:

-   `~/setup-report.txt`: A personalized guide summarizing what was installed and providing quick "how-to" commands for key tools like `ufw`, `tmux`, and `rclone`.
-   `~/compile-zsh.sh`: A script you can run (`./compile-zsh.sh`) to pre-compile your Zsh configuration files, which can make your shell start even faster.

## Easy Updates & Configuration

This script is designed to be easily maintainable. To update the version of a tool it installs, you only need to edit the `CONFIGURATION` section at the top of `system-setup.sh`.

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

## Running the Script (Root vs. `sudo`)

The script must be run with root privileges.

-   **If you run as a non-root user:** `sudo ./setup.sh`
-   **If you are already logged in as `root`:** `./setup.sh`

The script automatically detects the original user who ran the command. It ensures that user-level installations (like NVM, Rust, and config files in `~/`) are placed correctly for that user, while system-wide package installations are handled by `root`.

