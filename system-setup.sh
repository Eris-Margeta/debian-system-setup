#!/bin/bash
# ==========================================================
# Remote Development Environment Setup Script
# For Debian/Ubuntu-based systems
# ==========================================================
# Version: 2.1.0
# Last Updated: Dec 3, 2025

# Set up colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Setup logging
LOG_FILE="/tmp/dev-env-setup-$(date +%Y%m%d-%H%M%S).log"
FAILURES=()

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

# Function to log errors
log_error() {
  echo -e "${RED}ERROR: $1${NC}" | tee -a "$LOG_FILE"
  FAILURES+=("$1")
}

# Function to log info
log_info() {
  echo -e "${BLUE}$1${NC}" | tee -a "$LOG_FILE"
}

# Function to log success
log_success() {
  echo -e "${GREEN}$1${NC}" | tee -a "$LOG_FILE"
}

# Function to display banner
show_banner() {
  clear
  echo -e "${BLUE}${BOLD}"
  echo "====================================================="
  echo "      Remote Development Environment Setup Script    "
  echo "====================================================="
  echo -e "${NC}"
  echo "This script will set up your development environment on"
  echo "Debian/Ubuntu-based systems."
  echo ""
}

#-----------------------------------------------------------------------------------------------------------------------------------------------
# Function to fix package repositories if needed
#-----------------------------------------------------------------------------------------------------------------------------------------------
fix_apt_sources() {
  log_info "Checking package repositories for errors..."

  # Find problematic source files and fix them
  for source_file in /etc/apt/sources.list.d/*.list; do
    if [ -f "$source_file" ]; then
      if grep -q "<!doctype" "$source_file" || grep -q "^E:" "$source_file"; then
        log_info "Found corrupted source file: $source_file, creating backup and disabling it"
        mv "$source_file" "${source_file}.bak"
        echo "# Temporarily disabled due to errors - $(date)" >"$source_file"
      fi
    fi
  done

  # Try to update apt
  apt update -y >/dev/null 2>&1 || {
    log_info "Attempting stronger fix for package repositories..."
    # More aggressive fix if needed
    mkdir -p /etc/apt/sources.list.d.backup
    mv /etc/apt/sources.list.d/*.list /etc/apt/sources.list.d.backup/ 2>/dev/null
    touch /etc/apt/sources.list.d/empty.list
    apt update -y >/dev/null 2>&1 || log_error "Unable to fix package repositories. Continuing anyway..."
  }
}

#-----------------------------------------------------------------------------------------------------------------------------------------------
# Function to update system
#-----------------------------------------------------------------------------------------------------------------------------------------------
update_system() {
  log_info "Updating system packages..."
  fix_apt_sources
  if ! apt update -y; then
    log_error "Failed to update package lists"
    return 1
  fi

  if ! apt upgrade -y; then
    log_error "Failed to upgrade packages"
    return 1
  fi

  return 0
}

#-----------------------------------------------------------------------------------------------------------------------------------------------
# Function to install essential build tools
#-----------------------------------------------------------------------------------------------------------------------------------------------
install_build_essentials() {
  log_info "Installing essential build tools..."
  build_tools=(
    "build-essential" "make" "libssl-dev" "libghc-zlib-dev" "libcurl4-gnutls-dev"
    "libexpat1-dev" "gettext" "unzip" "gfortran" "libopenblas-dev" "cmake"
  )
  if ! apt install -y "${build_tools[@]}"; then
    log_error "Failed to install build tools: ${build_tools[*]}"
    return 1
  fi
  log_success "Build essentials installed successfully."
  return 0
}

uninstall_build_essentials() {
  log_info "Uninstalling essential build tools..."
  build_tools=(
    "build-essential" "make" "libssl-dev" "libghc-zlib-dev" "libcurl4-gnutls-dev"
    "libexpat1-dev" "gettext" "unzip" "gfortran" "libopenblas-dev" "cmake"
  )
  if ! apt purge -y "${build_tools[@]}"; then
    log_error "Failed to uninstall build tools."
    return 1
  fi
  log_success "Build essentials uninstalled successfully."
  return 0
}

#-----------------------------------------------------------------------------------------------------------------------------------------------
# Function to install modern terminal definitions
#-----------------------------------------------------------------------------------------------------------------------------------------------
install_terminal_definitions() {
  log_info "Installing modern terminal definitions..."
  if ! apt install -y ncurses-term; then
    log_error "Failed to install ncurses-term."
    return 1
  fi
  log_success "Modern terminal definitions installed successfully."
  return 0
}

uninstall_terminal_definitions() {
  log_info "Uninstalling modern terminal definitions..."
  if ! apt purge -y ncurses-term; then
    log_error "Failed to uninstall ncurses-term."
    return 1
  fi
  log_success "Modern terminal definitions uninstalled successfully."
  return 0
}

#-----------------------------------------------------------------------------------------------------------------------------------------------
# Function to install ZSH and set it as default shell
#-----------------------------------------------------------------------------------------------------------------------------------------------
install_zsh() {
  log_info "Installing ZSH and setting it as default shell..."
  if ! apt install -y zsh zplug; then
    log_error "Failed to install zsh and zplug"
    return 1
  fi

  if [ -f "$ACTUAL_HOME/.zshrc" ]; then
    mv "$ACTUAL_HOME/.zshrc" "$ACTUAL_HOME/.zshrc.backup.$(date +%Y%m%d%H%M%S)"
  fi

  cat >"$ACTUAL_HOME/.zshrc" <<'EOL'
# Fix for modern terminals like Kitty
export TERM=xterm
# Set path if required
#export PATH=$GOPATH/bin:/usr/local/go/bin:$PATH
# Aliases
alias ec="sudo nvim ~/.zshrc"
alias sc="source ~/.zshrc"
alias ls="lsd"
alias fd="fdfind"
# Keep 5000 lines of history within the shell and save it to ~/.zsh_history:
HISTSIZE=5000
SAVEHIST=5000
HISTFILE=~/.zsh_history
# zplug - manage plugins
source /usr/share/zplug/init.zsh
zplug "zsh-users/zsh-syntax-highlighting"
zplug "zsh-users/zsh-autosuggestions"
zplug "zsh-users/zsh-history-substring-search"
zplug "zsh-users/zsh-completions"
# zplug - install/load new plugins when zsh is started or reloaded
if ! zplug check --verbose; then
    printf "Install? [y/N]: "
    if read -q; then
        echo; zplug install
    fi
fi
zplug load
# Enable completion caching
zstyle ':completion::complete:*' use-cache on
zstyle ':completion::complete:*' cache-path ~/.zsh/cache/$HOST
EOL

  chown "$ACTUAL_USER:$ACTUAL_USER" "$ACTUAL_HOME/.zshrc"
  chsh -s "$(command -v zsh)" "$ACTUAL_USER"
  log_success "ZSH setup completed successfully."
  return 0
}

uninstall_zsh() {
  log_info "Uninstalling ZSH and reverting shell..."
  # Change shell back to bash for the user
  chsh -s /bin/bash "$ACTUAL_USER"
  # Remove zsh and zplug
  apt purge -y zsh zplug
  # Remove zsh configuration files
  rm -f "$ACTUAL_HOME/.zshrc"
  rm -f "$ACTUAL_HOME/.zsh_history"
  rm -rf "$ACTUAL_HOME/.zsh"
  log_success "ZSH uninstalled and shell reverted to bash."
  return 0
}

#-----------------------------------------------------------------------------------------------------------------------------------------------
# Function to install Git and GitHub CLI
#-----------------------------------------------------------------------------------------------------------------------------------------------
install_git() {
  log_info "Installing Git and GitHub CLI..."
  apt install -y git
  curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
  chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | tee /etc/apt/sources.list.d/github-cli.list >/dev/null
  apt update
  apt install -y gh
  log_success "Git and GitHub CLI installed successfully."
  return 0
}

uninstall_git() {
  log_info "Uninstalling Git and GitHub CLI..."
  apt purge -y git gh
  rm -f /etc/apt/sources.list.d/github-cli.list
  rm -f /usr/share/keyrings/githubcli-archive-keyring.gpg
  apt update
  log_success "Git and GitHub CLI uninstalled successfully."
  return 0
}

#-----------------------------------------------------------------------------------------------------------------------------------------------
# Function to install curl, wget, and other utilities
#-----------------------------------------------------------------------------------------------------------------------------------------------
install_utilities() {
  log_info "Installing utilities (curl, wget, htop, iotop, tree, lsd)..."
  if ! apt install -y curl wget htop tree iotop lsd; then
    log_error "Failed to install utilities"
    return 1
  fi
  log_success "Utilities installed successfully."
  return 0
}

uninstall_utilities() {
  log_info "Uninstalling utilities..."
  if ! apt purge -y curl wget htop tree iotop lsd; then
    log_error "Failed to uninstall utilities."
    return 1
  fi
  log_success "Utilities uninstalled successfully."
  return 0
}

#-----------------------------------------------------------------------------------------------------------------------------------------------
# Function to install fzf and ripgrep
#-----------------------------------------------------------------------------------------------------------------------------------------------
install_search_tools() {
  log_info "Installing search tools (fzf, ripgrep, fd)..."
  if ! apt install -y fzf ripgrep fd-find; then
    log_error "Failed to install search tools"
    return 1
  fi
  echo "alias fd=fdfind" >>"$ACTUAL_HOME/.zshrc"
  log_success "Search tools installed successfully."
  return 0
}

uninstall_search_tools() {
  log_info "Uninstalling search tools..."
  apt purge -y fzf ripgrep fd-find
  sed -i '/alias fd=fdfind/d' "$ACTUAL_HOME/.zshrc"
  log_success "Search tools uninstalled successfully."
  return 0
}

#-----------------------------------------------------------------------------------------------------------------------------------------------
# Function to install Lua
#-----------------------------------------------------------------------------------------------------------------------------------------------
install_lua() {
  log_info "Setting up Lua 5.1 and LuaJIT..."
  if ! apt install -y lua5.1 luajit; then
    log_error "Failed to install Lua packages"
    return 1
  fi
  log_success "Lua installed successfully."
  return 0
}

uninstall_lua() {
  log_info "Uninstalling Lua..."
  if ! apt purge -y lua5.1 luajit; then
    log_error "Failed to uninstall Lua packages."
    return 1
  fi
  log_success "Lua uninstalled successfully."
  return 0
}

#-----------------------------------------------------------------------------------------------------------------------------------------------
# Function to install LuaRocks
#-----------------------------------------------------------------------------------------------------------------------------------------------
install_luarocks() {
  log_info "Installing LuaRocks..."
  apt install -y luarocks
  log_success "LuaRocks installed successfully."
  return 0
}

uninstall_luarocks() {
  log_info "Uninstalling LuaRocks..."
  apt purge -y luarocks
  log_success "LuaRocks uninstalled successfully."
  return 0
}

#-----------------------------------------------------------------------------------------------------------------------------------------------
# Function to install Node.js
#-----------------------------------------------------------------------------------------------------------------------------------------------
install_nvm_node() {
  log_info "Setting up Node.js environment..."
  su - "$ACTUAL_USER" -c "curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash"
  cat >>"$ACTUAL_HOME/.zshrc" <<'EOL'
# NVM Setup
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
EOL
  su - "$ACTUAL_USER" -c "
    export NVM_DIR=\"\$HOME/.nvm\"
    [ -s \"\$NVM_DIR/nvm.sh\" ] && . \"\$NVM_DIR/nvm.sh\"
    nvm install 20.10.0
    nvm alias default 20.10.0
    npm i -g pnpm neovim
  "
  log_success "Node.js environment setup completed successfully!"
  return 0
}

uninstall_nvm_node() {
  log_info "Uninstalling NVM and Node.js..."
  su - "$ACTUAL_USER" -c "
        export NVM_DIR=\"\$HOME/.nvm\"
        [ -s \"\$NVM_DIR/nvm.sh\" ] && . \"\$NVM_DIR/nvm.sh\"
        nvm unload
    "
  rm -rf "$ACTUAL_HOME/.nvm"
  sed -i '/NVM_DIR/d' "$ACTUAL_HOME/.zshrc"
  sed -i '/nvm.sh/d' "$ACTUAL_HOME/.zshrc"
  log_success "NVM and Node.js uninstalled successfully."
  return 0
}

#-----------------------------------------------------------------------------------------------------------------------------------------------
# Function to install Nerd Font
#-----------------------------------------------------------------------------------------------------------------------------------------------
install_nerd_font() {
  log_info "Installing Nerd Font..."
  mkdir -p "$ACTUAL_HOME/.local/share/fonts"
  cd /tmp || return 1
  wget -q https://github.com/ryanoasis/nerd-fonts/releases/download/v3.2.1/Hack.zip
  unzip -q Hack.zip -d "$ACTUAL_HOME/.local/share/fonts/Hack"
  fc-cache -f
  rm -f Hack.zip
  log_success "Nerd Font installed successfully."
  return 0
}

uninstall_nerd_font() {
  log_info "Uninstalling Nerd Font..."
  rm -rf "$ACTUAL_HOME/.local/share/fonts/Hack"
  fc-cache -f
  log_success "Nerd Font uninstalled successfully."
  return 0
}

#-----------------------------------------------------------------------------------------------------------------------------------------------
# Function to install Rust
#-----------------------------------------------------------------------------------------------------------------------------------------------
install_rust() {
  log_info "Installing Rust..."
  su - "$ACTUAL_USER" -c "curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y"
  cat >>"$ACTUAL_HOME/.zshrc" <<'EOL'
# Rust setup
source $HOME/.cargo/env
EOL
  log_success "Rust installed successfully."
  return 0
}

uninstall_rust() {
  log_info "Uninstalling Rust..."
  su - "$ACTUAL_USER" -c "rustup self uninstall -y"
  sed -i '/# Rust setup/d' "$ACTUAL_HOME/.zshrc"
  sed -i '/source \$HOME\/.cargo\/env/d' "$ACTUAL_HOME/.zshrc"
  log_success "Rust uninstalled successfully."
  return 0
}

#-----------------------------------------------------------------------------------------------------------------------------------------------
# Function to install Docker
#-----------------------------------------------------------------------------------------------------------------------------------------------
install_docker() {
  log_info "Installing Docker"
  apt install -y ca-certificates curl gnupg
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  chmod a+r /etc/apt/keyrings/docker.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | tee /etc/apt/sources.list.d/docker.list >/dev/null
  apt update
  apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  log_success "Docker installed successfully."
  return 0
}

uninstall_docker() {
  log_info "Uninstalling Docker..."
  apt purge -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  rm -f /etc/apt/sources.list.d/docker.list
  rm -f /etc/apt/keyrings/docker.gpg
  apt update
  log_success "Docker uninstalled successfully."
  return 0
}

#-----------------------------------------------------------------------------------------------------------------------------------------------
# Function to install Poetry for Python
#-----------------------------------------------------------------------------------------------------------------------------------------------
install_python_poetry() {
  log_info "Installing Poetry and Python 3.12.3..."
  apt install -y build-essential libssl-dev zlib1g-dev libncurses5-dev libnss3-dev libreadline-dev libffi-dev libsqlite3-dev wget libbz2-dev libgdbm-dev libdb-dev liblzma-dev tk-dev uuid-dev python3-pip
  cd /tmp || return 1
  wget -q https://www.python.org/ftp/python/3.12.3/Python-3.12.3.tgz
  tar -xf Python-3.12.3.tgz
  cd Python-3.12.3 || return 1
  ./configure --enable-optimizations
  make -j"$(nproc)"
  make altinstall
  python3.12 -m ensurepip
  python3.12 -m pip install virtualenv pynvim
  su - "$ACTUAL_USER" -c "curl -sSL https://install.python-poetry.org | python3.12 -"
  cat >>"$ACTUAL_HOME/.zshrc" <<'EOL'
# Add Poetry to PATH
export PATH=$HOME/.local/bin:$PATH
EOL
  cd /tmp && rm -rf Python-3.12.3*
  log_success "Python 3.12.3 and Poetry installation completed successfully!"
  return 0
}

uninstall_python_poetry() {
  log_info "Uninstalling Poetry and Python 3.12..."
  su - "$ACTUAL_USER" -c "curl -sSL https://install.python-poetry.org | python3.12 - --uninstall"
  rm -rf "$ACTUAL_HOME/.local/bin/poetry"
  sed -i '/# Add Poetry to PATH/d' "$ACTUAL_HOME/.zshrc"
  sed -i '/export PATH=\$HOME\/.local\/bin:\$PATH/d' "$ACTUAL_HOME/.zshrc"
  # This is a bit tricky, uninstalling a compiled python is not straightforward
  # We will remove the binary.
  rm -f /usr/local/bin/python3.12
  log_success "Poetry and Python 3.12 uninstalled."
  return 0
}

#-----------------------------------------------------------------------------------------------------------------------------------------------
# Function to install tmux
#-----------------------------------------------------------------------------------------------------------------------------------------------
install_tmux() {
  log_info "Installing tmux 3.5a from source..."
  apt install -y git automake build-essential pkg-config libevent-dev libncurses5-dev bison
  cd /tmp || return 1
  git clone https://github.com/tmux/tmux.git
  cd tmux || return 1
  git checkout 3.5a
  sh autogen.sh
  ./configure
  make && make install
  cat >"$ACTUAL_HOME/.tmux.conf" <<'EOL'
set -g default-terminal "screen-256color"
set -g prefix C-a
bind C-a send-prefix
bind r source-file ~/.tmux.conf \; display "Config reloaded!"
bind | split-window -h
bind - split-window -v
set -g mouse on
EOL
  chown "$ACTUAL_USER":"$ACTUAL_USER" "$ACTUAL_HOME/.tmux.conf"
  cd /tmp && rm -rf tmux
  log_success "Tmux 3.5a installation completed successfully!"
  return 0
}

uninstall_tmux() {
  log_info "Uninstalling tmux..."
  # This is tricky as it's installed from source.
  # We can remove the binary and config.
  rm -f /usr/local/bin/tmux
  rm -f "$ACTUAL_HOME/.tmux.conf"
  log_success "Tmux uninstalled."
  return 0
}

#-----------------------------------------------------------------------------------------------------------------------------------------------
# Function to install Go
#-----------------------------------------------------------------------------------------------------------------------------------------------
install_go() {
  log_info "Installing Go..."
  cd /tmp || return 1
  wget -q https://dl.google.com/go/go1.21.7.linux-amd64.tar.gz
  rm -rf /usr/local/go
  tar -xzf go1.21.7.linux-amd64.tar.gz -C /usr/local
  cat >>"$ACTUAL_HOME/.zshrc" <<'EOL'
# Go setup
export PATH=$PATH:/usr/local/go/bin
export GOPATH=$HOME/go
export PATH=$PATH:$GOPATH/bin
EOL
  mkdir -p "$ACTUAL_HOME/go/"{bin,pkg,src}
  chown -R "$ACTUAL_USER":"$ACTUAL_USER" "$ACTUAL_HOME/go"
  rm -f /tmp/go1.21.7.linux-amd64.tar.gz
  log_success "Go installation completed successfully!"
  return 0
}

uninstall_go() {
  log_info "Uninstalling Go..."
  rm -rf /usr/local/go
  rm -rf "$ACTUAL_HOME/go"
  sed -i '/# Go setup/d' "$ACTUAL_HOME/.zshrc"
  sed -i '/export PATH=\$PATH:\/usr\/local\/go\/bin/d' "$ACTUAL_HOME/.zshrc"
  sed -i '/export GOPATH=\$HOME\/go/d' "$ACTUAL_HOME/.zshrc"
  sed -i '/export PATH=\$PATH:\$GOPATH\/bin/d' "$ACTUAL_HOME/.zshrc"
  log_success "Go uninstalled successfully."
  return 0
}

#-----------------------------------------------------------------------------------------------------------------------------------------------
# Function to install Neovim
#-----------------------------------------------------------------------------------------------------------------------------------------------
install_neovim() {
  log_info "Installing Neovim v0.11.1..."
  apt install -y tar gzip
  NVIM_DIR="$ACTUAL_HOME/nvim-linux-x86_64"
  mkdir -p "$NVIM_DIR"
  cd /tmp || return 1
  wget https://github.com/neovim/neovim/releases/download/v0.11.1/nvim-linux-x86_64.tar.gz
  tar xzvf nvim-linux-x86_64.tar.gz -C "$ACTUAL_HOME"
  chown -R "$ACTUAL_USER":"$ACTUAL_USER" "$NVIM_DIR"
  cat >>"$ACTUAL_HOME/.zshrc" <<EOL
alias nvim='$NVIM_DIR/bin/nvim'
EOL
  su - "$ACTUAL_USER" -c "git clone https://github.com/LazyVim/starter ~/.config/nvim"
  rm -f /tmp/nvim-linux-x86_64.tar.gz
  log_success "Neovim v0.11.1 installation completed successfully!"
  return 0
}

uninstall_neovim() {
  log_info "Uninstalling Neovim..."
  NVIM_DIR="$ACTUAL_HOME/nvim-linux-x86_64"
  rm -rf "$NVIM_DIR"
  rm -rf "$ACTUAL_HOME/.config/nvim"
  sed -i "/alias nvim='$NVIM_DIR\/bin\/nvim'/d" "$ACTUAL_HOME/.zshrc"
  log_success "Neovim uninstalled successfully."
  return 0
}

#-----------------------------------------------------------------------------------------------------------------------------------------------
# Function to configure SSH with real-time priority
#-----------------------------------------------------------------------------------------------------------------------------------------------
configure_ssh_priority() {
  log_info "Configuring SSH with real-time priority..."
  mkdir -p /etc/systemd/system/ssh.service.d
  cat >/etc/systemd/system/ssh.service.d/override.conf <<'EOL'
[Service]
CPUSchedulingPolicy=rr
CPUSchedulingPriority=99
EOL
  systemctl daemon-reload
  systemctl restart ssh
  log_success "SSH configured with real-time priority successfully!"
  return 0
}

unconfigure_ssh_priority() {
  log_info "Unconfiguring SSH real-time priority..."
  rm -f /etc/systemd/system/ssh.service.d/override.conf
  systemctl daemon-reload
  systemctl restart ssh
  log_success "SSH real-time priority unconfigured."
  return 0
}

#-----------------------------------------------------------------------------------------------------------------------------------------------
# Function to install rsync
#-----------------------------------------------------------------------------------------------------------------------------------------------
install_rsync() {
  log_info "Installing rsync..."
  if ! apt install -y rsync; then
    log_error "Failed to install rsync"
    return 1
  fi
  log_success "rsync installation completed successfully!"
  return 0
}

uninstall_rsync() {
  log_info "Uninstalling rsync..."
  if ! apt purge -y rsync; then
    log_error "Failed to uninstall rsync."
    return 1
  fi
  log_success "rsync uninstalled successfully."
  return 0
}

#-----------------------------------------------------------------------------------------------------------------------------------------------
# Function to create DEV directory
#-----------------------------------------------------------------------------------------------------------------------------------------------
create_dev_directory() {
  log_info "Creating DEV directory..."
  mkdir -p "$ACTUAL_HOME/DEV"
  chown "$ACTUAL_USER":"$ACTUAL_USER" "$ACTUAL_HOME/DEV"
  log_success "DEV directory created."
  return 0
}

remove_dev_directory() {
  log_info "Removing DEV directory..."
  rm -rf "$ACTUAL_HOME/DEV"
  log_success "DEV directory removed."
  return 0
}

#-----------------------------------------------------------------------------------------------------------------------------------------------
# Function to set additional ZSH optimizations
#-----------------------------------------------------------------------------------------------------------------------------------------------
optimize_zsh() {
  log_info "Setting additional ZSH optimizations..."
  cat >>"$ACTUAL_HOME/.zshrc" <<'EOL'
# ZSH performance optimizations
alias update='sudo apt update && sudo apt upgrade -y'
alias install='sudo apt install -y'
EOL
  log_success "ZSH optimizations applied."
  return 0
}

unoptimize_zsh() {
  log_info "Removing ZSH optimizations..."
  sed -i '/# ZSH performance optimizations/d' "$ACTUAL_HOME/.zshrc"
  sed -i "/alias update='sudo apt update && sudo apt upgrade -y'/d" "$ACTUAL_HOME/.zshrc"
  sed -i "/alias install='sudo apt install -y'/d" "$ACTUAL_HOME/.zshrc"
  log_success "ZSH optimizations removed."
  return 0
}

#-----------------------------------------------------------------------------------------------------------------------------------------------
# UNINSTALL ALL FUNCTION
#-----------------------------------------------------------------------------------------------------------------------------------------------
uninstall_all() {
  log_info "Starting complete uninstallation process..."
  uninstall_neovim
  uninstall_go
  uninstall_tmux
  uninstall_python_poetry
  uninstall_docker
  uninstall_rust
  uninstall_nerd_font
  uninstall_nvm_node
  uninstall_luarocks
  uninstall_lua
  uninstall_search_tools
  uninstall_utilities
  uninstall_git
  unconfigure_ssh_priority
  uninstall_rsync
  remove_dev_directory
  unoptimize_zsh
  uninstall_zsh # Do this late
  uninstall_terminal_definitions
  uninstall_build_essentials
  log_info "Cleaning up..."
  apt autoremove -y
  apt clean
  log_success "All components have been uninstalled."
}

#-----------------------------------------------------------------------------------------------------------------------------------------------
# Function to display the menu and allow selecting tasks
#-----------------------------------------------------------------------------------------------------------------------------------------------
show_menu() {
  show_banner
  echo -e "${BOLD}Available tasks:${NC}"
  echo "1)  Update system packages"
  echo "2)  Install essential build tools"
  echo "3)  Install modern terminal definitions (Fix for Kitty terminal)"
  echo "4)  Install ZSH and set as default shell"
  echo "5)  Install Git and GitHub CLI"
  echo "6)  Install utilities (curl, wget, htop, iotop, tree, lsd)"
  echo "7)  Install search tools (fzf, ripgrep, fd)"
  echo "8)  Install Lua 5.1 and LuaJIT"
  echo "9)  Install LuaRocks"
  echo "10) Install NVM and Node.js"
  echo "11) Install Nerd Font"
  echo "12) Install Rust"
  echo "13) Install Docker"
  echo "14) Install Poetry and Python 3.12.3"
  echo "15) Install tmux 3.5a"
  echo "16) Install Go"
  echo "17) Install Neovim v0.11.1 and LazyVim"
  echo "18) Configure SSH with real-time priority"
  echo "19) Install rsync"
  echo "20) Create DEV directory"
  echo "21) Apply additional ZSH optimizations"
  echo ""
  echo "0)  Install ALL (complete setup)"
  echo "99) ${RED}Uninstall ALL${NC}"
  echo "q)  Quit"
  echo ""
  echo -e "${BOLD}Enter your choice (or multiple choices separated by spaces):${NC}"
  read -r -p "> " choices
}

#-----------------------------------------------------------------------------------------------------------------------------------------------
# Main function
#-----------------------------------------------------------------------------------------------------------------------------------------------
main() {
  while true; do
    show_menu
    if [[ "$choices" == "q" || "$choices" == "Q" ]]; then
      echo "Exiting setup script. Goodbye!"
      exit 0
    elif [ "$choices" == "0" ]; then
      update_system
      install_build_essentials
      install_terminal_definitions
      install_zsh
      install_git
      install_utilities
      install_search_tools
      install_lua
      install_luarocks
      install_nvm_node
      install_nerd_font
      install_rust
      install_docker
      install_python_poetry
      install_tmux
      install_go
      install_neovim
      configure_ssh_priority
      install_rsync
      create_dev_directory
      optimize_zsh
      log_success "All tasks completed!"
      read -r -p "Press Enter to return to the menu..."
    elif [ "$choices" == "99" ]; then
      read -r -p "$(echo -e ${RED}${BOLD}"Are you sure you want to uninstall everything? [y/N] "${NC})" confirm
      if [[ "$confirm" =~ ^[yY]$ ]]; then
        uninstall_all
      else
        log_info "Uninstallation cancelled."
      fi
      read -r -p "Press Enter to return to the menu..."
    else
      for choice in $choices; do
        case "$choice" in
        1) update_system ;;
        2) install_build_essentials ;;
        3) install_terminal_definitions ;;
        4) install_zsh ;;
        5) install_git ;;
        6) install_utilities ;;
        7) install_search_tools ;;
        8) install_lua ;;
        9) install_luarocks ;;
        10) install_nvm_node ;;
        11) install_nerd_font ;;
        12) install_rust ;;
        13) install_docker ;;
        14) install_python_poetry ;;
        15) install_tmux ;;
        16) install_go ;;
        17) install_neovim ;;
        18) configure_ssh_priority ;;
        19) install_rsync ;;
        20) create_dev_directory ;;
        21) optimize_zsh ;;
        *) echo "Invalid choice: $choice" ;;
        esac
      done
      log_success "Selected tasks completed!"
      read -r -p "Press Enter to return to the menu..."
    fi
  done
}

main
