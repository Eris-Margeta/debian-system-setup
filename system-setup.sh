#!/bin/bash
# ==========================================================
# Remote Development Environment Setup Script
# TARGET: DEBIAN 13 (TRIXIE)
# ==========================================================
# Version: 6.0.0 (Apt Tmux & Verification Test)
# Last Updated: Dec 7, 2025

# --- CONFIGURATION ---
# Easily update software versions and settings here in the future.

# GENERAL
GO_VERSION="1.25.4"
NVM_VERSION="0.39.7"
# TMUX_VERSION is no longer needed as we install from apt.
NEOVIM_URL="https://github.com/neovim/neovim/releases/latest/download/nvim-linux-x86_64.tar.gz"

# SCRIPT BEHAVIOR
ENABLE_LOGGING=true # Set to false to disable logging to a file.

# --- SCRIPT CORE ---

# Set up colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m'

# Script needs to be run as root or with sudo
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}Please run as root or with sudo${NC}"
  exit 1
fi

# Store the actual user who ran the script
if [ -z "$SUDO_USER" ]; then ACTUAL_USER="$(whoami)"; else ACTUAL_USER="$SUDO_USER"; fi
ACTUAL_HOME="$(eval echo ~"$ACTUAL_USER")"

# Configure logging if enabled
if [ "$ENABLE_LOGGING" = true ]; then
  LOG_FILE="$ACTUAL_HOME/setup-log-$(date +'%Y-%m-%d_%H-%M-%S').txt"
  # Redirect stdout and stderr to a log file while also printing to the console
  exec &> >(tee -a "$LOG_FILE")
  chown "$ACTUAL_USER":"$ACTUAL_USER" "$LOG_FILE"
  echo "Logging enabled. Output is being saved to $LOG_FILE"
fi

# Verify Debian Version
if ! grep -q 'VERSION_CODENAME=trixie' /etc/os-release; then
  log_error "This script is specifically designed for Debian 13 (Trixie)."
  log_error "Your system appears to be a different version. Aborting."
  exit 1
fi

# --- HELPER FUNCTIONS ---

log_error() { echo -e "${RED}ERROR: $1${NC}"; }
log_info() { echo -e "${BLUE}$1${NC}"; }
log_success() { echo -e "${GREEN}$1${NC}"; }

show_banner() {
  clear
  echo -e "${BLUE}${BOLD}"
  echo "====================================================="
  echo "      Remote Development Environment Setup Script    "
  echo "                (For Debian 13 Trixie)               "
  echo "====================================================="
  echo -e "${NC}"
  echo "This script will set up your development environment."
  echo ""
}

purge_packages() {
  local packages_to_remove=()
  for pkg in "$@"; do if dpkg -l | grep -q "ii  $pkg "; then packages_to_remove+=("$pkg"); fi; done
  if [ ${#packages_to_remove[@]} -gt 0 ]; then
    log_info "Purging packages: ${packages_to_remove[*]}"
    if ! apt purge -y "${packages_to_remove[@]}"; then log_error "Failed to purge packages."; fi
  fi
}

# --- INSTALLATION FUNCTIONS ---

configure_apt_sources() {
  log_info "Configuring APT to use official Debian mirrors for maximum compatibility..."
  # Back up existing configuration robustly
  if [ -d "/etc/apt/sources.list.d" ]; then mv /etc/apt/sources.list.d /etc/apt/sources.list.d.bak; fi
  if [ -f "/etc/apt/sources.list" ]; then mv /etc/apt/sources.list /etc/apt/sources.list.bak; fi
  mkdir -p /etc/apt/sources.list.d # Ensure the directory exists for other installers

  # Create a new, clean sources.list pointing to official Debian repos
  tee /etc/apt/sources.list >/dev/null <<'EOF'
deb http://deb.debian.org/debian/ trixie main contrib non-free-firmware
deb-src http://deb.debian.org/debian/ trixie main contrib non-free-firmware

deb http://deb.debian.org/debian-security/ trixie-security main contrib non-free-firmware
deb-src http://deb.debian.org/debian-security/ trixie-security main contrib non-free-firmware

deb http://deb.debian.org/debian/ trixie-updates main contrib non-free-firmware
deb-src http://deb.debian.org/debian/ trixie-updates main contrib non-free-firmware
EOF
  log_success "APT sources configured to use official Debian mirrors."
  update_system
}

update_system() {
  log_info "Updating system packages..."
  apt update -y && apt upgrade -y
  log_success "System updated."
}
install_build_essentials() {
  log_info "Installing build tools..."
  apt install -y build-essential make libssl-dev gettext unzip cmake
  log_success "Build tools installed."
}
install_firewall() {
  log_info "Installing and configuring UFW firewall..."
  apt install -y ufw
  ufw allow ssh
  ufw --force enable
  ufw status verbose
  log_success "Firewall enabled. SSH is allowed."
}
install_fail2ban() {
  log_info "Installing Fail2ban..."
  apt install -y fail2ban
  systemctl enable fail2ban && systemctl start fail2ban
  log_success "Fail2ban installed and enabled."
}

install_zsh() {
  log_info "Installing ZSH and zplug..."
  apt install -y zsh zplug
  if [ -f "$ACTUAL_HOME/.zshrc" ]; then mv "$ACTUAL_HOME/.zshrc" "$ACTUAL_HOME/.zshrc.bak"; fi
  local python_executable
  python_executable=$(apt-cache search --names-only '^python3\.[0-9]+$' | sort -V | tail -n 1 | awk '{print $1}')
  if [ -z "$python_executable" ]; then python_executable="python3"; fi

  cat >"$ACTUAL_HOME/.zshrc" <<EOL
export TERM=xterm
HISTFILE=~/.zsh_history; HISTSIZE=5000; SAVEHIST=5000
alias ec="nvim ~/.zshrc"; alias ep="nvim ~/.config/starship.toml"; alias sc="source ~/.zshrc"; alias ls="lsd"; alias fd="fdfind"
alias python='$python_executable'
source /usr/share/zplug/init.zsh
zplug "zsh-users/zsh-syntax-highlighting"; zplug "zsh-users/zsh-autosuggestions"
if ! zplug check; then zplug install; fi
zplug load
EOL
  chown "$ACTUAL_USER":"$ACTUAL_USER" "$ACTUAL_HOME/.zshrc" && chsh -s "$(command -v zsh)" "$ACTUAL_USER"
  log_success "ZSH setup completed."
}

install_starship() {
  log_info "Installing Starship prompt..."
  su - "$ACTUAL_USER" -c "curl -sS https://starship.rs/install.sh | sh -s -- -y"
  echo -e '\neval "$(starship init zsh)"' >>"$ACTUAL_HOME/.zshrc"
  mkdir -p "$ACTUAL_HOME/.config"
  cat >"$ACTUAL_HOME/.config/starship.toml" <<'EOL'
# ~/.config/starship.toml
add_newlformat = """
└── $username$hostname $directory$git_branch$git_status$python$nodejs$rust$golang$cmd_duration
$character"""
add_newline = true

[character]
success_symbol = "[➜](bold green)"
error_symbol = "[➜](bold red)"
vicmd_symbol = "[❖](bold green)"

[username]
show_always = true
format = "[$user]($style)"

[directory]
style = "bold green"
format = "[$path]($style) "
truncation_length = 4
truncate_to_repo = false
home_symbol = "⌂"
read_only = " [!](bold red)"
truncation_symbol = "…/"

[hostname]
ssh_only = false
format = "@"[$hostname]($style)"
disabled = false

[git_branch]
format = " [$branch](bold green)"

[git_status]
style = "bold red"
stashed = " 📦"
ahead = " ⇡"
behind = " ⇣"
diverged = " ⇕"
untracked = " …"
deleted = " 🗑"
renamed = " »"
modified = " !"
staged = " +"

[python]
format = " via [🐍 $version](bold green)"

[nodejs]
format = " via [⬢ $version](bold green)"

[rust]
format = " via [🦀 $version](bold red)"

[golang]
format = " via [🐹 $version](bold cyan)"

[cmd_duration]
format = "⏳ [$duration](bold yellow)"
min_time = 2000

[package]
disabled = true

[battery]
disabled = true
EOL
  chown -R "$ACTUAL_USER":"$ACTUAL_USER" "$ACTUAL_HOME/.config"
  log_success "Starship prompt installed and configured."
}

install_git() {
  log_info "Installing Git & GitHub CLI..."
  apt install -y git

  if [ ! -f "/usr/share/keyrings/githubcli-archive-keyring.gpg" ]; then
    log_info "Downloading GitHub CLI GPG key..."
    curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | gpg --dearmor -o /usr/share/keyrings/githubcli-archive-keyring.gpg
    chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg
  else
    log_info "GitHub CLI GPG key already exists. Skipping download."
  fi

  echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" >/etc/apt/sources.list.d/github-cli.list
  apt update && apt install -y gh
  log_success "Git & GitHub CLI installed."
}

install_utilities() {
  log_info "Installing utilities (ranger, lsd, etc)..."
  apt install -y curl wget htop tree iotop lsd ranger
  log_success "Utilities installed."
}
install_search_tools() {
  log_info "Installing search tools (fzf, rg)..."
  apt install -y fzf ripgrep fd-find
  log_success "Search tools installed."
}

install_lazygit() {
  log_info "Installing Lazygit for Debian 13 (Trixie) via apt..."
  apt install -y lazygit
  log_success "Lazygit installed successfully."
}

install_nvm_node() {
  log_info "Installing NVM v$NVM_VERSION and Node.js..."
  su - "$ACTUAL_USER" -c "curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v$NVM_VERSION/install.sh | bash"
  cat >>"$ACTUAL_HOME/.zshrc" <<'EOL'

# NVM (Node Version Manager)
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
EOL
  su - "$ACTUAL_USER" -c 'source ~/.zshrc; nvm install --lts; nvm alias default node; npm i -g pnpm neovim'
  log_success "NVM and Node.js setup complete."
}

install_nerd_font() {
  log_info "Installing Nerd Font..."
  apt install -y fontconfig
  mkdir -p "$ACTUAL_HOME/.local/share/fonts"
  cd /tmp || return 1
  wget -q https://github.com/ryanoasis/nerd-fonts/releases/download/v3.2.1/Hack.zip
  unzip -o -q Hack.zip -d "$ACTUAL_HOME/.local/share/fonts/"
  chown -R "$ACTUAL_USER":"$ACTUAL_USER" "$ACTUAL_HOME/.local/share/fonts"
  if command -v fc-cache >/dev/null 2>&1; then fc-cache -f; fi
  rm -f Hack.zip
  log_success "Nerd Font installed."
}
install_rust() {
  log_info "Installing Rust..."
  su - "$ACTUAL_USER" -c "curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y"
  echo 'source "$HOME/.cargo/env"' >>"$ACTUAL_HOME/.zshrc"
  log_success "Rust installed."
}
install_docker() {
  log_info "Installing Docker..."
  apt install -y ca-certificates curl
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  chmod a+r /etc/apt/keyrings/docker.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian $(. /etc/os-release && echo "$VERSION_CODENAME") stable" >/etc/apt/sources.list.d/docker.list
  apt update && apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  log_success "Docker installed."
}

install_python_poetry() {
  log_info "Installing Python and Poetry via apt..."
  log_info "Detecting latest available Python 3 version from apt..."
  PYTHON_EXECUTABLE=$(apt-cache search --names-only '^python3\.[0-9]+$' | sort -V | tail -n 1 | awk '{print $1}')

  if [ -z "$PYTHON_EXECUTABLE" ]; then
    log_error "Could not automatically detect a suitable Python 3 version from apt. Aborting."
    return 1
  fi
  log_info "Detected latest available version: $GREEN$PYTHON_EXECUTABLE${NC}"

  log_info "Installing $PYTHON_EXECUTABLE, its development packages, and required libraries..."
  apt install -y "$PYTHON_EXECUTABLE" "${PYTHON_EXECUTABLE}-venv" "${PYTHON_EXECUTABLE}-dev" python3-pip libffi-dev
  log_success "Python installation complete."

  log_info "Performing a clean installation of Poetry..."
  su - "$ACTUAL_USER" -c "curl -sSL https://install.python-poetry.org | $PYTHON_EXECUTABLE - --uninstall" >/dev/null 2>&1 || true
  su - "$ACTUAL_USER" -c "rm -rf ~/.local/bin/poetry ~/.local/share/pypoetry ~/.cache/pypoetry"

  su - "$ACTUAL_USER" -c "curl -sSL https://install.python-poetry.org | $PYTHON_EXECUTABLE -"
  if ! grep -q 'export PATH="$HOME/.local/bin:$PATH"' "$ACTUAL_HOME/.zshrc"; then
    echo '' >>"$ACTUAL_HOME/.zshrc"
    echo '# Add Poetry to PATH' >>"$ACTUAL_HOME/.zshrc"
    echo 'export PATH="$HOME/.local/bin:$PATH"' >>"$ACTUAL_HOME/.zshrc"
  fi
  log_success "Poetry installed successfully."

  log_info "Installing pynvim for Neovim integration..."
  "$PYTHON_EXECUTABLE" -m pip install pynvim
  log_success "Python and Poetry setup is complete."
}

install_tmux() {
  log_info "Installing tmux, TPM, and Catppuccin theme..."
  # Install tmux directly from apt - much faster and more reliable
  apt install -y tmux git

  # Install the Tmux Plugin Manager (TPM)
  su - "$ACTUAL_USER" -c "git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm"

  # Create the user's tmux configuration file
  cat >"$ACTUAL_HOME/.tmux.conf" <<'EOL'
set-option -g status-interval 60; set-option -g status on; set-option -g mouse on
bind '"' split-window -v -c "#{pane_current_path}"; bind % split-window -h -c "#{pane_current_path}"
bind x kill-pane
set-option -g default-terminal "tmux-256color"; set -ga terminal-overrides ',xterm-256color:Tc'
set -g @plugin 'tmux-plugins/tpm'; set -g @plugin 'catppuccin/tmux'; set -g @catppuccin_flavor 'frappe'
run '~/.tmux/plugins/tpm/tpm'
EOL
  chown "$ACTUAL_USER":"$ACTUAL_USER" "$ACTUAL_HOME/.tmux.conf"
  log_info "${BOLD}IMPORTANT: After starting tmux, press 'Ctrl+A' then 'I' (capital i) to install plugins."
  log_success "Tmux and TPM installed."
}

install_go() {
  log_info "Installing Go v$GO_VERSION..."
  local go_archive="go$GO_VERSION.linux-amd64.tar.gz"
  cd /tmp || return 1
  wget -q "https://dl.google.com/go/$go_archive"
  rm -rf /usr/local/go && tar -xzf "$go_archive" -C /usr/local
  cat >>"$ACTUAL_HOME/.zshrc" <<'EOL'

# Go Language
export PATH=$PATH:/usr/local/go/bin; export GOPATH=$HOME/go; export PATH=$PATH:$GOPATH/bin
EOL
  mkdir -p "$ACTUAL_HOME/go/"{bin,pkg,src} && chown -R "$ACTUAL_USER":"$ACTUAL_USER" "$ACTUAL_HOME/go"
  rm -f "/tmp/$go_archive"
  log_success "Go installed."
}

install_neovim_dependencies() {
  log_info "Installing Neovim & LazyVim dependencies (Image support included)..."
  apt install -y lua5.1 liblua5.1-0-dev luajit luarocks trash-cli imagemagick ghostscript
  log_info "--> Installing Tree-sitter CLI v0.22.6 (required by LazyVim)..."
  curl -L https://github.com/tree-sitter/tree-sitter/releases/download/v0.22.6/tree-sitter-linux-x64.gz -o /tmp/tree-sitter.gz
  gunzip /tmp/tree-sitter.gz
  mv /tmp/tree-sitter /usr/local/bin/tree-sitter
  chmod +x /usr/local/bin/tree-sitter
  log_success "Neovim dependencies installed."
}

install_neovim() {
  log_info "Starting full Neovim & LazyVim installation..."
  install_build_essentials
  install_git
  install_search_tools
  install_neovim_dependencies
  log_info "--> Installing Neovim binary..."
  apt install -y tar gzip
  local nvim_dir="$ACTUAL_HOME/.local/nvim"
  mkdir -p "$nvim_dir"
  cd /tmp || return 1
  curl -L -o nvim-linux64.tar.gz "$NEOVIM_URL"
  tar xzvf nvim-linux64.tar.gz -C "$nvim_dir" --strip-components 1
  chown -R "$ACTUAL_USER":"$ACTUAL_USER" "$nvim_dir"
  if ! grep -q "alias nvim=" "$ACTUAL_HOME/.zshrc"; then echo "alias nvim='$nvim_dir/bin/nvim'" >>"$ACTUAL_HOME/.zshrc"; fi
  log_info "--> Cloning LazyVim starter configuration..."
  if [ ! -d "$ACTUAL_HOME/.config/nvim" ]; then su - "$ACTUAL_USER" -c "git clone https://github.com/LazyVim/starter ~/.config/nvim"; fi
  rm -f nvim-linux64.tar.gz
  log_info "${BOLD}IMPORTANT: On your first run of nvim, please run the following commands to install parsers:"
  log_info "${BOLD}--> :TSInstall bash regex"
  log_success "Neovim and LazyVim installed successfully."
}

install_rsync() {
  log_info "Installing rsync..."
  apt install -y rsync
  log_success "rsync installed."
}
install_rclone() {
  log_info "Installing rclone..."
  curl https://rclone.org/install.sh | bash
  log_success "rclone installed."
}
create_dev_directory() {
  log_info "Creating DEV directory..."
  mkdir -p "$ACTUAL_HOME/DEV" && chown "$ACTUAL_USER":"$ACTUAL_USER" "$ACTUAL_HOME/DEV"
  log_success "DEV directory created."
}
configure_ssh_priority() {
  log_info "Configuring SSH priority..."
  mkdir -p /etc/systemd/system/ssh.service.d
  echo -e "[Service]\nCPUSchedulingPolicy=rr\nCPUSchedulingPriority=99" >/etc/systemd/system/ssh.service.d/override.conf
  systemctl daemon-reload && systemctl restart ssh
  log_success "SSH priority configured."
}

create_zsh_compiler_script() {
  log_info "Creating Zsh compiler script..."
  cat >"$ACTUAL_HOME/compile-zsh.sh" <<'EOL'
#!/bin/zsh
FILES=("$HOME/.zshenv" "$HOME/.zshrc" "$HOME/.zprofile")
echo "Cleaning up old .zwc files..."; for file in "${FILES[@]}"; do if [ -f "$file.zwc" ]; then rm -v "$file.zwc"; fi; done
echo "Compiling new .zwc files..."; for file in "${FILES[@]}"; do if [ -f "$file" ]; then zcompile "$file"; fi; done; echo "Compilation complete!"
EOL
  chmod +x "$ACTUAL_HOME/compile-zsh.sh" && chown "$ACTUAL_USER":"$ACTUAL_USER" "$ACTUAL_HOME/compile-zsh.sh"
  log_success "Zsh compiler script created."
}

generate_setup_report() {
  log_info "Generating setup report..."
  cat >"$ACTUAL_HOME/setup-report.txt" <<EOL
=================================
 SERVER SETUP REPORT & QUICK TIPS
=================================
### UFW (Firewall)
- Status: $(ufw status | head -n 1)
- To see rules: sudo ufw status numbered
- To allow http: sudo ufw allow http
### Fail2ban
- Status: $(systemctl is-active fail2ban)
- Protects SSH. Check banned IPs: sudo fail2ban-client status sshd
### Shell (Zsh & Starship)
- To edit shell config: nvim ~/.zshrc
- To speed up shell start: ./compile-zsh.sh
### Tmux
- Prefix Key: Ctrl+A
- To install plugins: Start tmux, press Ctrl+A then I (capital i)
### Lazygit & Ranger
- To start git TUI: lazygit
- To start file manager: ranger
### rclone & rsync
- To configure cloud sync: rclone config
- To transfer files: rsync -avz /local/path user@remote:/remote/
EOL
  chown "$ACTUAL_USER":"$ACTUAL_USER" "$ACTUAL_HOME/setup-report.txt"
  log_success "Setup report created at ~/setup-report.txt"
}

# --- UNINSTALLATION FUNCTIONS ---

uninstall_all() {
  log_info "Starting complete uninstallation..."
  uninstall_neovim
  uninstall_go
  uninstall_tmux
  uninstall_python_poetry
  uninstall_docker
  uninstall_rust
  uninstall_nerd_font
  uninstall_nvm_node
  uninstall_utilities
  uninstall_starship
  uninstall_zsh
  uninstall_firewall
  uninstall_fail2ban
  uninstall_rclone
  uninstall_rsync
  uninstall_search_tools
  uninstall_lazygit
  remove_dev_directory
  unconfigure_ssh_priority
  log_info "Cleaning up orphaned packages..."
  apt autoremove -y
  apt clean
  log_success "All components uninstalled."
}
uninstall_neovim() {
  log_info "Uninstalling Neovim..."
  purge_packages lua5.1 liblua5.1-0-dev luajit luarocks trash-cli imagemagick ghostscript
  rm -f /usr/local/bin/tree-sitter
  rm -rf "$ACTUAL_HOME/.local/nvim" "$ACTUAL_HOME/.config/nvim"
  sed -i "/alias nvim=/d" "$ACTUAL_HOME/.zshrc"
  log_success "Neovim & dependencies uninstalled."
}
uninstall_go() {
  log_info "Uninstalling Go..."
  rm -rf /usr/local/go "$ACTUAL_HOME/go"
  sed -i -e '/# Go Language/d' -e '/GOPATH/d' -e '/\/usr\/local\/go\/bin/d' "$ACTUAL_HOME/.zshrc"
  log_success "Go uninstalled."
}
uninstall_tmux() {
  log_info "Uninstalling tmux..."
  purge_packages tmux
  rm -rf "$ACTUAL_HOME/.tmux.conf" "$ACTUAL_HOME/.tmux"
  log_success "Tmux uninstalled."
}
uninstall_python_poetry() {
  log_info "Uninstalling Poetry & Python..."
  su - "$ACTUAL_USER" -c "rm -rf ~/.local/bin/poetry ~/.local/share/pypoetry ~/.cache/pypoetry"
  sed -i -e '/# Add Poetry to PATH/d' -e '/\.local\/bin/d' "$ACTUAL_HOME/.zshrc"
  log_info "Poetry files removed."

  log_info "Purging all apt-managed python3.* packages..."
  packages_to_purge=$(dpkg -l | grep 'python3\.[0-9]\+' | awk '{print $2}' | tr '\n' ' ')
  if [ -n "$packages_to_purge" ]; then
    purge_packages "$packages_to_purge"
  fi
  apt autoremove -y
  log_success "Poetry & Python uninstalled."
}
uninstall_docker() {
  log_info "Uninstalling Docker..."
  purge_packages docker-ce docker-ce-cli containerd.io
  rm -f /etc/apt/sources.list.d/docker.list /usr/share/keyrings/docker.gpg
  apt update >/dev/null
  log_success "Docker uninstalled."
}
uninstall_rust() {
  log_info "Uninstalling Rust..."
  su - "$ACTUAL_USER" -c "rustup self uninstall -y"
  sed -i '/\.cargo\/env/d' "$ACTUAL_HOME/.zshrc"
  log_success "Rust uninstalled."
}
uninstall_nerd_font() {
  log_info "Uninstalling Nerd Font..."
  rm -rf "$ACTUAL_HOME/.local/share/fonts/Hack"
  if command -v fc-cache >/dev/null 2>&1; then fc-cache -f; fi
  log_success "Nerd Font uninstalled."
}
uninstall_nvm_node() {
  log_info "Uninstalling NVM & Node..."
  rm -rf "$ACTUAL_HOME/.nvm"
  sed -i -e '/# NVM/d' -e '/NVM_DIR/d' "$ACTUAL_HOME/.zshrc"
  log_success "NVM & Node uninstalled."
}
uninstall_utilities() {
  log_info "Uninstalling utilities (keeping curl)..."
  purge_packages wget htop tree iotop lsd ranger
  log_success "Utilities uninstalled."
}
uninstall_zsh() {
  log_info "Uninstalling ZSH..."
  chsh -s /bin/bash "$ACTUAL_USER"
  purge_packages zsh zplug
  rm -f "$ACTUAL_HOME/.zshrc" "$ACTUAL_HOME/.zsh_history" "$ACTUAL_HOME/compile-zsh.sh"
  rm -rf "$ACTUAL_HOME/.zsh" "$ACTUAL_HOME/.zplug"
  log_success "ZSH uninstalled."
}
uninstall_starship() {
  log_info "Uninstalling Starship..."
  rm -f /usr/local/bin/starship "$ACTUAL_HOME/.config/starship.toml"
  sed -i '/starship init/d' "$ACTUAL_HOME/.zshrc"
  log_success "Starship uninstalled."
}
uninstall_rclone() {
  log_info "Uninstalling rclone..."
  rm -f /usr/bin/rclone /usr/local/share/man/man1/rclone.1
  log_success "rclone uninstalled."
}
uninstall_rsync() {
  log_info "Uninstalling rsync..."
  purge_packages rsync
  log_success "rsync uninstalled."
}
uninstall_search_tools() {
  log_info "Uninstalling search tools..."
  purge_packages fzf ripgrep fd-find
  log_success "Search tools uninstalled."
}
uninstall_lazygit() {
  log_info "Uninstalling Lazygit..."
  apt purge -y lazygit >/dev/null 2>&1
  log_success "Lazygit uninstalled."
}
uninstall_firewall() {
  log_info "Disabling and uninstalling firewall..."
  ufw --force reset
  apt purge -y ufw
  log_success "Firewall uninstalled."
}
uninstall_fail2ban() {
  log_info "Uninstalling Fail2ban..."
  apt purge -y fail2ban
  log_success "Fail2ban uninstalled."
}
remove_dev_directory() {
  log_info "Removing DEV directory..."
  rm -rf "$ACTUAL_HOME/DEV"
  log_success "DEV directory removed."
}
unconfigure_ssh_priority() {
  log_info "Removing SSH priority..."
  rm -f /etc/systemd/system/ssh.service.d/override.conf
  systemctl daemon-reload && systemctl restart ssh
  log_success "SSH priority unconfigured."
}

# --- NEW: Verification Function ---
verify_system() {
  log_info "Starting system verification. Note: This checks the environment for the user '$ACTUAL_USER'."

  # Define local variables for the check
  local TOTAL_CHECKS=0
  local PASSED_CHECKS=0

  # Define a local check function
  check() {
    ((TOTAL_CHECKS++))
    local DESCRIPTION=$1
    local COMMAND_TO_RUN=$2
    printf "${BLUE}%-50s${NC}" "$DESCRIPTION"
    # Run the command as the actual user where appropriate to check user-specific files
    if eval "su - $ACTUAL_USER -c '$COMMAND_TO_RUN'" >/dev/null 2>&1; then
      printf "[ ${GREEN}PASSED${NC} ]\n"
      ((PASSED_CHECKS++))
    else
      # Fallback for system-level commands that need root
      if eval "$COMMAND_TO_RUN" >/dev/null 2>&1; then
        printf "[ ${GREEN}PASSED${NC} ]\n"
        ((PASSED_CHECKS++))
      else
        printf "[ ${RED}FAILED${NC} ]\n"
      fi
    fi
  }

  echo -e "\n${YELLOW}${BOLD}--- Security ---${NC}"
  check "UFW Firewall is active" "ufw status | grep -q 'Status: active'"
  check "Fail2ban service is running" "systemctl is-active --quiet fail2ban"

  echo -e "\n${YELLOW}${BOLD}--- Shell Environment ---${NC}"
  check "Zsh is installed" "command -v zsh"
  check "Starship prompt is installed" "command -v starship"
  check "Tmux is installed" "command -v tmux"
  check "Nerd Fonts directory exists" "'[ -d ~/.local/share/fonts ] && [ -n \"\$(ls -A ~/.local/share/fonts)\" ]'"
  check "Zsh configuration file exists" "'[ -f ~/.zshrc ]'"
  check "Starship configuration file exists" "'[ -f ~/.config/starship.toml ]'"
  check "Tmux configuration file exists" "'[ -f ~/.tmux.conf ]'"

  echo -e "\n${YELLOW}${BOLD}--- Development Tools ---${NC}"
  check "Git is installed" "command -v git"
  check "GitHub CLI (gh) is installed" "command -v gh"
  check "Lazygit is installed" "command -v lazygit"
  check "fzf is installed" "command -v fzf"
  check "ripgrep (rg) is installed" "command -v rg"
  check "fd (fdfind) is installed" "command -v fdfind"
  check "NVM, node, and npm are available" "'source ~/.nvm/nvm.sh && command -v node && command -v npm'"
  check "Rust (rustc) is available" "'source ~/.cargo/env && command -v rustc'"
  check "Go is installed" "command -v go"
  local PY_EXEC
  PY_EXEC=$(command -v python3.13)
  check "Python is installed ($PY_EXEC)" "[ -n \"$PY_EXEC\" ]"
  check "Poetry is available" "'source ~/.zshrc && command -v poetry'"
  check "Docker service is running" "systemctl is-active --quiet docker"
  check "Neovim binary exists" "'[ -x ~/.local/nvim/bin/nvim ]'"
  check "Neovim config (LazyVim) exists" "'[ -d ~/.config/nvim ]'"

  echo -e "\n${YELLOW}${BOLD}--- System & Miscellaneous ---${NC}"
  check "rclone is installed" "command -v rclone"
  check "rsync is installed" "command -v rsync"
  check "DEV directory exists" "'[ -d ~/DEV ]'"
  check "SSH real-time priority is configured" "'[ -f /etc/systemd/system/ssh.service.d/override.conf ]'"
  check "Zsh compiler script exists" "'[ -f ~/compile-zsh.sh ]'"
  check "Setup report exists" "'[ -f ~/setup-report.txt ]'"

  echo -e "\n${BLUE}${BOLD}--- Verification Summary ---${NC}"
  echo -e "${BOLD}Checks Passed: $PASSED_CHECKS / $TOTAL_CHECKS${NC}\n"
  if [ "$PASSED_CHECKS" -eq "$TOTAL_CHECKS" ]; then
    echo -e "${GREEN}${BOLD}🎉 All checks passed! Your environment appears to be fully set up.${NC}"
  else
    echo -e "${RED}${BOLD}🔥 Some checks failed. Please review the output above.${NC}"
  fi
}

# --- MENU AND MAIN LOGIC ---

show_menu() {
  show_banner
  echo -e "${BOLD}Installation Menu:${NC}"
  echo "------------------"
  echo " A) Configure APT sources & Update System (RECOMMENDED FIRST)"
  echo " T) Test System (Verify Installation)"
  echo
  echo " 1) Update system packages"
  echo " 2) Install essential build tools"
  echo " 3) Install essential utilities (ranger, lsd, etc)"
  echo
  echo -e "${BOLD}Security:${NC}"
  echo " 4) Install and Configure Firewall (UFW)"
  echo " 5) Install Fail2ban (Brute-force protection)"
  echo
  echo -e "${BOLD}Shell Environment:${NC}"
  echo " 6) Install ZSH and set as default shell"
  echo " 7) Install Starship Prompt"
  echo " 8) Install Nerd Font"
  echo " 9) Install tmux (with TPM & Catppuccin)"
  echo
  echo -e "${BOLD}Development Tools:${NC}"
  echo " 10) Install Git & GitHub CLI"
  echo " 11) Install Lazygit"
  echo " 12) Install Search Tools (fzf, ripgrep)"
  echo " 13) Install NVM & Node.js"
  echo " 14) Install Rust"
  echo " 15) Install Go"
  echo " 16) Install Python & Poetry"
  echo " 17) Install Docker"
  echo " 18) Install Neovim & LazyVim"
  echo
  echo -e "${BOLD}System & Misc:${NC}"
  echo " 19) Install rclone (Cloud Sync)"
  echo " 20) Install rsync"
  echo " 21) Create DEV directory"
  echo " 22) Configure SSH with real-time priority"
  echo
  echo " 0) Install ALL (recommended)"
  echo -e "99) ${RED}Uninstall ALL${NC}"
  echo " q) Quit"
  echo
  echo -e "${BOLD}Enter your choice(s):${NC}"
  read -r -p "> " choices
}

main() {
  while true; do
    show_menu
    local will_exec_zsh=false
    case "$choices" in
    q | Q)
      echo "Exiting script."
      exit 0
      ;;
    0)
      tasks=('A' 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22)
      will_exec_zsh=true
      ;;
    99) read -r -p "$(echo -e ${RED}${BOLD}"Sure? This will remove ALL script-installed components. [y/N] "${NC})" confirm && [[ "$confirm" =~ ^[yY]$ ]] && uninstall_all ;;
    *) tasks=($choices) ;;
    esac
    if [[ -n "${tasks-}" ]]; then
      for choice in "${tasks[@]}"; do
        case "$choice" in
        A | a) configure_apt_sources ;; T | t) verify_system ;; 1) update_system ;; 2) install_build_essentials ;; 3) install_utilities ;; 4) install_firewall ;; 5) install_fail2ban ;; 6) install_zsh ;;
        7) install_starship ;; 8) install_nerd_font ;; 9) install_tmux ;; 10) install_git ;; 11) install_lazygit ;; 12) install_search_tools ;;
        13) install_nvm_node ;; 14) install_rust ;; 15) install_go ;; 16) install_python_poetry ;; 17) install_docker ;; 18) install_neovim ;;
        19) install_rclone ;; 20) install_rsync ;; 21) create_dev_directory ;; 22) configure_ssh_priority ;;
        *) log_error "Invalid choice: $choice" ;;
        esac
      done
      if [ "$will_exec_zsh" = true ]; then
        create_zsh_compiler_script
        generate_setup_report
        log_success "${BOLD}All tasks completed!"
        log_info "${BOLD}The script will now switch your current session to Zsh."
        read -n 1 -s -r -p "Press any key to switch to Zsh..."
        exec su - "$ACTUAL_USER" -c zsh
      else
        log_success "Selected tasks completed!"
      fi
    fi
    unset tasks
    read -n 1 -s -r -p "Press any key to return to the menu..."
  done
}

main
