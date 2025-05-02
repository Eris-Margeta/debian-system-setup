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
  if ! apt install -y --reinstall build-essential make libssl-dev libghc-zlib-dev \
    libcurl4-gnutls-dev libexpat1-dev gettext unzip \
    gfortran libopenblas-dev cmake || ! command -v gcc >/dev/null 2>&1; then
    log_error "Failed to install build essentials"
    return 1
  fi
  return 0
}

#-----------------------------------------------------------------------------------------------------------------------------------------------
# Function to install ZSH and set it as default shell
#-----------------------------------------------------------------------------------------------------------------------------------------------
install_zsh() {
  log_info "Installing/Reinstalling ZSH and setting as default shell..."

  # Install/Reinstall ZSH using the reinstall flag
  if ! apt install --reinstall -y zsh zplug; then
    log_error "Failed to reinstall ZSH"
    return 1
  fi

  # Verify installation
  if ! command -v zsh >/dev/null 2>&1; then
    log_error "ZSH installation verification failed"
    return 1
  else
    log_success "ZSH installed successfully: $(zsh --version)"
  fi

  # Create/overwrite .zshrc file
  log_info "Creating/updating .zshrc configuration..."
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

  # Ensure correct ownership of the .zshrc file
  chown "$ACTUAL_USER:$ACTUAL_USER" "$ACTUAL_HOME/.zshrc"

  # Change default shell for the user (will work even if already set)
  log_info "Setting ZSH as the default shell for $ACTUAL_USER..."
  chsh -s "$(command -v zsh)" "$ACTUAL_USER"

  log_success "ZSH setup completed successfully"
  return 0
}

#-----------------------------------------------------------------------------------------------------------------------------------------------
# Function to install Git and GitHub CLI
#-----------------------------------------------------------------------------------------------------------------------------------------------
install_git() {
  log_info "Installing/Reinstalling Git and GitHub CLI..."

  # Install/Reinstall Git
  log_info "Installing Git..."
  if ! apt install --reinstall -y git; then
    log_error "Failed to reinstall Git"
    return 1
  fi

  # Verify Git installation
  if ! command -v git >/dev/null 2>&1; then
    log_error "Git installation verification failed"
    return 1
  else
    log_success "Git installed successfully: $(git --version)"
  fi

  # Setup GitHub CLI repository keys (needed even for reinstall)
  log_info "Setting up GitHub CLI repository..."
  curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg 2>/dev/null

  # Setup GitHub CLI repository
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | tee /etc/apt/sources.list.d/github-cli.list >/dev/null

  # Update package lists
  apt update -y

  # Install/Reinstall GitHub CLI
  log_info "Installing GitHub CLI..."
  if ! apt install --reinstall -y gh; then
    log_error "Failed to reinstall GitHub CLI"
    return 1
  fi

  # Verify GitHub CLI installation
  if ! command -v gh >/dev/null 2>&1; then
    log_error "GitHub CLI installation verification failed"
    return 1
  else
    log_success "GitHub CLI installed successfully: $(gh --version)"
  fi

  log_success "Git and GitHub CLI reinstallation completed successfully"
  return 0
}

#-----------------------------------------------------------------------------------------------------------------------------------------------
# Function to install curl, wget, and other utilities
#-----------------------------------------------------------------------------------------------------------------------------------------------
install_utilities() {
  log_info "Installing utilities (curl, wget, htop, iotop, tree, lsd)..."
  if ! apt install -y --reinstall curl wget htop tree iotop lsd; then
    log_error "Failed to install basic utilities"
    return 1
  fi
  return 0
}

#-----------------------------------------------------------------------------------------------------------------------------------------------
# Function to install fzf and ripgrep
#-----------------------------------------------------------------------------------------------------------------------------------------------
install_search_tools() {
  log_info "Installing search tools (fzf, ripgrep, fd)..."
  if ! apt install -y --reinstall fzf ripgrep fd-find; then
    log_error "Failed to install search tools"
    return 1
  fi

  # Add alias for fd to .zshrc if not already there
  if ! grep -q "alias fd=fdfind" "$ACTUAL_HOME/.zshrc"; then
    echo "alias fd=fdfind" >>"$ACTUAL_HOME/.zshrc"
  fi
  return 0
}

#-----------------------------------------------------------------------------------------------------------------------------------------------
# Function to install Lua
#-----------------------------------------------------------------------------------------------------------------------------------------------
install_lua() {
  log_info "Setting up Lua 5.1 and LuaJIT..."

  # Check if Lua and LuaJIT are already installed
  local lua_installed=false
  local luajit_installed=false

  if dpkg -l | grep -q "lua5.1"; then
    lua_installed=true
    log_info "Lua 5.1 is already installed, will reinstall"
  fi

  if dpkg -l | grep -q "luajit"; then
    luajit_installed=true
    log_info "LuaJIT is already installed, will reinstall"
  fi

  # Clean up custom installations only if they exist
  if [ -d "/usr/local/bin/lua" ]; then
    log_info "Removing custom Lua installation from /usr/local/bin/lua"
    rm -rf /usr/local/bin/lua*
  fi

  if [ -d "/usr/local/bin/luajit" ]; then
    log_info "Removing custom LuaJIT installation from /usr/local/bin/luajit"
    rm -rf /usr/local/bin/luajit*
  fi

  if [ -d "/usr/local/include/lua" ]; then
    log_info "Removing custom Lua headers from /usr/local/include/lua"
    rm -rf /usr/local/include/lua*
  fi

  if [ -d "/usr/local/lib/lua" ]; then
    log_info "Removing custom Lua libraries from /usr/local/lib/lua"
    rm -rf /usr/local/lib/lua*
  fi

  # Add buster repository temporarily for Lua 5.1 if needed
  if ! grep -q "deb http://deb.debian.org/debian buster main" /etc/apt/sources.list; then
    log_info "Adding Debian Buster repository for Lua 5.1"
    echo "# Add Buster repository for Lua 5.1" >>/etc/apt/sources.list
    echo "deb http://deb.debian.org/debian buster main" >>/etc/apt/sources.list
    apt update -y >/dev/null 2>&1
  fi

  # Install or reinstall Lua and LuaJIT as needed
  local install_cmd="apt install -y"

  if $lua_installed; then
    install_cmd+=" --reinstall lua5.1"
  else
    install_cmd+=" lua5.1"
  fi

  if $luajit_installed; then
    install_cmd+=" --reinstall luajit"
  else
    install_cmd+=" luajit"
  fi

  log_info "Installing/reinstalling Lua packages with: $install_cmd"
  if ! eval "$install_cmd"; then
    log_error "Failed to install Lua packages"
    return 1
  fi

  # Comment out the buster line to avoid issues
  sed -i 's/^deb http:\/\/deb.debian.org\/debian buster main/# deb http:\/\/deb.debian.org\/debian buster main/' /etc/apt/sources.list
  apt update -y >/dev/null 2>&1

  log_info "Lua installation completed successfully"
  return 0
}

#-----------------------------------------------------------------------------------------------------------------------------------------------
# Function to install LuaRocks
#-----------------------------------------------------------------------------------------------------------------------------------------------
install_luarocks() {
  log_info "Installing LuaRocks 3.11.1..."

  # Create a temporary directory with a specific name to avoid conflicts
  TEMP_DIR="$HOME/luarocks_install_tmp"
  mkdir -p "$TEMP_DIR"

  # Navigate to the temp directory and verify we're there
  cd "$TEMP_DIR" || {
    log_error "Failed to create/navigate to temporary directory"
    return 1
  }

  # Download LuaRocks with error checking
  log_info "Downloading LuaRocks..."
  if ! wget -q https://luarocks.org/releases/luarocks-3.11.1.tar.gz; then
    log_error "Failed to download LuaRocks"
    cd "$HOME" && rm -rf "$TEMP_DIR"
    return 1
  fi

  # Extract with error checking
  log_info "Extracting LuaRocks..."
  if ! tar zxpf luarocks-3.11.1.tar.gz; then
    log_error "Failed to extract LuaRocks"
    cd "$HOME" && rm -rf "$TEMP_DIR"
    return 1
  fi

  # Navigate to the extracted directory
  if ! cd "luarocks-3.11.1"; then
    log_error "Failed to navigate to LuaRocks directory - extraction may have failed"
    cd "$HOME" && rm -rf "$TEMP_DIR"
    return 1
  fi

  # Configure and install with error checking
  log_info "Configuring LuaRocks..."
  if ! ./configure --with-lua-include=/usr/include/lua5.1; then
    log_error "Failed to configure LuaRocks"
    cd "$HOME" && rm -rf "$TEMP_DIR"
    return 1
  fi

  log_info "Building LuaRocks..."
  if ! make; then
    log_error "Failed to build LuaRocks"
    cd "$HOME" && rm -rf "$TEMP_DIR"
    return 1
  fi

  log_info "Installing LuaRocks..."
  if ! make install; then
    log_error "Failed to install LuaRocks"
    cd "$HOME" && rm -rf "$TEMP_DIR"
    return 1
  fi

  # Check if LuaRocks is installed correctly
  if ! command -v luarocks >/dev/null 2>&1; then
    log_error "LuaRocks installation completed but the 'luarocks' command is not available in PATH"
  else
    log_info "LuaRocks installed successfully"
  fi

  # Clean up
  cd "$HOME" || true
  rm -rf "$TEMP_DIR"

  # Final verification
  if command -v luarocks >/dev/null 2>&1; then
    log_info "LuaRocks version: $(luarocks --version)"
    return 0
  else
    log_error "LuaRocks installation failed"
    return 1
  fi
}

#-----------------------------------------------------------------------------------------------------------------------------------------------
# Function to install Node.js
#-----------------------------------------------------------------------------------------------------------------------------------------------
install_node() {
  log_info "Setting up Node.js environment..."

  # Check if NVM is installed and remove it
  if [ -d "$ACTUAL_HOME/.nvm" ]; then
    log_info "Removing existing NVM installation..."
    su - "$ACTUAL_USER" -c "
      # Uninstall any existing node versions
      if command -v nvm &>/dev/null; then
        nvm use default
        nvm deactivate
        nvm uninstall --lts
        nvm uninstall default
        nvm uninstall node
      fi
    "

    # Remove NVM directory
    rm -rf "$ACTUAL_HOME/.nvm"

    # Remove NVM entries from shell config files
    for config_file in "$ACTUAL_HOME/.bashrc" "$ACTUAL_HOME/.zshrc" "$ACTUAL_HOME/.profile"; do
      if [ -f "$config_file" ]; then
        sed -i '/NVM_DIR/d' "$config_file"
        sed -i '/nvm.sh/d' "$config_file"
        sed -i '/bash_completion/d' "$config_file"
      fi
    done
  fi

  # Clean npm and pnpm caches if they exist
  log_info "Cleaning package manager caches..."
  su - "$ACTUAL_USER" -c "
    if command -v npm &>/dev/null; then
      npm cache clean --force
    fi
    
    if command -v pnpm &>/dev/null; then
      pnpm store prune
    fi
  "

  # Remove any globally installed Node.js
  if command -v apt &>/dev/null; then
    log_info "Removing system Node.js packages if they exist..."
    apt purge -y nodejs npm
    apt autoremove -y
  fi

  # Install NVM
  log_info "Installing NVM and Node.js 20.10.0..."
  su - "$ACTUAL_USER" -c "curl -s -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash"

  # Update .zshrc with NVM setup if not already there
  if ! grep -q "export NVM_DIR" "$ACTUAL_HOME/.zshrc"; then
    cat >>"$ACTUAL_HOME/.zshrc" <<'EOL'
# NVM Setup
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion
EOL
  fi

  # Install specific Node.js version and set it as default
  log_info "Installing Node.js 20.10.0..."
  su - "$ACTUAL_USER" -c "
    export NVM_DIR=\"\$HOME/.nvm\"
    [ -s \"\$NVM_DIR/nvm.sh\" ] && . \"\$NVM_DIR/nvm.sh\"
    nvm install 20.10.0
    nvm use 20.10.0
    nvm alias default 20.10.0
  " || {
    log_error "Failed to install Node.js 20.10.0"
    return 1
  }

  # Install pnpm globally
  log_info "Installing pnpm globally..."
  su - "$ACTUAL_USER" -c "
    export NVM_DIR=\"\$HOME/.nvm\"
    [ -s \"\$NVM_DIR/nvm.sh\" ] && . \"\$NVM_DIR/nvm.sh\"
    npm i -g pnpm
  "

  # Install neovim support
  log_info "Installing neovim support..."
  su - "$ACTUAL_USER" -c "
    export NVM_DIR=\"\$HOME/.nvm\"
    [ -s \"\$NVM_DIR/nvm.sh\" ] && . \"\$NVM_DIR/nvm.sh\"
    npm install -g neovim
  "

  log_info "Node.js 20.10.0 installation completed successfully"
  return 0
}

#-----------------------------------------------------------------------------------------------------------------------------------------------
# Function to install Nerd Font
#-----------------------------------------------------------------------------------------------------------------------------------------------
install_nerd_font() {
  log_info "Installing Nerd Font..."
  # Create fonts directory if it doesn't exist
  mkdir -p "$ACTUAL_HOME/.local/share/fonts"
  # Download and install Hack Nerd Font
  cd /tmp || return 1
  wget -q https://github.com/ryanoasis/nerd-fonts/releases/download/v3.2.1/Hack.zip
  if ! unzip -q Hack.zip -d "$ACTUAL_HOME/.local/share/fonts/Hack"; then
    log_error "Failed to install Nerd Font"
    return 1
  fi
  # Update font cache
  fc-cache -f
  # Clean up
  rm -f Hack.zip
  return 0
}

#-----------------------------------------------------------------------------------------------------------------------------------------------
# Function to install Rust
#-----------------------------------------------------------------------------------------------------------------------------------------------
install_rust() {
  log_info "Installing Rust..."
  # Install Rust for the actual user
  if ! su - "$ACTUAL_USER" -c "curl -s --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y"; then
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

#-----------------------------------------------------------------------------------------------------------------------------------------------
# Function to install Docker
#-----------------------------------------------------------------------------------------------------------------------------------------------
install_docker() {
  print_section "Installing Docker"

  # Check if Docker is already installed
  if command -v docker &>/dev/null; then
    echo "Docker is already installed. Skipping installation."
    return 0
  fi

  # Install dependencies
  echo "Installing Docker dependencies..."
  sudo apt-get update
  sudo apt-get install -y \
    ca-certificates \
    curl \
    gnupg \
    lsb-release

  # Create directory for Docker's GPG key
  sudo mkdir -p "/etc/apt/keyrings"

  # Download Docker's GPG key
  curl -fsSL "https://download.docker.com/linux/ubuntu/gpg" | sudo gpg --dearmor -o "/etc/apt/keyrings/docker.gpg"

  # Set correct permissions
  sudo chmod a+r "/etc/apt/keyrings/docker.gpg"

  # Add Docker repository
  echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
    $(lsb_release -cs) stable" | sudo tee "/etc/apt/sources.list.d/docker.list" >/dev/null

  # Update package lists
  sudo apt-get update

  # Check if apt-get update succeeded
  if ! sudo apt-get update; then
    echo "Failed to update package lists. Docker installation aborted."
    return 1
  fi

  # Install Docker packages
  echo "Installing Docker Engine and related tools..."
  if ! sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin; then
    echo "Failed to install Docker packages. Installation aborted."
    return 1
  fi

  # Add current user to docker group to run docker without sudo
  echo "Adding user to the docker group..."
  if ! sudo usermod -aG docker "$USER"; then
    echo "Failed to add user to docker group. You may need to run Docker with sudo."
  fi

  echo "Docker has been successfully installed!"
  echo "You will need to log out and back in for the group changes to take effect."
  echo "After logging back in, you can test Docker with: docker run hello-world"
}

#-----------------------------------------------------------------------------------------------------------------------------------------------
# Function to install Poetry for Python
#-----------------------------------------------------------------------------------------------------------------------------------------------
install_poetry() {
  log_info "Installing Poetry and Python 3.12.3..."
  # Install Python dependencies
  apt install -y build-essential libssl-dev zlib1g-dev libncurses5-dev libnss3-dev libreadline-dev libffi-dev libsqlite3-dev wget libbz2-dev libgdbm-dev libdb-dev liblzma-dev tk-dev uuid-dev
  # Download and extract Python
  cd /tmp || return 1
  if ! wget -q https://www.python.org/ftp/python/3.12.3/Python-3.12.3.tgz; then
    log_error "Failed to download Python 3.12.3"
    return 1
  fi

  if ! tar -xf Python-3.12.3.tgz; then
    log_error "Failed to extract Python 3.12.3"
    return 1
  fi

  cd Python-3.12.3 || return 1
  # Configure and install
  if ! ./configure --enable-optimizations >/dev/null 2>&1; then
    log_error "Failed to configure Python 3.12.3"
    return 1
  fi

  if ! make -j"$(nproc)" >/dev/null 2>&1; then
    log_error "Failed to make Python 3.12.3"
    return 1
  fi

  if ! make altinstall >/dev/null 2>&1 || ! command -v python3.12 >/dev/null 2>&1; then
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

  # Install pip for system Python
  if ! apt install -y python3-pip; then
    log_error "Failed to install system Python pip"
    return 1
  fi

  # Install pip for Python 3.12 if not already installed with Python
  if ! python3.12 -m ensurepip; then
    log_error "Failed to ensure pip for Python 3.12"
    return 1
  fi

  # Install virtualenv
  if ! python3.12 -m pip install virtualenv >/dev/null 2>&1; then
    log_error "Failed to install virtualenv"
    return 1
  fi

  # Install neovim support globally
  if ! python3.12 -m pip install pynvim >/dev/null 2>&1; then
    log_error "Failed to install pynvim (neovim support)"
    return 1
  fi

  # Install Poetry
  if ! su - "$ACTUAL_USER" -c "curl -sSL https://install.python-poetry.org | python3.12 -"; then
    log_error "Failed to install Poetry"
    return 1
  fi

  # Add Poetry to PATH in .zshrc if not already there
  if ! grep -q "\$HOME/.local/bin" "$ACTUAL_HOME/.zshrc"; then
    cat >>"$ACTUAL_HOME/.zshrc" <<'EOL'
# Add Poetry to PATH
export PATH=$HOME/.local/bin:$PATH
EOL
  fi

  # Clean up
  cd /tmp || return 1
  rm -rf Python-3.12.3*
  return 0
}

#-----------------------------------------------------------------------------------------------------------------------------------------------
# Function to install tmux
#-----------------------------------------------------------------------------------------------------------------------------------------------
install_tmux() {
  log_info "Installing tmux 3.5a from source..."
  # Install dependencies
  if ! apt install -y git automake build-essential pkg-config libevent-dev libncurses5-dev bison; then
    log_error "Failed to install tmux dependencies"
    return 1
  fi

  # Clone and build tmux
  cd /tmp || return 1
  if ! git clone https://github.com/tmux/tmux.git; then
    log_error "Failed to clone tmux repository"
    return 1
  fi

  cd tmux || return 1
  if ! git checkout 3.5a; then
    log_error "Failed to checkout tmux version 3.5a"
    return 1
  fi

  if ! sh autogen.sh >/dev/null 2>&1; then
    log_error "Failed to run autogen.sh for tmux"
    return 1
  fi

  if ! ./configure >/dev/null 2>&1; then
    log_error "Failed to configure tmux"
    return 1
  fi

  if ! make >/dev/null 2>&1; then
    log_error "Failed to make tmux"
    return 1
  fi

  if ! make install >/dev/null 2>&1 || ! command -v tmux >/dev/null 2>&1; then
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
    chown "$ACTUAL_USER":"$ACTUAL_USER" "$ACTUAL_HOME/.tmux.conf"
  fi

  # Clean up
  cd /tmp || return 1
  rm -rf tmux
  return 0
}

#-----------------------------------------------------------------------------------------------------------------------------------------------
# Function to install Go
#-----------------------------------------------------------------------------------------------------------------------------------------------
install_go() {
  log_info "Installing Go..."
  # Download the latest Go binary
  cd /tmp || return 1
  if ! wget -q https://dl.google.com/go/go1.21.7.linux-amd64.tar.gz; then
    log_error "Failed to download Go"
    return 1
  fi

  # Remove any previous Go installation
  rm -rf /usr/local/go

  # Extract Go archive
  if ! tar -xzf go1.21.7.linux-amd64.tar.gz -C /usr/local; then
    log_error "Failed to install Go"
    return 1
  fi

  # Add Go to PATH in .zshrc if not already there
  if ! grep -q "export PATH=\$PATH:/usr/local/go/bin" "$ACTUAL_HOME/.zshrc"; then
    {
      echo ""
      echo "# Go setup"
      echo "export PATH=\$PATH:/usr/local/go/bin"
      echo "export GOPATH=\$HOME/go"
      echo "export PATH=\$PATH:\$GOPATH/bin"
    } >>"$ACTUAL_HOME/.zshrc"
  fi

  # Create Go workspace
  mkdir -p "$ACTUAL_HOME/go/"{bin,pkg,src}
  chown -R "$ACTUAL_USER":"$ACTUAL_USER" "$ACTUAL_HOME/go"

  # Install lemonade for clipboard support
  export PATH=$PATH:/usr/local/go/bin
  if ! go install github.com/lemonade-command/lemonade@latest; then
    log_error "Failed to install lemonade"
    return 1
  fi

  if [ -f "$ACTUAL_HOME/go/bin/lemonade" ]; then
    mv "$ACTUAL_HOME/go/bin/lemonade" /usr/local/bin/
  else
    log_error "Lemonade binary not found after installation"
    return 1
  fi

  # Clean up
  rm -f /tmp/go1.21.7.linux-amd64.tar.gz
  return 0
}

#-----------------------------------------------------------------------------------------------------------------------------------------------
# Function to install Neovim
#-----------------------------------------------------------------------------------------------------------------------------------------------
install_neovim() {
  log_info "Installing Neovim v0.11.1..."
  # Make sure tar is installed
  if ! apt install -y tar gzip; then
    log_error "Failed to install tar and gzip"
    return 1
  fi

  # Create Neovim directory in user's home
  NVIM_DIR="$ACTUAL_HOME/nvim-linux-x86_64"
  mkdir -p "$NVIM_DIR"

  # Download Neovim 0.11.1
  cd /tmp || return 1
  if ! wget -q https://github.com/neovim/neovim/releases/download/v0.11.1/nvim-linux-x86_64.tar.gz; then
    log_error "Failed to download Neovim"
    return 1
  fi

  # Extract to user's home
  if ! tar xzvf nvim-linux-x86_64.tar.gz -C "$ACTUAL_HOME" >/dev/null 2>&1; then
    log_error "Failed to extract Neovim"
    return 1
  fi

  if ! chown -R "$ACTUAL_USER":"$ACTUAL_USER" "$NVIM_DIR"; then
    log_error "Failed to set ownership for Neovim directory"
    return 1
  fi

  # Add Neovim to PATH in .zshrc if not already there
  if ! grep -q "alias nvim=" "$ACTUAL_HOME/.zshrc"; then
    if ! sed -i "s/alias ec=\"sudo nvim ~\/.zshrc\"/alias ec=\"sudo $NVIM_DIR\/bin\/nvim ~\/.zshrc\"/" "$ACTUAL_HOME/.zshrc"; then
      log_error "Failed to update ec alias in .zshrc"
    fi

    cat >>"$ACTUAL_HOME/.zshrc" <<EOL
alias nvim='$NVIM_DIR/bin/nvim'
EOL
  fi

  # Install tree-sitter
  cd /tmp || return 1
  if ! wget -q https://github.com/tree-sitter/tree-sitter/releases/download/v0.20.8/tree-sitter-linux-x64.gz; then
    log_error "Failed to download tree-sitter"
    return 1
  fi

  if ! gunzip tree-sitter-linux-x64.gz; then
    log_error "Failed to extract tree-sitter"
    return 1
  fi

  if ! mv tree-sitter-linux-x64 /usr/local/bin/tree-sitter; then
    log_error "Failed to move tree-sitter to /usr/local/bin"
    return 1
  fi

  if ! chmod +x /usr/local/bin/tree-sitter; then
    log_error "Failed to make tree-sitter executable"
    return 1
  fi

  # Install Neovim Python support
  if ! python3.12 -m pip install neovim >/dev/null 2>&1; then
    log_error "Failed to install Neovim Python support"
    return 1
  fi

  # Create directories for LazyVim
  mkdir -p "$ACTUAL_HOME/.config"

  # Clone LazyVim starter
  if [ ! -d "$ACTUAL_HOME/.config/nvim" ]; then
    if ! su - "$ACTUAL_USER" -c "git clone https://github.com/LazyVim/starter ~/.config/nvim"; then
      log_error "Failed to clone LazyVim starter"
      return 1
    fi

    if ! su - "$ACTUAL_USER" -c "rm -rf ~/.config/nvim/.git"; then
      log_error "Failed to remove .git directory from LazyVim starter"
      # Not returning 1 here as this is not critical
    fi
  fi

  # Clean up
  rm -f /tmp/nvim-linux-x86_64.tar.gz
  return 0
}

#-----------------------------------------------------------------------------------------------------------------------------------------------
# Function to configure SSH with real-time priority
#-----------------------------------------------------------------------------------------------------------------------------------------------
configure_ssh_priority() {
  log_info "Configuring SSH with real-time priority..."
  # Configure SSH for real-time priority
  if ! mkdir -p /etc/systemd/system/ssh.service.d; then
    log_error "Failed to create SSH service override directory"
    return 1
  fi

  cat >/etc/systemd/system/ssh.service.d/override.conf <<'EOL'
[Service]
CPUSchedulingPolicy=rr
CPUSchedulingPriority=99
EOL

  # Reload systemd and restart SSH service
  if ! systemctl daemon-reload >/dev/null 2>&1; then
    log_error "Failed to reload systemd daemon"
    return 1
  fi

  if ! systemctl restart ssh >/dev/null 2>&1; then
    log_error "Failed to restart SSH service"
    return 1
  fi

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

  if ! command -v rsync >/dev/null 2>&1; then
    log_error "rsync command not found after installation"
    return 1
  fi

  return 0
}

#-----------------------------------------------------------------------------------------------------------------------------------------------
# Function to create DEV directory
#-----------------------------------------------------------------------------------------------------------------------------------------------
create_dev_dir() {
  log_info "Creating DEV directory..."
  if ! mkdir -p "$ACTUAL_HOME/DEV"; then
    log_error "Failed to create DEV directory"
    return 1
  fi

  if ! chown "$ACTUAL_USER":"$ACTUAL_USER" "$ACTUAL_HOME/DEV"; then
    log_error "Failed to set ownership for DEV directory"
    return 1
  fi

  return 0
}

#-----------------------------------------------------------------------------------------------------------------------------------------------
# Function to set additional ZSH optimizations
#-----------------------------------------------------------------------------------------------------------------------------------------------
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

#-----------------------------------------------------------------------------------------------------------------------------------------------
# Function to display the menu and allow selecting tasks
#-----------------------------------------------------------------------------------------------------------------------------------------------
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
  read -r -p "> " choices
}

#-----------------------------------------------------------------------------------------------------------------------------------------------
#-----------------------------------------------------------------------------------------------------------------------------------------------
#-----------------------------------------------------------------------------------------------------------------------------------------------
# Main function
#-----------------------------------------------------------------------------------------------------------------------------------------------
#-----------------------------------------------------------------------------------------------------------------------------------------------
#-----------------------------------------------------------------------------------------------------------------------------------------------
main() {
  # Load configuration
  load_config

  # Check if running as root
  check_root

  # Loop to show menu until user quits
  while true; do
    # Show menu and get user choice
    show_menu

    # Process user choices
    if [ "$choices" == "q" ] || [ "$choices" == "Q" ]; then
      echo "Exiting setup script. Goodbye!"
      exit 0
    elif [ "$choices" == "0" ]; then
      # Run all tasks
      update_system
      install_build_essentials
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
      configure_ssh
      install_rsync
      create_dev_directory
      apply_zsh_optimizations

      echo ""
      echo -e "${GREEN}All tasks completed successfully!${NC}"
      echo "You may need to log out and log back in for some changes to take effect."
      echo "Press Enter to return to the menu..."
      read -r
    else
      # Process individual choices
      for choice in $choices; do
        case "$choice" in
        1) update_system ;;
        2) install_build_essentials ;;
        3) install_zsh ;;
        4) install_git ;;
        5) install_utilities ;;
        6) install_search_tools ;;
        7) install_lua ;;
        8) install_luarocks ;;
        9) install_nvm_node ;;
        10) install_nerd_font ;;
        11) install_rust ;;
        12) install_docker ;;
        13) install_python_poetry ;;
        14) install_tmux ;;
        15) install_go ;;
        16) install_neovim ;;
        17) configure_ssh ;;
        18) install_rsync ;;
        19) create_dev_directory ;;
        20) apply_zsh_optimizations ;;
        21)
          echo "Running developer essentials setup (system, build tools, Go, Rust)..."
          update_system
          install_build_essentials
          install_go
          install_rust
          ;;
        *) echo "Invalid choice: $choice" ;;
        esac
      done

      echo ""
      echo -e "${GREEN}Selected tasks completed successfully!${NC}"
      echo "You may need to log out and log back in for some changes to take effect."
      echo "Press Enter to return to the menu..."
      read -r
    fi
  done
}

main
