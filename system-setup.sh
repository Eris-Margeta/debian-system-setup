#!/bin/bash
# ==========================================================
# Remote Development Environment Setup Script
# For Debian/Ubuntu-based systems
# ==========================================================
# Version: 2.8.0
# Last Updated: Dec 3, 2025

# --- CONFIGURATION ---
# Easily update software versions here in the future.

GO_VERSION="1.25.4"
PYTHON_VERSION="3.12.3"
NVM_VERSION="0.39.7"
TMUX_VERSION="3.5a"
# Fetches the latest stable Neovim for x86_64 architecture (standard for Hetzner)
NEOVIM_URL="https://github.com/neovim/neovim/releases/latest/download/nvim-linux-x86_64.tar.gz"

# --- SCRIPT CORE ---
# (No need to edit below this line for version changes)

# Set up colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Setup logging
LOG_FILE="/tmp/dev-env-setup-$(date +%Y%m%d-%H%M%S).log"

# Script needs to be run as root or with sudo
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}Please run as root or with sudo${NC}"
  exit 1
fi

# Store the actual user who ran the script
if [ -z "$SUDO_USER" ]; then
  ACTUAL_USER="$(whoami)"
else
  ACTUAL_USER="$SUDO_USER"
fi
ACTUAL_HOME="$(eval echo ~"$ACTUAL_USER")"

# --- HELPER FUNCTIONS ---

log_error() { echo -e "${RED}ERROR: $1${NC}" | tee -a "$LOG_FILE"; }
log_info() { echo -e "${BLUE}$1${NC}" | tee -a "$LOG_FILE"; }
log_success() { echo -e "${GREEN}$1${NC}" | tee -a "$LOG_FILE"; }

show_banner() {
  clear
  echo -e "${BLUE}${BOLD}"
  echo "====================================================="
  echo "      Remote Development Environment Setup Script    "
  echo "====================================================="
  echo -e "${NC}"
  echo "This script will set up your development environment."
  echo ""
}

# Helper function to intelligently purge packages
purge_packages() {
  local packages_to_remove=()
  for pkg in "$@"; do
    if dpkg -l | grep -q "ii  $pkg "; then
      packages_to_remove+=("$pkg")
    fi
  done

  if [ ${#packages_to_remove[@]} -gt 0 ]; then
    log_info "Purging packages: ${packages_to_remove[*]}"
    if ! apt purge -y "${packages_to_remove[@]}"; then
      log_error "Failed to purge: ${packages_to_remove[*]}"
    fi
  fi
}

# --- INSTALLATION FUNCTIONS ---

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
install_terminal_definitions() {
  log_info "Installing terminal definitions..."
  apt install -y ncurses-term
  log_success "Terminal definitions installed."
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
  cat >"$ACTUAL_HOME/.zshrc" <<EOL
# Fix for modern terminals like Kitty
export TERM=xterm

# History settings
HISTFILE=~/.zsh_history
HISTSIZE=5000
SAVEHIST=5000

# Aliases for quick file editing
alias ec="nvim ~/.zshrc"
alias ep="nvim ~/.config/starship.toml"
alias sc="source ~/.zshrc"
alias ls="lsd"

# Python aliases
alias python='python3.12'

# zplug plugin manager
source /usr/share/zplug/init.zsh
zplug "zsh-users/zsh-syntax-highlighting"
zplug "zsh-users/zsh-autosuggestions"
if ! zplug check; then zplug install; fi
zplug load
EOL
  chown "$ACTUAL_USER":"$ACTUAL_USER" "$ACTUAL_HOME/.zshrc" && chsh -s "$(command -v zsh)" "$ACTUAL_USER"
  log_success "ZSH setup completed. Shell will be switched at the end of the script."
}

install_starship() {
  log_info "Installing Starship prompt..."
  su - "$ACTUAL_USER" -c "curl -sS https://starship.rs/install.sh | sh -s -- -y"
  echo -e '\neval "$(starship init zsh)"' >>"$ACTUAL_HOME/.zshrc"
  mkdir -p "$ACTUAL_HOME/.config"
  cat >"$ACTUAL_HOME/.config/starship.toml" <<'EOL'
add_newline = false
[character]
success_symbol = "[➜](bold green)"
error_symbol = "[➜](bold red)"
[directory]
truncation_length = 3
truncation_symbol = "…/"
style = "bold blue"
EOL
  chown -R "$ACTUAL_USER":"$ACTUAL_USER" "$ACTUAL_HOME/.config"
  log_success "Starship prompt installed and configured."
}

install_git() {
  log_info "Installing Git & GitHub CLI..."
  apt install -y git
  curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | gpg --dearmor -o /usr/share/keyrings/githubcli-archive-keyring.gpg
  chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" >/etc/apt/sources.list.d/github-cli.list
  apt update && apt install -y gh
  log_success "Git & GitHub CLI installed."
}
install_utilities() {
  log_info "Installing utilities (ranger, lsd, etc)..."
  apt install -y curl wget htop tree iotop lsd ranger
  log_success "Utilities installed."
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
  cd /tmp && wget -q https://github.com/ryanoasis/nerd-fonts/releases/download/v3.2.1/Hack.zip
  unzip -o -q Hack.zip -d "$ACTUAL_HOME/.local/share/fonts/"
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
  log_info "Installing Python $PYTHON_VERSION and Poetry..."
  apt install -y build-essential libssl-dev zlib1g-dev wget python3-pip
  cd /tmp || return 1
  wget -q "https://www.python.org/ftp/python/$PYTHON_VERSION/Python-$PYTHON_VERSION.tgz"
  tar -xf "Python-$PYTHON_VERSION.tgz"
  cd "Python-$PYTHON_VERSION" && ./configure --enable-optimizations && make -j"$(nproc)" && make altinstall
  python3.12 -m pip install pynvim
  su - "$ACTUAL_USER" -c "curl -sSL https://install.python-poetry.org | python3.12 -"
  echo 'export PATH="$HOME/.local/bin:$PATH"' >>"$ACTUAL_HOME/.zshrc"
  cd /tmp && rm -rf "Python-$PYTHON_VERSION"*
  log_success "Python and Poetry installed."
}

install_tmux() {
  log_info "Installing tmux, TPM, and Catppuccin theme..."
  apt install -y build-essential libevent-dev libncurses5-dev bison git xsel
  cd /tmp || return 1
  git clone https://github.com/tmux/tmux.git && cd tmux
  git checkout "$TMUX_VERSION"
  sh autogen.sh && ./configure && make && make install
  su - "$ACTUAL_USER" -c "git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm"
  cat >"$ACTUAL_HOME/.tmux.conf" <<'EOL'
set-option -g status-interval 60
set-option -g status on
set-option -g mouse on
bind '"' split-window -v -c "#{pane_current_path}"
bind % split-window -h -c "#{pane_current_path}"
bind x kill-pane
set-option -g default-terminal "tmux-256color"
set -ga terminal-overrides ',xterm-256color:Tc'
bind-key -T copy-mode-vi y send -X copy-pipe-and-cancel "xsel -ib"
set-option -g set-clipboard on
set -g @plugin 'tmux-plugins/tpm'
set -g @plugin 'catppuccin/tmux'
set -g @catppuccin_flavor 'frappe'
run '~/.tmux/plugins/tpm/tpm'
EOL
  chown "$ACTUAL_USER":"$ACTUAL_USER" "$ACTUAL_HOME/.tmux.conf"
  cd /tmp && rm -rf tmux
  log_info "${BOLD}IMPORTANT: After starting tmux, press 'Prefix + I' (that's Ctrl+A then capital I) to install plugins."
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
export PATH=$PATH:/usr/local/go/bin
export GOPATH=$HOME/go
export PATH=$PATH:$GOPATH/bin
EOL
  mkdir -p "$ACTUAL_HOME/go/"{bin,pkg,src} && chown -R "$ACTUAL_USER":"$ACTUAL_USER" "$ACTUAL_HOME/go"
  rm -f "/tmp/$go_archive"
  log_success "Go installed."
}

install_neovim() {
  log_info "Installing latest Neovim stable..."
  apt install -y tar gzip
  local nvim_dir="$ACTUAL_HOME/.local/nvim"
  mkdir -p "$nvim_dir"
  cd /tmp || return 1
  curl -L -o nvim-linux64.tar.gz "$NEOVIM_URL"
  tar xzvf nvim-linux64.tar.gz -C "$nvim_dir" --strip-components 1
  chown -R "$ACTUAL_USER":"$ACTUAL_USER" "$nvim_dir"
  if ! grep -q "alias nvim=" "$ACTUAL_HOME/.zshrc"; then echo "alias nvim='$nvim_dir/bin/nvim'" >>"$ACTUAL_HOME/.zshrc"; fi
  if [ ! -d "$ACTUAL_HOME/.config/nvim" ]; then su - "$ACTUAL_USER" -c "git clone https://github.com/LazyVim/starter ~/.config/nvim"; fi
  rm -f nvim-linux64.tar.gz
  log_success "Neovim installed."
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

create_zsh_compiler_script() {
  log_info "Creating Zsh compiler script..."
  cat >"$ACTUAL_HOME/compile-zsh.sh" <<'EOL'
#!/bin/zsh
FILES=("$HOME/.zshenv" "$HOME/.zshrc" "$HOME/.zprofile")
echo "Cleaning up old .zwc files..."
for file in "${FILES[@]}"; do if [ -f "$file.zwc" ]; then rm -v "$file.zwc"; fi; done
echo "Compiling new .zwc files..."
for file in "${FILES[@]}"; do if [ -f "$file" ]; then zcompile "$file"; fi; done
echo "Compilation complete!"
EOL
  chmod +x "$ACTUAL_HOME/compile-zsh.sh" && chown "$ACTUAL_USER":"$ACTUAL_USER" "$ACTUAL_HOME/compile-zsh.sh"
  log_success "Zsh compiler script created at ~/compile-zsh.sh"
}

generate_setup_report() {
  log_info "Generating setup report..."
  cat >"$ACTUAL_HOME/setup-report.txt" <<EOL
=================================
 SERVER SETUP REPORT & QUICK TIPS
=================================
This server was configured on $(date).

---
## Security
---
### UFW (Firewall)
- Status: $(ufw status | head -n 1)
- To see rules: sudo ufw status numbered
- To allow http: sudo ufw allow http
- To delete a rule: sudo ufw delete [rule_number]

### Fail2ban
- Status: $(systemctl is-active fail2ban)
- Protects SSH from brute-force attacks automatically.
- To check banned IPs: sudo fail2ban-client status sshd

---
## Shell Environment
---
### Zsh & Starship
- Your default shell is Zsh with a Starship prompt.
- To edit shell config: nvim ~/.zshrc
- To edit prompt config: nvim ~/.config/starship.toml
- To speed up shell start time: ./compile-zsh.sh

### Tmux
- Prefix Key: Ctrl+A
- To install plugins: Start tmux, press Ctrl+A then I (capital i)
- New vertical split: Ctrl+A then %
- New horizontal split: Ctrl+A then "

---
## Utilities
---
### Ranger, rclone, rsync
- To start file manager: ranger
- To configure cloud sync: rclone config
- To transfer files: rsync -avz /local/path user@remote:/remote/path
EOL
  chown "$ACTUAL_USER":"$ACTUAL_USER" "$ACTUAL_HOME/setup-report.txt"
  log_success "Setup report created at ~/setup-report.txt"
}

# --- UNINSTALLATION FUNCTIONS ---

uninstall_neovim() {
  log_info "Uninstalling Neovim..."
  rm -rf "$ACTUAL_HOME/.local/nvim" "$ACTUAL_HOME/.config/nvim" "$ACTUAL_HOME/.local/share/nvim"
  sed -i "/alias nvim=.*nvim/d" "$ACTUAL_HOME/.zshrc"
  log_success "Neovim uninstalled."
}
uninstall_go() {
  log_info "Uninstalling Go..."
  rm -rf /usr/local/go "$ACTUAL_HOME/go"
  sed -i -e '/# Go Language/d' -e '/GOPATH/d' -e '/\/usr\/local\/go\/bin/d' "$ACTUAL_HOME/.zshrc"
  log_success "Go uninstalled."
}
uninstall_tmux() {
  log_info "Uninstalling tmux..."
  rm -f /usr/local/bin/tmux
  rm -rf "$ACTUAL_HOME/.tmux.conf" "$ACTUAL_HOME/.tmux"
  log_success "Tmux uninstalled."
}
uninstall_python_poetry() {
  log_info "Uninstalling Poetry & Python..."
  su - "$ACTUAL_USER" -c "curl -sSL https://install.python-poetry.org | python3.12 - --uninstall"
  rm -rf "$ACTUAL_HOME/.local/bin/poetry" /usr/local/bin/python3.12
  sed -i '/\.local\/bin/d' "$ACTUAL_HOME/.zshrc"
  log_success "Poetry & Python uninstalled."
}
uninstall_docker() {
  log_info "Uninstalling Docker..."
  purge_packages docker-ce docker-ce-cli containerd.io
  rm -f /etc/apt/sources.list.d/docker.list
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
  log_info "Cleaning up orphaned packages..."
  apt autoremove -y
  apt clean
  log_success "All components uninstalled."
}

# --- MENU AND MAIN LOGIC ---

show_menu() {
  show_banner
  echo -e "${BOLD}Installation Menu:${NC}"
  echo -e "${BOLD}------------------${NC}"
  echo " 1) Update system packages"
  echo " 2) Install essential build tools"
  echo " 3) Install essential utilities (ranger, lsd, etc)"
  echo
  echo -e "${BOLD}Security (Recommended First):${NC}"
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
  echo " 11) Install NVM & Node.js"
  echo " 12) Install Rust"
  echo " 13) Install Go"
  echo " 14) Install Python & Poetry"
  echo " 15) Install Docker"
  echo " 16) Install rclone (Cloud Sync)"
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
    # Logical order for a complete, secure setup
    0)
      tasks=(1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16)
      will_exec_zsh=true
      ;;
    99) read -r -p "$(echo -e ${RED}${BOLD}"Sure? This will remove ALL script-installed components. [y/N] "${NC})" confirm && [[ "$confirm" =~ ^[yY]$ ]] && uninstall_all ;;
    *) tasks=($choices) ;;
    esac
    if [[ -n "${tasks-}" ]]; then
      for choice in "${tasks[@]}"; do
        case "$choice" in
        1) update_system ;; 2) install_build_essentials ;; 3) install_utilities ;; 4) install_firewall ;; 5) install_fail2ban ;; 6) install_zsh ;;
        7) install_starship ;; 8) install_nerd_font ;; 9) install_tmux ;; 10) install_git ;; 11) install_nvm_node ;; 12) install_rust ;;
        13) install_go ;; 14) install_python_poetry ;; 15) install_docker ;; 16) install_rclone ;;
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
