# Debian 13 (Trixie) Development Environment Setup Script

A robust, idempotent script to automate the setup of a complete and secure development environment on a fresh Debian 13 "Trixie" server.

## USAGE: 

```bash
curl -sL https://raw.githubusercontent.com/Eris-Margeta/debian-system-setup/master/system-setup.sh -o setup.sh && chmod +x setup.sh && sudo ./setup.sh
```

## Philosophy & Design

This script is specifically hardened for **Debian 13 (Trixie)**. Instead of trying to support multiple operating systems with complex logic, it focuses on doing one thing perfectly: providing a reliable, repeatable setup on the latest stable Debian release.

It strongly prefers using Debian's official APT repositories over compiling from source. This results in a faster, more stable, and more secure installation that is easier to maintain with standard system updates.

## Key Features

-   **Targeted for Debian 13**: The script first verifies it's running on "Trixie" to ensure 100% compatibility and reliability.
-   **Standardized & Provider-Agnostic APT Setup**: The first step standardizes the server's software sources to the official Debian mirrors, removing any provider-specific (e.g., Hetzner) configurations. This guarantees a consistent environment on any cloud provider.
-   **Robust, `apt`-based Installations**: Key components like **Python** and **Tmux** are no longer compiled from source. They are installed directly from the official Debian repositories for maximum stability and speed.
-   **Automatic Python Versioning**: The script intelligently detects the latest Python 3 version available in the Debian 13 repositories (e.g., `python3.13`) and installs it, removing the need for hardcoded version numbers.
-   **Built-in Verification Test**: A new "Test System" menu option runs a comprehensive suite of checks to verify that every single component has been installed and configured correctly.
-   **Slimmed-Down Neovim Dependencies**: Installs all essentials for a rich Neovim experience, including image support (`imagemagick`), but skips very large, niche dependencies like LaTeX (`texlive-full`) to significantly speed up the setup process.
-   **Comprehensive Security**: Installs and configures UFW (firewall) and Fail2ban (brute-force protection) from the very start.
-   **Full Uninstallation**: A single command can revert all changes made by the script, cleanly removing packages, configuration files, and installed binaries.
-   **User-Context Aware**: Safely installs user-specific tools (like NVM and Rust) and configuration files for the correct user, even when run with `sudo`.

## How to Use

The script provides an interactive menu. For the best results on a fresh server, follow this sequence:

1.  **Run the script**: `sudo ./setup.sh`
2.  **Step 1: Configure APT (Essential First Step)**
    -   Choose option **`A) Configure APT sources & Update System`**. This is critical to ensure your server uses the official, complete Debian software repositories.
3.  **Step 2: Install Everything**
    -   Choose option **`0) Install ALL`**. The script will securely install and configure all components in the optimal order.
4.  **Step 3: Verify the Installation**
    -   After the installation is complete, choose option **`T) Test System`**. This will run a full diagnostic check and provide a clear summary of what passed and what failed, giving you confidence that the setup is perfect.

## The "Test System" Feature

You can run the verification test at any time by choosing option `T` from the menu. It checks for:
-   Active security services (UFW, Fail2ban).
-   Correct installation of all shell tools (Zsh, Starship, Tmux).
-   Availability of all development binaries (Git, gh, lazygit, Node, Rust, Go, Python, Poetry, Docker, Neovim).
-   Existence of key configuration files and directories.

The test provides a clear pass/fail summary, so you can easily identify any issues.

## Easy Updates & Configuration

This script is designed to be easily maintainable. To update the version of a tool it installs, you only need to edit the `CONFIGURATION` section at the top of `system-setup.sh`.

**Note on Package Versions:**
-   **Python & Tmux**: These are now installed from `apt`. Their versions are managed by Debian and will be updated when you run a standard system update (`sudo apt update && sudo apt upgrade`).
-   **Go, NVM, etc.**: These are still installed from specific versions. To update them, simply edit the corresponding variable in the script.

**Example:** To upgrade the script to install a newer version of Go, edit the `GO_VERSION` variable:
```bash
# --- CONFIGURATION ---
# Easily update software versions here in the future.

GO_VERSION="1.25.4" # Change this to "1.26.0" when it's released
NVM_VERSION="0.39.7"
```

## After Installation

After running the full setup, two new files will be available in your home directory:

-   `~/setup-report.txt`: A personalized guide summarizing what was installed and providing quick "how-to" commands for key tools like `ufw`, `tmux`, `lazygit`, and `rclone`.
-   `~/compile-zsh.sh`: A script you can run (`./compile-zsh.sh`) to pre-compile your Zsh configuration files, which can make your shell start even faster.
-   `~/setup-log-*.txt`: A detailed log of the entire installation process (if logging is enabled).
