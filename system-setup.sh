#!/bin/bash

# ==========================================================
# Remote Development Environment Setup Script
# For Debian/Ubuntu-based systems
# ==========================================================
# Version: 2.0.0
# Last Updated: May 2, 2025

# Set up colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
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
  ACTUAL_USER=$(whoami)
else
  ACTUAL_USER=$SUDO_USER
fi
ACTUAL_HOME=$(eval echo ~$ACTUAL_USER)

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

# Function to fix package repositories if needed
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

# Function to update system
update_system() {
  log_info "Updating system packages..."

  fix_apt_sources
  apt update -y
  if [ $? -ne 0 ]; then
    log_error "Failed to update package lists"
    return 1
  fi

  apt upgrade -y
  if [ $? -ne 0 ]; then
    log_error "Failed to upgrade packages"
    return 1
  fi

  return 0
}

# Function to install essential build tools
install_build_essentials() {
  log_info "Installing essential build tools..."

  apt install -y build-essential make libssl-dev libghc-zlib-dev \
    libcurl4-gnutls-dev libexpat1-dev gettext unzip \
    gfortran libopenblas-dev cmake

  if [ $? -ne 0 ] || ! command -v gcc >/dev/null 2>&1; then
    log_error "Failed to install build essentials"
    return 1
  fi

  return 0
}

# Function to install ZSH and set it as default shell
install_zsh() {
  log_info "Installing ZSH and setting as default shell..."
  apt install -y zsh zplug

  if [ $? -ne 0 ] || ! command -v zsh >/dev/null 2>&1; then
    log_error "Failed to install ZSH"
    return 1
  fi

  # Create .zshrc file if it doesn't exist
  if [ ! -f "$ACTUAL_HOME/.zshrc" ]; then
    cat >"$ACTUAL_HOME/.zshrc" <<'EOL'
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
    chown $ACTUAL_USER:$ACTUAL_USER "$ACTUAL_HOME/.zshrc"
  fi

  # Change default shell for the user
  chsh -s /bin/zsh $ACTUAL_USER
  return 0
}

# Function to install Git and GitHub CLI
install_git() {
  log_info "Installing Git and GitHub CLI..."
  apt install -y git

  if [ $? -ne 0 ] || ! command -v git >/dev/null 2>&1; then
    log_error "Failed to install Git"
    return 1
  fi

  # Install GitHub CLI
  curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg 2>/dev/null
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | tee /etc/apt/sources.list.d/github-cli.list >/dev/null
  apt update -y
  apt install -y gh

  if ! command -v gh >/dev/null 2>&1; then
    log_error "Failed to install GitHub CLI"
    return 1
  fi

  return 0
}

# Function to install curl, wget, and other utilities
install_utilities() {
  log_info "Installing utilities (curl, wget, htop, iotop, tree, lsd)..."
  apt install -y curl wget htop tree iotop

  if [ $? -ne 0 ]; then
    log_error "Failed to install basic utilities"
    return 1
  fi

  # Install lsd (an advanced ls command)
  ARCH=$(dpkg --print-architecture)
  cd /tmp

  # Get the latest release URL
  LATEST_RELEASE_URL=$(curl -s https://api.github.com/repos/Peltoche/lsd/releases/latest | grep "browser_download_url.*lsd_.*_${ARCH}.deb" | cut -d : -f 2,3 | tr -d \")

  # Download and install the .deb package
  if [ ! -z "$LATEST_RELEASE_URL" ]; then
    wget -q $LATEST_RELEASE_URL -O lsd.deb
    dpkg -i lsd.deb
    rm lsd.deb
  else
    log_error "Failed to install lsd"
  fi

  return 0
}

# Function to install fzf and ripgrep
install_search_tools() {
  log_info "Installing search tools (fzf, ripgrep, fd)..."
  apt install -y fzf ripgrep fd-find

  if [ $? -ne 0 ]; then
    log_error "Failed to install search tools"
    return 1
  fi

  # Add alias for fd to .zshrc if not already there
  if ! grep -q "alias fd=fdfind" "$ACTUAL_HOME/.zshrc"; then
    echo "alias fd=fdfind" >>"$ACTUAL_HOME/.zshrc"
  fi

  return 0
}

# Function to install Lua
install_lua() {
  log_info "Installing Lua 5.1 and LuaJIT..."

  # Add buster repository temporarily for Lua 5.1
  if ! grep -q "deb http://deb.debian.org/debian buster main" /etc/apt/sources.list; then
    echo "# Add Buster repository for Lua 5.1" >>/etc/apt/sources.list
    echo "deb http://deb.debian.org/debian buster main" >>/etc/apt/sources.list
    apt update -y >/dev/null 2>&1
  fi

  # Install Lua 5.1 and LuaJIT
  apt install -y lua5.1 luajit

  if [ $? -ne 0 ]; then
    log_error "Failed to install Lua"
    return 1
  fi

  # Comment out the buster line to avoid issues
  sed -i 's/^deb http:\/\/deb.debian.org\/debian buster main/# deb http:\/\/deb.debian.org\/debian buster main/' /etc/apt/sources.list
  apt update -y >/dev/null 2>&1

  return 0
}

# Function to install LuaRocks
install_luarocks() {
  log_info "Installing LuaRocks 3.11.1..."

  # Download and install LuaRocks
  cd /tmp
  wget -q https://luarocks.org/releases/luarocks-3.11.1.tar.gz
  tar zxpf luarocks-3.11.1.tar.gz
  cd luarocks-3.11.1

  # Configure and install
  ./configure --with-lua-include=/usr/include/lua5.1
  make >/dev/null 2>&1
  make install >/dev/null 2>&1

  # Check if LuaRocks is installed correctly
  if ! command -v luarocks >/dev/null 2>&1; then
    log_error "Failed to install LuaRocks"
    return 1
  fi

  # Clean up
  cd /tmp
  rm -rf luarocks-3.11.1*

  return 0
}

# Function to install Node.js
install_node() {
  log_info "Installing NVM and Node.js..."

  # Install NVM
  su - $ACTUAL_USER -c "curl -s -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash"

  # Update .zshrc with NVM setup if not already there
  if ! grep -q "export NVM_DIR" "$ACTUAL_HOME/.zshrc"; then
    cat >>"$ACTUAL_HOME/.zshrc" <<'EOL'

# NVM Setup
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion
EOL
  fi

  # Source NVM
  export NVM_DIR="$ACTUAL_HOME/.nvm"
  [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"

  # Install latest Node.js and set it as default
  su - $ACTUAL_USER -c "source $ACTUAL_HOME/.nvm/nvm.sh && nvm install --lts && nvm use --lts && nvm alias default node" || {
    log_error "Failed to install Node.js"
    return 1
  }

  # Install pnpm globally
  su - $ACTUAL_USER -c "source $ACTUAL_HOME/.nvm/nvm.sh && npm i -g pnpm"

  # Install neovim support
  su - $ACTUAL_USER -c "source $ACTUAL_HOME/.nvm/nvm.sh && npm install -g neovim"

  return 0
}

# Function to install Nerd Font
install_nerd_font() {
  log_info "Installing Nerd Font..."

  # Create fonts directory if it doesn't exist
  mkdir -p "$ACTUAL_HOME/.local/share/fonts"

  # Download and install Hack Nerd Font (smaller than Operator Mono)
  cd /tmp
  wget -q https://github.com/ryanoasis/nerd-fonts/releases/download/v3.2.1/Hack.zip
  unzip -q Hack.zip -d "$ACTUAL_HOME/.local/share/fonts/Hack"

  if [ $? -ne 0 ]; then
    log_error "Failed to install Nerd Font"
    return 1
  fi

  # Update font cache
  fc-cache -f

  # Clean up
  rm -f Hack.zip

  return 0
}

# Function to install Rust
install_rust() {
  log_info "Installing Rust..."

  # Install Rust for the actual user
  su - $ACTUAL_USER -c "curl -s --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y"

  if [ $? -ne 0 ]; then
    log_error "Failed to install Rust"
    return 1
  fi

  # Add Rust to the user's PATH in .zshrc if not already there
  if ! grep -q "source \$HOME/.cargo/env" "$ACTUAL_HOME/.zshrc"; then
    cat >>"$ACTUAL_HOME/.zshrc" <<'EOL'

# Rust setup
source $HOME/.cargo/env
EOL
  fi

  return 0
}

# Function to install Docker
install_docker() {
  log_info "Installing Docker..."

  # Remove old versions if they exist
  apt remove -y docker docker-engine docker.io containerd runc >/dev/null 2>&1

  # Install dependencies
  apt install -y ca-certificates gnupg lsb-release

  # Add Docker's official GPG key
  mkdir -p /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg

  # Set up the repository
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list >/dev/null

  # Update and install Docker
  apt update -y >/dev/null 2>&1
  apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

  if [ $? -ne 0 ] || ! command -v docker >/dev/null 2>&1; then
    log_error "Failed to install Docker"
    return 1
  fi

  # Add user to the docker group
  usermod -aG docker $ACTUAL_USER

  return 0
}

# Function to install Poetry for Python
install_poetry() {
  log_info "Installing Poetry and Python 3.12.3..."

  # Install Python dependencies
  apt install -y build-essential libssl-dev zlib1g-dev libncurses5-dev libnss3-dev libreadline-dev libffi-dev libsqlite3-dev wget libbz2-dev libgdbm-dev libdb-dev liblzma-dev tk-dev uuid-dev

  # Download and extract Python
  cd /tmp
  wget -q https://www.python.org/ftp/python/3.12.3/Python-3.12.3.tgz
  tar -xf Python-3.12.3.tgz
  cd Python-3.12.3

  # Configure and install
  ./configure --enable-optimizations >/dev/null 2>&1
  make -j$(nproc) >/dev/null 2>&1
  make altinstall >/dev/null 2>&1

  if [ $? -ne 0 ] || ! command -v python3.12 >/dev/null 2>&1; then
    log_error "Failed to install Python 3.12.3"
    return 1
  fi

  # Create Python alias in .zshrc if not already there
  if ! grep -q "alias python=python3.12" "$ACTUAL_HOME/.zshrc"; then
    cat >>"$ACTUAL_HOME/.zshrc" <<'EOL'

# Python alias
alias python=python3.12
EOL
  fi

  # Install pip for system Python if needed
  apt install -y python3-pip

  # Install virtualenv
  python3.12 -m pip install virtualenv >/dev/null 2>&1

  # Install Poetry
  su - $ACTUAL_USER -c "curl -sSL https://install.python-poetry.org | python3.12 -" || {
    log_error "Failed to install Poetry"
    return 1
  }

  # Add Poetry to PATH in .zshrc if not already there
  if ! grep -q "\$HOME/.local/bin" "$ACTUAL_HOME/.zshrc"; then
    cat >>"$ACTUAL_HOME/.zshrc" <<'EOL'

# Add Poetry to PATH
export PATH=$HOME/.local/bin:$PATH
EOL
  fi

  # Clean up
  cd /tmp
  rm -rf Python-3.12.3*

  return 0
}

# Function to install tmux
install_tmux() {
  log_info "Installing tmux 3.5a from source..."

  # Install dependencies
  apt install -y git automake build-essential pkg-config libevent-dev libncurses5-dev bison

  # Clone and build tmux
  cd /tmp
  git clone https://github.com/tmux/tmux.git
  cd tmux
  git checkout 3.5a
  sh autogen.sh >/dev/null 2>&1
  ./configure >/dev/null 2>&1
  make >/dev/null 2>&1
  make install >/dev/null 2>&1

  if [ $? -ne 0 ] || ! command -v tmux >/dev/null 2>&1; then
    log_error "Failed to install tmux"
    return 1
  fi

  # Create basic tmux config
  if [ ! -f "$ACTUAL_HOME/.tmux.conf" ]; then
    cat >"$ACTUAL_HOME/.tmux.conf" <<'EOL'
# Improve colors
set -g default-terminal "screen-256color"
set -ga terminal-overrides ",*256col*:Tc"

# Set the prefix to Ctrl+a
unbind C-b
set -g prefix C-a
bind C-a send-prefix

# Reload config with r
bind r source-file ~/.tmux.conf \; display "Config reloaded!"

# Split panes using | and -
bind | split-window -h
bind - split-window -v
unbind '"'
unbind %

# Switch panes using Alt-arrow without prefix
bind -n M-Left select-pane -L
bind -n M-Right select-pane -R
bind -n M-Up select-pane -U
bind -n M-Down select-pane -D

# Enable mouse control
set -g mouse on

# Start window numbering at 1
set -g base-index 1
setw -g pane-base-index 1

# Don't rename windows automatically
set-option -g allow-rename off

# Increase scrollback buffer size
set -g history-limit 50000
EOL
    chown $ACTUAL_USER:$ACTUAL_USER "$ACTUAL_HOME/.tmux.conf"
  fi

  # Clean up
  cd /tmp
  rm -rf tmux

  return 0
}

# Function to install Go
install_go() {
  log_info "Installing Go..."

  # Download the latest Go binary
  cd /tmp
  wget -q https://dl.google.com/go/go1.21.7.linux-amd64.tar.gz

  # Remove any previous Go installation
  rm -rf /usr/local/go

  # Extract Go archive
  tar -xzf go1.21.7.linux-amd64.tar.gz -C /usr/local

  if [ $? -ne 0 ]; then
    log_error "Failed to install Go"
    return 1
  fi

  # Add Go to PATH in .zshrc if not already there
  if ! grep -q "export PATH=\$PATH:/usr/local/go/bin" "$ACTUAL_HOME/.zshrc"; then
    echo "" >>"$ACTUAL_HOME/.zshrc"
    echo "# Go setup" >>"$ACTUAL_HOME/.zshrc"
    echo "export PATH=\$PATH:/usr/local/go/bin" >>"$ACTUAL_HOME/.zshrc"
    echo "export GOPATH=\$HOME/go" >>"$ACTUAL_HOME/.zshrc"
    echo "export PATH=\$PATH:\$GOPATH/bin" >>"$ACTUAL_HOME/.zshrc"
  fi

  # Create Go workspace
  mkdir -p $ACTUAL_HOME/go/{bin,pkg,src}
  chown -R $ACTUAL_USER:$ACTUAL_USER $ACTUAL_HOME/go

  # Install lemonade for clipboard support
  export PATH=$PATH:/usr/local/go/bin
  go install github.com/lemonade-command/lemonade@latest
  mv $ACTUAL_HOME/go/bin/lemonade /usr/local/bin/

  # Clean up
  rm -f /tmp/go1.21.7.linux-amd64.tar.gz

  return 0
}

# Function to install Neovim
install_neovim() {
  log_info "Installing Neovim v0.11.1..."

  # Make sure tar is installed
  apt install -y tar gzip

  # Create Neovim directory in user's home
  NVIM_DIR="$ACTUAL_HOME/nvim-linux-x86_64"
  mkdir -p "$NVIM_DIR"

  # Download Neovim 0.11.1
  cd /tmp
  wget -q https://github.com/neovim/neovim/releases/download/v0.11.1/nvim-linux-x86_64.tar.gz

  # Extract to user's home
  tar xzvf nvim-linux-x86_64.tar.gz -C "$ACTUAL_HOME" >/dev/null 2>&1
  chown -R $ACTUAL_USER:$ACTUAL_USER "$NVIM_DIR"

  if [ $? -ne 0 ]; then
    log_error "Failed to install Neovim"
    return 1
  fi

  # Add Neovim to PATH in .zshrc if not already there
  if ! grep -q "alias nvim=" "$ACTUAL_HOME/.zshrc"; then
    sed -i "s/alias ec=\"sudo nvim ~\/.zshrc\"/alias ec=\"sudo $NVIM_DIR\/bin\/nvim ~\/.zshrc\"/" "$ACTUAL_HOME/.zshrc"
    cat >>"$ACTUAL_HOME/.zshrc" <<EOL

# Neovim setup
alias nvim='$NVIM_DIR/bin/nvim'
EOL
  fi

  # Install tree-sitter
  cd /tmp
  wget -q https://github.com/tree-sitter/tree-sitter/releases/download/v0.20.8/tree-sitter-linux-x64.gz
  gunzip tree-sitter-linux-x64.gz
  mv tree-sitter-linux-x64 /usr/local/bin/tree-sitter
  chmod +x /usr/local/bin/tree-sitter

  # Install Neovim Python support
  python3.12 -m pip install neovim >/dev/null 2>&1

  # Create directories for LazyVim
  mkdir -p $ACTUAL_HOME/.config

  # Clone LazyVim starter
  if [ ! -d "$ACTUAL_HOME/.config/nvim" ]; then
    su - $ACTUAL_USER -c "git clone https://github.com/LazyVim/starter ~/.config/nvim"
    su - $ACTUAL_USER -c "rm -rf ~/.config/nvim/.git"
  fi

  # Clean up
  rm -f /tmp/nvim-linux-x86_64.tar.gz

  return 0
}

# Function to configure SSH with real-time priority
configure_ssh_priority() {
  log_info "Configuring SSH with real-time priority..."

  # Configure SSH for real-time priority
  mkdir -p /etc/systemd/system/ssh.service.d
  cat >/etc/systemd/system/ssh.service.d/override.conf <<'EOL'
[Service]
CPUSchedulingPolicy=rr
CPUSchedulingPriority=99
EOL

  # Reload systemd and restart SSH service
  systemctl daemon-reload >/dev/null 2>&1
  systemctl restart ssh >/dev/null 2>&1

  if [ $? -ne 0 ]; then
    log_error "Failed to configure SSH with real-time priority"
    return 1
  fi

  return 0
}

# Function to install rsync
install_rsync() {
  log_info "Installing rsync..."
  apt install -y rsync

  if [ $? -ne 0 ] || ! command -v rsync >/dev/null 2>&1; then
    log_error "Failed to install rsync"
    return 1
  fi

  return 0
}

# Function to create DEV directory
create_dev_dir() {
  log_info "Creating DEV directory..."
  mkdir -p $ACTUAL_HOME/DEV
  chown $ACTUAL_USER:$ACTUAL_USER $ACTUAL_HOME/DEV

  return 0
}

# Function to set additional ZSH optimizations
optimize_zsh() {
  log_info "Setting additional ZSH optimizations..."

  # Add some useful aliases and configurations if not already present
  if ! grep -q "# ZSH performance optimizations" "$ACTUAL_HOME/.zshrc"; then
    cat >>"$ACTUAL_HOME/.zshrc" <<'EOL'

# ZSH performance optimizations
zstyle ':completion:*' accept-exact '*(N)'
zstyle ':completion:*' use-cache on
zstyle ':completion:*' cache-path ~/.zsh/cache

# Additional useful aliases
alias update='sudo apt update && sudo apt upgrade -y'
alias install='sudo apt install -y'
alias remove='sudo apt remove -y'
alias purge='sudo apt purge -y'
alias autoremove='sudo apt autoremove -y'

EOL
  fi

  return 0
}

# Function to display the menu and allow selecting tasks
show_menu() {
  show_banner
  echo -e "${BOLD}Available tasks:${NC}"
  echo "1)  Update system packages"
  echo "2)  Install essential build tools"
  echo "3)  Install ZSH and set as default shell"
  echo "4)  Install Git and GitHub CLI"
  echo "5)  Install utilities (curl, wget, htop, iotop, tree, lsd)"
  echo "6)  Install search tools (fzf, ripgrep, fd)"
  echo "7)  Install Lua 5.1 and LuaJIT"
  echo "8)  Install LuaRocks 3.11.1"
  echo "9)  Install NVM and Node.js"
  echo "10) Install Nerd Font"
  echo "11) Install Rust"
  echo "12) Install Docker"
  echo "13) Install Poetry and Python 3.12.3"
  echo "14) Install tmux 3.5a"
  echo "15) Install Go"
  echo "16) Install Neovim v0.11.1 and LazyVim"
  echo "17) Configure SSH with real-time priority"
  echo "18) Install rsync"
  echo "19) Create DEV directory"
  echo "20) Apply additional ZSH optimizations"
  echo "0)  Install ALL (complete setup)"
  echo "q)  Quit"
  echo ""
  echo -e "${BOLD}Enter your choice (or multiple choices separated by spaces):${NC}"
  read -p "> " choices
}

# Main function
main() {
  # Track completed tasks
  declare -a completed_tasks

  show_menu

  # Check for quit option
  if [[ "$choices" == "q" ]]; then
    log_info "Exiting without installing"
    exit 0
  fi

  # Check for install all option
  if [[ "$choices" == "0" ]]; then
    choices="1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20"
  fi

  # Process each choice
  for choice in $choices; do
    case $choice in
    1) update_system ;;
    2) install_build_essentials ;;
    3) install_zsh ;;
    4) install_git ;;
    5) install_utilities ;;
    6) install_search_tools ;;
    7) install_lua ;;
    8) install_luarocks ;;
    9) install_node ;;
    10) install_nerd_font ;;
    11) install_rust ;;
    12) install_docker ;;
    13) install_poetry ;;
    14) install_tmux ;;
    15) install_go ;;
    16) install_neovim ;;
    17) configure_ssh_priority ;;
    18) install_rsync ;;
    19) create_dev_dir ;;
    20) optimize_zsh ;;
    *) log_error "Invalid choice: $choice" ;;
    esac
  done

  # Report results
  if [ ${#FAILURES[@]} -eq 0 ]; then
    log_success "All tasks completed successfully!"
  else
    echo -e "\n${RED}${BOLD}The following errors occurred:${NC}"
    for error in "${FAILURES[@]}"; do
      echo -e "- $error"
    done
    echo -e "\nCheck the log file for more details: ${LOG_FILE}"
  fi

  echo -e "\n${GREEN}${BOLD}Setup completed!${NC}"
  echo -e "To apply all changes, log out and log back in or run:"
  echo -e "${BLUE}source ~/.zshrc${NC}"
}

# Run the main function
main 3 4 5 6 7 8 9 10 11 12 13 14 15 16
