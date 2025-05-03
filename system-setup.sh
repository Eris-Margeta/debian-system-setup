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

  # Step 1: Check existing installations
  log_info "Step 1/3: Checking existing build tool installations..."
  build_tools=(
    "build-essential"
    "make"
    "libssl-dev"
    "libghc-zlib-dev"
    "libcurl4-gnutls-dev"
    "libexpat1-dev"
    "gettext"
    "unzip"
    "gfortran"
    "libopenblas-dev"
    "cmake"
  )
  missing_tools=()

  # Check which packages are installed using dpkg
  for tool in "${build_tools[@]}"; do
    if dpkg -l | grep -q "ii  $tool "; then
      log_info "- ✓ $tool is already installed"
    else
      log_info "- ✗ $tool needs to be installed"
      missing_tools+=("$tool")
    fi
  done

  # Check for gcc separately since it's a command
  if command -v gcc >/dev/null 2>&1; then
    gcc_version=$(gcc --version | head -n 1)
    log_info "- ✓ gcc is already installed: $gcc_version"
  else
    log_info "- ✗ gcc is not available, will be installed with build-essential"
    # Make sure build-essential is in missing_tools if gcc is missing
    if ! [[ " ${missing_tools[*]} " =~ "build-essential" ]]; then
      missing_tools+=("build-essential")
    fi
  fi

  # Step 2: Install missing build tools
  if [ ${#missing_tools[@]} -eq 0 ]; then
    log_info "Step 2/3: ✓ All build tools are already installed"
  else
    log_info "Step 2/3: Installing missing build tools..."
    log_info "- Installing: ${missing_tools[*]}"

    if ! apt install -y "${missing_tools[@]}"; then
      log_error "Failed to install build tools: ${missing_tools[*]}"
      return 1
    fi
    log_info "✓ Successfully installed missing build tools"
  fi

  # Step 3: Verify key tool installations
  log_info "Step 3/3: Verifying key build tool installations..."
  verification_tools=("gcc" "make" "cmake")
  all_verified=true

  for tool in "${verification_tools[@]}"; do
    if command -v "$tool" >/dev/null 2>&1; then
      version=$("$tool" --version | head -n 1)
      log_info "- ✓ $tool: $version"
    else
      log_error "- ✗ $tool installation failed"
      all_verified=false
    fi
  done

  if $all_verified; then
    log_info "✅ Build essentials installation completed successfully"
    return 0
  else
    log_error "Build essentials installation verification failed"
    return 1
  fi
}

#-----------------------------------------------------------------------------------------------------------------------------------------------
# Function to install ZSH and set it as default shell
#-----------------------------------------------------------------------------------------------------------------------------------------------
install_zsh() {
  log_info "Installing ZSH and setting it as default shell..."

  # Step 1: Check existing ZSH installation
  log_info "Step 1/5: Checking existing ZSH installation..."
  if command -v zsh >/dev/null 2>&1; then
    zsh_version=$(zsh --version)
    log_info "- ✓ ZSH is already installed: $zsh_version"
    needs_install=false
  else
    log_info "- ✗ ZSH is not installed"
    needs_install=true
  fi

  # Check for zplug
  if dpkg -l | grep -q "ii  zplug "; then
    log_info "- ✓ zplug is already installed"
    needs_zplug=false
  else
    log_info "- ✗ zplug is not installed"
    needs_zplug=true
  fi

  # Step 2: Install ZSH and zplug if needed
  log_info "Step 2/5: Installing ZSH and zplug..."
  if [ "$needs_install" = false ] && [ "$needs_zplug" = false ]; then
    log_info "- ✓ Both ZSH and zplug are already installed"
  else
    install_packages=()

    if [ "$needs_install" = true ]; then
      install_packages+=("zsh")
    fi

    if [ "$needs_zplug" = true ]; then
      install_packages+=("zplug")
    fi

    if [ ${#install_packages[@]} -gt 0 ]; then
      log_info "- Installing: ${install_packages[*]}"
      if ! apt install -y "${install_packages[@]}"; then
        log_error "Failed to install: ${install_packages[*]}"
        return 1
      fi
      log_info "- ✓ Successfully installed: ${install_packages[*]}"
    fi
  fi

  # Verify installation
  if ! command -v zsh >/dev/null 2>&1; then
    log_error "ZSH installation verification failed"
    return 1
  else
    zsh_version=$(zsh --version)
    log_success "✓ ZSH installed successfully: $zsh_version"
  fi

  # Step 3: Create/update .zshrc configuration
  log_info "Step 3/5: Creating/updating .zshrc configuration..."

  # Backup existing .zshrc if it exists
  if [ -f "$ACTUAL_HOME/.zshrc" ]; then
    backup_file="$ACTUAL_HOME/.zshrc.backup.$(date +%Y%m%d%H%M%S)"
    log_info "- Backing up existing .zshrc to $backup_file"
    cp "$ACTUAL_HOME/.zshrc" "$backup_file"
  fi

  log_info "- Writing new .zshrc configuration..."
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
  log_info "- ✓ .zshrc configuration written successfully"

  # Step 4: Set correct file ownership
  log_info "Step 4/5: Setting correct file ownership..."
  chown "$ACTUAL_USER:$ACTUAL_USER" "$ACTUAL_HOME/.zshrc"
  log_info "- ✓ File ownership set to $ACTUAL_USER:$ACTUAL_USER"

  # Step 5: Set ZSH as default shell
  log_info "Step 5/5: Setting ZSH as the default shell..."
  current_shell=$(getent passwd "$ACTUAL_USER" | cut -d: -f7)
  zsh_path=$(command -v zsh)

  if [ "$current_shell" = "$zsh_path" ]; then
    log_info "- ✓ ZSH is already the default shell for $ACTUAL_USER"
  else
    log_info "- Changing default shell from $current_shell to $zsh_path"
    if ! chsh -s "$zsh_path" "$ACTUAL_USER"; then
      log_error "Failed to set ZSH as default shell"
      return 1
    fi
    log_info "- ✓ ZSH set as default shell for $ACTUAL_USER"
  fi

  log_success "✅ ZSH setup completed successfully"
  log_info "ZSH configuration includes: syntax highlighting, autosuggestions, history search, and completions"
  log_info "To fully apply changes, please log out and log back in, or run: exec zsh"

  return 0
}

#-----------------------------------------------------------------------------------------------------------------------------------------------
# Function to install Git and GitHub CLI
#-----------------------------------------------------------------------------------------------------------------------------------------------
install_git() {
  log_info "Installing Git and GitHub CLI..."

  # Step 1: Check existing Git installation
  log_info "Step 1/6: Checking Git installation..."
  if command -v git >/dev/null 2>&1; then
    current_git_version=$(git --version)
    log_info "- Git is already installed: $current_git_version"
    log_info "- Proceeding with Git update/reinstall to ensure latest version"
  else
    log_info "- Git is not installed, will install from repositories"
  fi

  # Step 2: Install/Reinstall Git
  log_info "Step 2/6: Installing Git..."
  if ! apt install -y git; then
    log_error "Failed to install Git"
    return 1
  fi

  # Verify Git installation
  git_version=$(git --version)
  log_success "✓ Git installed successfully: $git_version"

  # Step 3: Check existing GitHub CLI installation
  log_info "Step 3/6: Checking GitHub CLI installation..."
  if command -v gh >/dev/null 2>&1; then
    current_gh_version=$(gh --version | head -n 1)
    log_info "- GitHub CLI is already installed: $current_gh_version"
    log_info "- Will check for updates to ensure latest version"
  else
    log_info "- GitHub CLI is not installed, will set up repository and install"
  fi

  # Step 4: Setup GitHub CLI repository keys
  log_info "Step 4/6: Setting up GitHub CLI repository..."

  # Check if keyring file already exists
  if [ -f "/usr/share/keyrings/githubcli-archive-keyring.gpg" ]; then
    log_info "- GitHub CLI keyring already exists"
  else
    log_info "- Downloading GitHub CLI repository key..."
    if ! curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg; then
      log_error "Failed to download GitHub CLI keyring"
      return 1
    fi
    log_info "✓ GitHub CLI keyring installed successfully"
  fi

  # Check if repository is already configured
  if [ -f "/etc/apt/sources.list.d/github-cli.list" ]; then
    log_info "- GitHub CLI repository already configured"
  else
    log_info "- Adding GitHub CLI repository to APT sources..."
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | tee /etc/apt/sources.list.d/github-cli.list >/dev/null
    log_info "✓ GitHub CLI repository added successfully"
  fi

  # Step 5: Update package lists
  log_info "Step 5/6: Updating package lists..."
  if ! apt update; then
    log_error "Failed to update package lists"
    return 1
  fi
  log_info "✓ Package lists updated successfully"

  # Step 6: Install/Reinstall GitHub CLI
  log_info "Step 6/6: Installing GitHub CLI..."
  if ! apt install -y gh; then
    log_error "Failed to install GitHub CLI"
    return 1
  fi

  # Verify GitHub CLI installation
  gh_version=$(gh --version | head -n 1)
  log_success "✓ GitHub CLI installed successfully: $gh_version"

  # Display detailed version info
  log_info "GitHub CLI details:"
  gh --version

  log_success "✅ Git and GitHub CLI installation completed successfully"
  return 0
}

#-----------------------------------------------------------------------------------------------------------------------------------------------
# Function to install curl, wget, and other utilities
#-----------------------------------------------------------------------------------------------------------------------------------------------
install_utilities() {
  log_info "Installing utilities (curl, wget, htop, iotop, tree, lsd)..."

  # Step 1: Check what utilities are already installed
  log_info "Step 1/2: Checking existing utility installations..."
  utilities=("curl" "wget" "htop" "tree" "iotop" "lsd")
  missing_utils=()

  for util in "${utilities[@]}"; do
    if command -v "$util" >/dev/null 2>&1; then
      log_info "- ✓ $util is already installed: $($util --version 2>&1 | head -n 1)"
    else
      log_info "- ✗ $util is not installed"
      missing_utils+=("$util")
    fi
  done

  # Step 2: Install missing utilities
  log_info "Step 2/2: Installing missing utilities..."
  if [ ${#missing_utils[@]} -eq 0 ]; then
    log_info "✓ All utilities are already installed"
  else
    log_info "- Installing: ${missing_utils[*]}"
    if ! apt install -y "${missing_utils[@]}"; then
      log_error "Failed to install utilities: ${missing_utils[*]}"
      return 1
    fi
    log_info "✓ Successfully installed missing utilities"
  fi

  # Verify all installations
  log_info "Verifying utility installations:"
  for util in "${utilities[@]}"; do
    if command -v "$util" >/dev/null 2>&1; then
      version=$($util --version 2>&1 | head -n 1)
      log_info "- ✓ $util: $version"
    else
      log_error "- ✗ $util installation failed"
    fi
  done

  log_info "✅ Utility installation completed successfully"
  return 0
}

#-----------------------------------------------------------------------------------------------------------------------------------------------
# Function to install fzf and ripgrep
#-----------------------------------------------------------------------------------------------------------------------------------------------
install_search_tools() {
  log_info "Installing search tools (fzf, ripgrep, fd)..."

  # Step 1: Check what search tools are already installed
  log_info "Step 1/3: Checking existing search tool installations..."
  search_tools=("fzf" "ripgrep" "fd-find")
  search_commands=("fzf" "rg" "fdfind")
  missing_tools=()

  for i in "${!search_tools[@]}"; do
    tool="${search_tools[$i]}"
    cmd="${search_commands[$i]}"

    if command -v "$cmd" >/dev/null 2>&1; then
      # Get version information when possible
      if [ "$cmd" = "fzf" ]; then
        version=$(fzf --version 2>&1)
      elif [ "$cmd" = "rg" ]; then
        version=$(rg --version 2>&1 | head -n 1)
      elif [ "$cmd" = "fdfind" ]; then
        version=$(fdfind --version 2>&1)
      else
        version="installed"
      fi
      log_info "- ✓ $tool is already installed: $version"
    else
      log_info "- ✗ $tool is not installed"
      missing_tools+=("$tool")
    fi
  done

  # Step 2: Install missing search tools
  log_info "Step 2/3: Installing missing search tools..."
  if [ ${#missing_tools[@]} -eq 0 ]; then
    log_info "✓ All search tools are already installed"
  else
    log_info "- Installing: ${missing_tools[*]}"
    if ! apt install -y "${missing_tools[@]}"; then
      log_error "Failed to install search tools: ${missing_tools[*]}"
      return 1
    fi
    log_info "✓ Successfully installed missing search tools"
  fi

  # Step 3: Set up fd alias if needed
  log_info "Step 3/3: Setting up fd alias..."
  if grep -q "alias fd=fdfind" "$ACTUAL_HOME/.zshrc"; then
    log_info "- ✓ fd alias already exists in .zshrc"
  else
    log_info "- Adding fd alias to .zshrc"
    echo "alias fd=fdfind" >>"$ACTUAL_HOME/.zshrc"
    log_info "✓ fd alias added successfully"
  fi

  # Verify all installations
  log_info "Verifying search tool installations:"
  for i in "${!search_tools[@]}"; do
    cmd="${search_commands[$i]}"
    if command -v "$cmd" >/dev/null 2>&1; then
      log_info "- ✓ ${search_tools[$i]} is installed"
    else
      log_error "- ✗ ${search_tools[$i]} installation failed"
    fi
  done

  log_info "✅ Search tools installation completed successfully"
  return 0
}

#-----------------------------------------------------------------------------------------------------------------------------------------------
# Function to install Lua
#-----------------------------------------------------------------------------------------------------------------------------------------------
install_lua() {
  log_info "Setting up Lua 5.1 and LuaJIT..."
  # Step 1: Check if Lua and LuaJIT are already installed
  log_info "Step 1/5: Checking existing Lua installations..."
  local lua_installed=false
  local luajit_installed=false
  if dpkg -l | grep -q "lua5.1"; then
    lua_installed=true
    log_info "- Lua 5.1 is already installed, will reinstall"
  else
    log_info "- Lua 5.1 is not installed, will install new"
  fi
  if dpkg -l | grep -q "luajit"; then
    luajit_installed=true
    log_info "- LuaJIT is already installed, will reinstall"
  else
    log_info "- LuaJIT is not installed, will install new"
  fi

  # Step 2: Clean up custom installations if they exist
  log_info "Step 2/5: Cleaning up any existing custom Lua installations..."
  if [ -f "/usr/local/bin/lua" ]; then
    log_info "- Removing custom Lua installation from /usr/local/bin/lua"
    rm -f /usr/local/bin/lua*
  else
    log_info "- No custom Lua binary found in /usr/local/bin"
  fi
  if [ -f "/usr/local/bin/luajit" ]; then
    log_info "- Removing custom LuaJIT installation from /usr/local/bin/luajit"
    rm -f /usr/local/bin/luajit*
  else
    log_info "- No custom LuaJIT binary found in /usr/local/bin"
  fi
  if [ -d "/usr/local/include/lua" ]; then
    log_info "- Removing custom Lua headers from /usr/local/include/lua"
    rm -rf /usr/local/include/lua*
  else
    log_info "- No custom Lua headers found in /usr/local/include"
  fi
  if [ -d "/usr/local/lib/lua" ]; then
    log_info "- Removing custom Lua libraries from /usr/local/lib/lua"
    rm -rf /usr/local/lib/lua*
  else
    log_info "- No custom Lua libraries found in /usr/local/lib"
  fi

  # Step 3: Use appropriate package management based on distribution
  log_info "Step 3/5: Preparing for package installation..."
  # Detect distribution using available methods

  # Initialize variables with defaults
  DISTRO="unknown"
  VERSION_ID="unknown"

  # Try lsb_release command first (most reliable)
  if command -v lsb_release >/dev/null 2>&1; then
    DISTRO=$(lsb_release -is | tr '[:upper:]' '[:lower:]')
    VERSION_ID=$(lsb_release -rs)
    log_info "- Detected distribution using lsb_release: ${DISTRO} ${VERSION_ID}"
  # If we can't find those, fall back to checking for common files
  elif grep -q "ID=" /etc/*-release 2>/dev/null; then
    # Generic approach using grep to find distribution ID in any release file
    DISTRO=$(grep -m1 "^ID=" /etc/*-release 2>/dev/null | cut -d= -f2 | tr -d '"')
    VERSION_ID=$(grep -m1 "^VERSION_ID=" /etc/*-release 2>/dev/null | cut -d= -f2 | tr -d '"')
    log_info "- Detected distribution from release files: ${DISTRO} ${VERSION_ID}"
  else
    # Last resort - try to determine based on available commands
    if command -v apt >/dev/null 2>&1; then
      DISTRO="debian-based"
      log_info "- Detected a Debian-based distribution (found apt)"
    elif command -v yum >/dev/null 2>&1; then
      DISTRO="redhat-based"
      log_info "- Detected a RedHat-based distribution (found yum)"
    else
      log_warning "Could not identify distribution, proceeding with generic installation"
    fi
  fi

  # Convert to lowercase if not already
  DISTRO=$(echo "$DISTRO" | tr '[:upper:]' '[:lower:]')

  log_info "- Using distribution: ${DISTRO} ${VERSION_ID}"

  # Step 4: Install or reinstall Lua and LuaJIT as needed
  log_info "Step 4/5: Installing Lua packages..."
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
  log_info "- Running: $install_cmd"
  if ! eval "$install_cmd"; then
    log_error "Failed to install Lua packages"
    return 1
  fi
  log_info "- Lua packages installed successfully"

  # Step 5: Verify installation
  log_info "Step 5/5: Verifying installation..."
  # Show installed versions
  lua_version=$(lua5.1 -v 2>/dev/null || echo "Not found")
  luajit_version=$(luajit -v 2>/dev/null || echo "Not found")
  log_info "Installed Lua version: $lua_version"
  log_info "Installed LuaJIT version: $luajit_version"

  if [[ "$lua_version" == "Not found" ]] || [[ "$luajit_version" == "Not found" ]]; then
    log_warning "One or more Lua components not properly installed"
    # Create symbolic links if needed
    if [[ "$lua_version" == "Not found" ]] && [ -f /usr/bin/lua5.1 ]; then
      ln -sf /usr/bin/lua5.1 /usr/local/bin/lua
      log_info "Created symbolic link for Lua 5.1"
      lua_version=$(lua -v 2>/dev/null || echo "Not found")
      log_info "Lua version after linking: $lua_version"
    fi
  fi

  log_info "✅ Lua installation completed successfully!"
  return 0
}
#-----------------------------------------------------------------------------------------------------------------------------------------------
# Function to install LuaRocks
#-----------------------------------------------------------------------------------------------------------------------------------------------
install_luarocks() {
  log_info "Installing LuaRocks 3.11.1..."

  # Step 1: Try different Lua development packages
  log_info "Step 1/8: Installing Lua development packages..."

  # Try different Lua versions and package names
  LUA_DEV_PACKAGES=("lua5.1-dev" "lua-5.1-dev" "liblua5.1-dev" "lua5.2-dev" "liblua5.2-dev" "lua-dev")
  LUA_INSTALLED=false

  for pkg in "${LUA_DEV_PACKAGES[@]}"; do
    log_info "Trying to install $pkg..."
    if apt-cache search --names-only "^$pkg$" | grep -q . && apt install -y "$pkg"; then
      log_info "✓ Successfully installed $pkg"
      LUA_INSTALLED=true
      LUA_PKG="$pkg"
      break
    fi
  done

  if ! $LUA_INSTALLED; then
    log_info "Could not find pre-packaged Lua dev. Installing Lua from source..."
    # Install build dependencies
    apt install -y build-essential libreadline-dev

    # Create and navigate to a temp directory for Lua source
    LUA_TEMP_DIR="$HOME/lua_install_tmp"
    mkdir -p "$LUA_TEMP_DIR"
    cd "$LUA_TEMP_DIR" || {
      log_error "Failed to create/navigate to Lua temporary directory"
      return 1
    }

    # Download and install Lua 5.1 from source
    wget --show-progress http://www.lua.org/ftp/lua-5.1.5.tar.gz
    tar zxf lua-5.1.5.tar.gz
    cd lua-5.1.5 || return 1
    make linux
    make install

    # Clean up
    cd "$HOME" || true
    rm -rf "$LUA_TEMP_DIR"

    # Set include path for later use with LuaRocks
    LUA_INCLUDE_PATH="/usr/local/include"
  else
    # Find the Lua include directory based on the installed package
    if [[ "$LUA_PKG" == *"5.1"* ]]; then
      LUA_INCLUDE_PATH="/usr/include/lua5.1"
    elif [[ "$LUA_PKG" == *"5.2"* ]]; then
      LUA_INCLUDE_PATH="/usr/include/lua5.2"
    else
      # Try to find the include directory
      LUA_INCLUDE_PATH=$(find /usr/include -name "lua.h" -exec dirname {} \; | head -n 1)
      if [ -z "$LUA_INCLUDE_PATH" ]; then
        LUA_INCLUDE_PATH="/usr/include/lua"
      fi
    fi
  fi

  log_info "✓ Lua development environment prepared successfully"

  # Step 2: Verify the include directory exists
  log_info "Step 2/8: Verifying Lua include directory..."
  if [ ! -d "$LUA_INCLUDE_PATH" ]; then
    log_error "Lua include directory is missing at $LUA_INCLUDE_PATH"
    log_info "Searching for lua.h..."
    LUA_INCLUDE_PATH=$(find /usr -name "lua.h" -exec dirname {} \; | head -n 1)

    if [ -z "$LUA_INCLUDE_PATH" ]; then
      log_error "Could not find lua.h anywhere in the system"
      return 1
    else
      log_info "Found lua.h at $LUA_INCLUDE_PATH"
    fi
  fi
  log_info "✓ Lua include directory verified at $LUA_INCLUDE_PATH"

  # Step 3: Create a temporary directory with a specific name to avoid conflicts
  log_info "Step 3/8: Creating temporary directory for installation..."
  TEMP_DIR="$HOME/luarocks_install_tmp"
  mkdir -p "$TEMP_DIR"
  # Navigate to the temp directory and verify we're there
  cd "$TEMP_DIR" || {
    log_error "Failed to create/navigate to temporary directory"
    return 1
  }
  log_info "✓ Created temporary directory at $TEMP_DIR"

  # Step 4: Download LuaRocks with error checking
  log_info "Step 4/8: Downloading LuaRocks 3.11.1..."
  if ! wget --show-progress https://luarocks.org/releases/luarocks-3.11.1.tar.gz; then
    log_error "Failed to download LuaRocks"
    cd "$HOME" && rm -rf "$TEMP_DIR"
    return 1
  fi
  log_info "✓ Downloaded LuaRocks 3.11.1 successfully"

  # Step 5: Extract with error checking
  log_info "Step 5/8: Extracting LuaRocks..."
  if ! tar zxvf luarocks-3.11.1.tar.gz; then
    log_error "Failed to extract LuaRocks"
    cd "$HOME" && rm -rf "$TEMP_DIR"
    return 1
  fi
  log_info "✓ Extracted LuaRocks archive successfully"

  # Navigate to the extracted directory
  if ! cd "luarocks-3.11.1"; then
    log_error "Failed to navigate to LuaRocks directory - extraction may have failed"
    cd "$HOME" && rm -rf "$TEMP_DIR"
    return 1
  fi

  # Step 6: Configure and install build dependencies
  log_info "Step 6/8: Installing build dependencies..."
  if ! apt install -y build-essential libreadline-dev; then
    log_error "Failed to install build dependencies"
    cd "$HOME" && rm -rf "$TEMP_DIR"
    return 1
  fi

  log_info "Configuring LuaRocks..."
  # Use detected Lua include path
  if ! ./configure --with-lua=/usr --with-lua-include="$LUA_INCLUDE_PATH"; then
    log_info "First configure attempt failed, trying alternative configuration..."
    # If first configure fails, try without specifying include path
    if ! ./configure; then
      log_error "Failed to configure LuaRocks"
      cd "$HOME" && rm -rf "$TEMP_DIR"
      return 1
    fi
  fi
  log_info "✓ LuaRocks configured successfully"

  # Step 7: Build and install
  log_info "Step 7/8: Building LuaRocks (this may take a minute)..."
  if ! make; then
    log_error "Failed to build LuaRocks"
    cd "$HOME" && rm -rf "$TEMP_DIR"
    return 1
  fi
  log_info "✓ LuaRocks built successfully"

  log_info "Installing LuaRocks..."
  if ! make install; then
    log_error "Failed to install LuaRocks"
    cd "$HOME" && rm -rf "$TEMP_DIR"
    return 1
  fi
  log_info "✓ LuaRocks installed to system path"

  # Step 8: Verify and clean up
  log_info "Step 8/8: Verifying installation and cleaning up..."
  # Check if LuaRocks is installed correctly
  if ! command -v luarocks >/dev/null 2>&1; then
    log_error "LuaRocks installation completed but the 'luarocks' command is not available in PATH"
    # Try to add it to path if it's in a standard location
    if [ -f "/usr/local/bin/luarocks" ]; then
      export PATH="/usr/local/bin:$PATH"
      log_info "Added /usr/local/bin to PATH"
    fi
  else
    log_info "✓ LuaRocks command available in PATH"
  fi

  # Clean up
  log_info "Cleaning up temporary files..."
  cd "$HOME" || true
  rm -rf "$TEMP_DIR"
  log_info "✓ Temporary files removed"

  # Final verification with version display
  if command -v luarocks >/dev/null 2>&1; then
    luarocks_version=$(luarocks --version)
    log_info "✅ LuaRocks installation successful!"
    log_info "LuaRocks version: $luarocks_version"
    return 0
  else
    log_error "LuaRocks installation failed"
    return 1
  fi
}

#-----------------------------------------------------------------------------------------------------------------------------------------------
# Function to install Node.js
#-----------------------------------------------------------------------------------------------------------------------------------------------
install_nvm_node() {
  log_info "Setting up Node.js environment..."

  # Step 1: Check and remove existing NVM installation
  log_info "Step 1/7: Checking for existing NVM installation..."
  if [ -d "$ACTUAL_HOME/.nvm" ]; then
    log_info "- Existing NVM installation found"
    log_info "- Uninstalling existing Node.js versions..."

    su - "$ACTUAL_USER" -c "
      # Uninstall any existing node versions
      if command -v nvm &>/dev/null; then
        echo '  > Activating default Node.js version'
        nvm use default
        echo '  > Deactivating NVM'
        nvm deactivate
        echo '  > Uninstalling LTS version'
        nvm uninstall --lts
        echo '  > Uninstalling default version'
        nvm uninstall default
        echo '  > Uninstalling all remaining versions'
        nvm uninstall node
      fi
    "

    log_info "- Removing NVM directory..."
    rm -rf "$ACTUAL_HOME/.nvm"

    log_info "- Cleaning NVM entries from shell configuration files..."
    for config_file in "$ACTUAL_HOME/.bashrc" "$ACTUAL_HOME/.zshrc" "$ACTUAL_HOME/.profile"; do
      if [ -f "$config_file" ]; then
        log_info "  > Cleaning $config_file"
        sed -i '/NVM_DIR/d' "$config_file"
        sed -i '/nvm.sh/d' "$config_file"
        sed -i '/bash_completion/d' "$config_file"
      fi
    done
    log_info "✓ Previous NVM installation completely removed"
  else
    log_info "- No existing NVM installation found"
  fi

  # Step 2: Clean package manager caches
  log_info "Step 2/7: Cleaning package manager caches..."
  su - "$ACTUAL_USER" -c "
    if command -v npm &>/dev/null; then
      echo '  > Cleaning npm cache'
      npm cache clean --force
    fi
    
    if command -v pnpm &>/dev/null; then
      echo '  > Pruning pnpm store'
      pnpm store prune
    fi
  "
  log_info "✓ Package manager caches cleaned"

  # Step 3: Remove system Node.js packages
  log_info "Step 3/7: Removing system Node.js packages if they exist..."
  if command -v apt &>/dev/null; then
    apt purge -y nodejs npm
    apt autoremove -y
    log_info "✓ System Node.js packages removed"
  else
    log_info "- APT not found, skipping system package removal"
  fi

  # Step 4: Install NVM
  log_info "Step 4/7: Installing NVM v0.39.7..."
  log_info "- Downloading and running NVM install script..."
  su - "$ACTUAL_USER" -c "curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash"

  log_info "- Verifying NVM installation..."
  if [ -d "$ACTUAL_HOME/.nvm" ]; then
    log_info "✓ NVM installed successfully"
  else
    log_error "! NVM installation failed - directory not found"
    return 1
  fi

  # Step 5: Update shell configuration
  log_info "Step 5/7: Updating shell configuration for NVM..."
  if ! grep -q "export NVM_DIR" "$ACTUAL_HOME/.zshrc"; then
    log_info "- Adding NVM configuration to .zshrc"
    cat >>"$ACTUAL_HOME/.zshrc" <<'EOL'
# NVM Setup
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion
EOL
    log_info "✓ NVM configuration added to .zshrc"
  else
    log_info "- NVM configuration already exists in .zshrc"
  fi

  # Step 6: Install Node.js
  log_info "Step 6/7: Installing Node.js 20.10.0 (this may take a minute)..."
  if ! su - "$ACTUAL_USER" -c "
    export NVM_DIR=\"\$HOME/.nvm\"
    [ -s \"\$NVM_DIR/nvm.sh\" ] && . \"\$NVM_DIR/nvm.sh\"
    echo '  > Installing Node.js 20.10.0'
    nvm install 20.10.0
    echo '  > Setting Node.js 20.10.0 as active version'
    nvm use 20.10.0
    echo '  > Setting Node.js 20.10.0 as default version'
    nvm alias default 20.10.0
    echo '  > Node.js version:' 
    node -v
    echo '  > NPM version:'
    npm -v
  "; then
    log_error "Failed to install Node.js 20.10.0"
    return 1
  fi
  log_info "✓ Node.js 20.10.0 installed and set as default"

  # Step 7: Install global packages
  log_info "Step 7/7: Installing global packages..."

  log_info "- Installing pnpm globally..."
  su - "$ACTUAL_USER" -c "
    export NVM_DIR=\"\$HOME/.nvm\"
    [ -s \"\$NVM_DIR/nvm.sh\" ] && . \"\$NVM_DIR/nvm.sh\"
    npm i -g pnpm
    echo '  > PNPM version:'
    pnpm --version
  "
  log_info "✓ PNPM installed globally"

  log_info "- Installing neovim support..."
  su - "$ACTUAL_USER" -c "
    export NVM_DIR=\"\$HOME/.nvm\"
    [ -s \"\$NVM_DIR/nvm.sh\" ] && . \"\$NVM_DIR/nvm.sh\"
    npm install -g neovim
  "
  log_info "✓ Neovim support installed"

  # Show final versions
  log_info "Installed versions:"
  su - "$ACTUAL_USER" -c "
    export NVM_DIR=\"\$HOME/.nvm\"
    [ -s \"\$NVM_DIR/nvm.sh\" ] && . \"\$NVM_DIR/nvm.sh\"
    echo ' - Node.js: $(node -v)'
    echo ' - NPM: $(npm -v)'
    echo ' - PNPM: $(pnpm --version)'
  "

  log_info "✅ Node.js environment setup completed successfully!"
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
  log_info "Installing Docker"

  # Step 1: Check if Docker is already installed
  log_info "Step 1/8: Checking for existing Docker installation..."
  if command -v docker &>/dev/null; then
    log_info "✓ Docker is already installed. Skipping installation."
    docker --version
    return 0
  fi
  log_info "- No existing Docker installation found, proceeding with install"

  # Step 2: Install dependencies only if they don't exist
  log_info "Step 2/8: Checking and installing Docker prerequisites..."
  log_info "- Updating package lists..."
  apt-get update

  log_info "- Checking for required packages..."
  dependencies=("ca-certificates" "curl" "gnupg")
  missing_deps=()

  for dep in "${dependencies[@]}"; do
    if ! dpkg -l | grep -q "ii  $dep "; then
      missing_deps+=("$dep")
    else
      log_info "  ✓ $dep is already installed"
    fi
  done

  if [ ${#missing_deps[@]} -gt 0 ]; then
    log_info "- Installing missing packages: ${missing_deps[*]}"
    apt-get install -y "${missing_deps[@]}"
    log_info "✓ Missing prerequisites installed"
  else
    log_info "✓ All prerequisites are already installed"
  fi

  # Step 3: Detect distribution for repository configuration
  log_info "Step 3/8: Detecting system distribution..."

  # Initialize distribution variables
  DISTRO="unknown"
  CODENAME="unknown"

  # Try different methods to detect distribution
  if command -v lsb_release &>/dev/null; then
    DISTRO=$(lsb_release -is | tr '[:upper:]' '[:lower:]')
    CODENAME=$(lsb_release -cs)
    log_info "- Detected distribution using lsb_release: ${DISTRO} ${CODENAME}"
  elif grep -q "^ID=" /etc/os-release 2>/dev/null; then
    DISTRO=$(grep -m1 "^ID=" /etc/os-release | cut -d= -f2 | tr -d '"')
    if grep -q "^VERSION_CODENAME=" /etc/os-release; then
      CODENAME=$(grep -m1 "^VERSION_CODENAME=" /etc/os-release | cut -d= -f2 | tr -d '"')
    elif grep -q "^UBUNTU_CODENAME=" /etc/os-release; then
      CODENAME=$(grep -m1 "^UBUNTU_CODENAME=" /etc/os-release | cut -d= -f2 | tr -d '"')
    fi
    log_info "- Detected distribution from os-release: ${DISTRO} ${CODENAME}"
  elif [ -f /etc/debian_version ]; then
    DISTRO="debian"
    # Fix useless cat warning by reading the file directly with cut
    CODENAME=$(cut -d/ -f1 /etc/debian_version)
    log_info "- Detected Debian distribution: ${CODENAME}"
  fi

  log_info "- Using distribution: ${DISTRO} with codename: ${CODENAME}"

  # Step 4: Set up Docker's GPG key
  log_info "Step 4/8: Setting up Docker repository..."
  log_info "- Checking if Docker's GPG key directory exists..."
  if [ ! -d "/etc/apt/keyrings" ]; then
    log_info "- Creating directory for Docker's GPG key..."
    mkdir -p "/etc/apt/keyrings"
  fi

  log_info "- Downloading and installing Docker's GPG key..."
  if [ ! -f "/etc/apt/keyrings/docker.gpg" ]; then
    # Download appropriate key based on distribution
    case "${DISTRO}" in
    ubuntu | debian)
      curl -fsSL "https://download.docker.com/linux/${DISTRO}/gpg" | gpg --dearmor -o "/etc/apt/keyrings/docker.gpg"
      ;;
    *)
      # Default to Ubuntu repository if distribution is unknown
      log_warning "Unknown distribution '${DISTRO}', defaulting to Ubuntu repository"
      curl -fsSL "https://download.docker.com/linux/ubuntu/gpg" | gpg --dearmor -o "/etc/apt/keyrings/docker.gpg"
      ;;
    esac
    chmod a+r "/etc/apt/keyrings/docker.gpg"
    log_info "✓ Docker GPG key configured successfully"
  else
    log_info "  ✓ Docker GPG key already exists"
  fi

  # Step 5: Add Docker repository if not already added
  log_info "Step 5/8: Configuring Docker repository in APT sources..."
  if [ ! -f "/etc/apt/sources.list.d/docker.list" ]; then
    log_info "- Adding Docker repository to APT sources..."
    # Configure the appropriate repository based on the distribution
    case "${DISTRO}" in
    ubuntu | debian)
      echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/${DISTRO} ${CODENAME} stable" >"/etc/apt/sources.list.d/docker.list"
      ;;
    *)
      # Default to Ubuntu repository using a stable version
      log_warning "Unknown distribution '${DISTRO}', using a stable default"
      echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu focal stable" >"/etc/apt/sources.list.d/docker.list"
      ;;
    esac
    log_info "✓ Docker repository added"
  else
    log_info "✓ Docker repository already configured"
  fi

  # Step 6: Update package lists with new repository
  log_info "Step 6/8: Updating package lists with Docker repository..."
  if ! apt-get update; then
    log_error "Failed to update package lists. Docker installation aborted."
    # Try removing the problematic repository file
    if [ -f "/etc/apt/sources.list.d/docker.list" ]; then
      log_warning "Removing potentially problematic Docker repository file..."
      rm -f "/etc/apt/sources.list.d/docker.list"
      apt-get update
    fi
    return 1
  fi
  log_info "✓ Package lists updated successfully"

  # Step 7: Install Docker packages
  log_info "Step 7/8: Installing Docker packages..."
  log_info "- Installing Docker packages (this may take a few minutes)..."
  if ! apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin; then
    log_error "Failed to install Docker packages. Installation aborted."
    return 1
  fi
  log_info "✓ Docker packages installed successfully"

  # Step 8: Verify installation
  log_info "Step 8/8: Verifying Docker installation..."
  if command -v docker &>/dev/null; then
    docker_version=$(docker --version)
    log_info "✓ Docker installed successfully: $docker_version"

    # Check if docker compose is installed
    if docker compose version &>/dev/null; then
      compose_version=$(docker compose version --short)
      log_info "✓ Docker Compose plugin installed: $compose_version"
    else
      log_warning "Docker Compose plugin not detected. You may need to install it separately."
    fi
  else
    log_warning "Docker installation may have failed. 'docker' command not found."
  fi

  log_info "✅ Docker installation completed!"
  log_info "NOTE: You may need to log out and back in for group changes to take effect."
  log_info "After logging back in, you can test Docker with: docker run hello-world"

  return 0
}

#-----------------------------------------------------------------------------------------------------------------------------------------------
# Function to install Poetry for Python
#-----------------------------------------------------------------------------------------------------------------------------------------------
install_python_poetry() {
  log_info "Installing Poetry and Python 3.12.3..."

  # Install Python dependencies
  log_info "Step 1/10: Installing Python build dependencies..."
  apt install -y build-essential libssl-dev zlib1g-dev libncurses5-dev libnss3-dev libreadline-dev libffi-dev libsqlite3-dev wget libbz2-dev libgdbm-dev libdb-dev liblzma-dev tk-dev uuid-dev

  # Download and extract Python
  cd /tmp || return 1
  log_info "Step 2/10: Downloading Python 3.12.3..."
  if ! wget -q --show-progress https://www.python.org/ftp/python/3.12.3/Python-3.12.3.tgz; then
    log_error "Failed to download Python 3.12.3"
    return 1
  fi

  log_info "Step 3/10: Extracting Python source code..."
  if ! tar -xf Python-3.12.3.tgz; then
    log_error "Failed to extract Python 3.12.3"
    return 1
  fi

  cd Python-3.12.3 || return 1

  # Configure and install
  log_info "Step 4/10: Configuring Python build (this may take a few minutes)..."
  if ! ./configure --enable-optimizations; then
    log_error "Failed to configure Python 3.12.3"
    return 1
  fi

  log_info "Step 5/10: Compiling Python (this will take several minutes)..."
  if ! make -j"$(nproc)"; then
    log_error "Failed to make Python 3.12.3"
    return 1
  fi

  log_info "Step 6/10: Installing Python 3.12.3..."
  if ! make altinstall || ! command -v python3.12 >/dev/null 2>&1; then
    log_error "Failed to install Python 3.12.3"
    return 1
  fi

  # Removed the alias section

  # Install pip for system Python
  log_info "Step 7/9: Installing pip for system Python..."
  if ! apt install -y python3-pip; then
    log_error "Failed to install system Python pip"
    return 1
  fi

  # Install pip for Python 3.12 if not already installed with Python
  log_info "Step 8/9: Ensuring pip is installed for Python 3.12..."
  if ! python3.12 -m ensurepip; then
    log_error "Failed to ensure pip for Python 3.12"
    return 1
  fi

  # Install virtualenv
  log_info "Installing virtualenv for Python 3.12..."
  if ! python3.12 -m pip install virtualenv; then
    log_error "Failed to install virtualenv"
    return 1
  fi

  # Install neovim support globally
  log_info "Installing pynvim for neovim support..."
  if ! python3.12 -m pip install pynvim; then
    log_error "Failed to install pynvim (neovim support)"
    return 1
  fi

  # Install Poetry
  log_info "Step 9/9: Installing Poetry (this may take a few minutes)..."
  if ! su - "$ACTUAL_USER" -c "curl -sSL https://install.python-poetry.org | python3.12 -"; then
    log_error "Failed to install Poetry"
    return 1
  fi

  # Add Poetry to PATH in .zshrc if not already there
  log_info "Setting up Poetry path..."
  if ! grep -q "\$HOME/.local/bin" "$ACTUAL_HOME/.zshrc"; then
    cat >>"$ACTUAL_HOME/.zshrc" <<'EOL'
# Add Poetry to PATH
export PATH=$HOME/.local/bin:$PATH
EOL
    log_info "Poetry path added to .zshrc"
  else
    log_info "Poetry path already exists in .zshrc"
  fi

  # Clean up
  log_info "Cleaning up temporary files..."
  cd /tmp || return 1
  rm -rf Python-3.12.3*

  log_info "✅ Python 3.12.3 and Poetry installation completed successfully!"
  log_info "To use Python 3.12, run: python3.12"
  log_info "To use pip for Python 3.12, run: python3.12 -m pip"
  return 0
}
#-----------------------------------------------------------------------------------------------------------------------------------------------
# Function to install tmux
#-----------------------------------------------------------------------------------------------------------------------------------------------
install_tmux() {
  log_info "Installing tmux 3.5a from source..."

  # Install dependencies
  log_info "Step 1/7: Installing tmux dependencies..."
  if ! apt install -y git automake build-essential pkg-config libevent-dev libncurses5-dev bison; then
    log_error "Failed to install tmux dependencies"
    return 1
  fi

  # Clone and build tmux
  cd /tmp || return 1
  log_info "Step 2/7: Cloning tmux repository..."
  if ! git clone https://github.com/tmux/tmux.git; then
    log_error "Failed to clone tmux repository"
    return 1
  fi

  cd tmux || return 1
  log_info "Step 3/7: Checking out tmux version 3.5a..."
  if ! git checkout 3.5a; then
    log_error "Failed to checkout tmux version 3.5a"
    return 1
  fi

  log_info "Step 4/7: Running autogen.sh..."
  if ! sh autogen.sh; then
    log_error "Failed to run autogen.sh for tmux"
    return 1
  fi

  log_info "Step 5/7: Configuring tmux build..."
  if ! ./configure; then
    log_error "Failed to configure tmux"
    return 1
  fi

  log_info "Step 6/7: Compiling tmux (this may take a few minutes)..."
  if ! make; then
    log_error "Failed to make tmux"
    return 1
  fi

  log_info "Step 7/7: Installing tmux..."
  if ! make install || ! command -v tmux >/dev/null 2>&1; then
    log_error "Failed to install tmux"
    return 1
  fi

  # Create basic tmux config
  log_info "Creating tmux configuration file..."
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
    log_info "Created tmux configuration file at $ACTUAL_HOME/.tmux.conf"
  else
    log_info "Tmux configuration file already exists at $ACTUAL_HOME/.tmux.conf"
  fi

  # Clean up
  log_info "Cleaning up temporary files..."
  cd /tmp || return 1
  rm -rf tmux

  log_info "✅ Tmux 3.5a installation completed successfully!"
  return 0
}

#-----------------------------------------------------------------------------------------------------------------------------------------------
# Function to install Go
#-----------------------------------------------------------------------------------------------------------------------------------------------
install_go() {
  log_info "Installing Go..."

  # Download the latest Go binary
  log_info "Downloading Go package..."
  cd /tmp || return 1
  if ! wget -q https://dl.google.com/go/go1.21.7.linux-amd64.tar.gz; then
    log_error "Failed to download Go"
    return 1
  fi

  # Remove any previous Go installation
  log_info "Removing previous Go installation if exists..."
  rm -rf /usr/local/go

  # Extract Go archive
  log_info "Extracting Go archive..."
  if ! tar -xzf go1.21.7.linux-amd64.tar.gz -C /usr/local; then
    log_error "Failed to install Go"
    return 1
  fi

  # Add Go to PATH in .zshrc if not already there
  log_info "Configuring Go environment..."
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
  log_info "Creating Go workspace..."
  mkdir -p "$ACTUAL_HOME/go/"{bin,pkg,src}
  chown -R "$ACTUAL_USER":"$ACTUAL_USER" "$ACTUAL_HOME/go"

  # Install lemonade for clipboard support
  log_info "Installing Go extras for tmux and neovim (lemonade)..."
  export PATH=$PATH:/usr/local/go/bin
  if ! go install github.com/lemonade-command/lemonade@latest; then
    log_error "Failed to install lemonade"
    return 1
  fi

  if [ -f "$ACTUAL_HOME/go/bin/lemonade" ]; then
    log_info "Moving lemonade to system path..."
    mv "$ACTUAL_HOME/go/bin/lemonade" /usr/local/bin/
  else
    log_error "Lemonade binary not found after installation"
    return 1
  fi

  # Clean up
  log_info "Cleaning up temporary files..."
  rm -f /tmp/go1.21.7.linux-amd64.tar.gz

  log_info "Go installation completed successfully!"
  return 0
}

#-----------------------------------------------------------------------------------------------------------------------------------------------
# Function to install Neovim
#-----------------------------------------------------------------------------------------------------------------------------------------------
install_neovim() {
  log_info "Installing Neovim v0.11.1..."

  # Make sure tar is installed
  log_info "Step 1/10: Installing required packages..."
  if ! apt install -y tar gzip; then
    log_error "Failed to install tar and gzip"
    return 1
  fi

  # Create Neovim directory in user's home
  log_info "Step 2/10: Creating Neovim directory..."
  NVIM_DIR="$ACTUAL_HOME/nvim-linux-x86_64"
  mkdir -p "$NVIM_DIR"

  # Download Neovim 0.11.1
  cd /tmp || return 1
  log_info "Step 3/10: Downloading Neovim v0.11.1..."
  if ! wget --show-progress https://github.com/neovim/neovim/releases/download/v0.11.1/nvim-linux-x86_64.tar.gz; then
    log_error "Failed to download Neovim"
    return 1
  fi

  # Extract to user's home
  log_info "Step 4/10: Extracting Neovim..."
  if ! tar xzvf nvim-linux-x86_64.tar.gz -C "$ACTUAL_HOME"; then
    log_error "Failed to extract Neovim"
    return 1
  fi

  log_info "Setting permissions for Neovim directory..."
  if ! chown -R "$ACTUAL_USER":"$ACTUAL_USER" "$NVIM_DIR"; then
    log_error "Failed to set ownership for Neovim directory"
    return 1
  fi

  # Add Neovim to PATH in .zshrc if not already there
  log_info "Step 5/10: Updating shell configuration..."
  if ! grep -q "alias nvim=" "$ACTUAL_HOME/.zshrc"; then
    # Fix: Using different delimiter (|) for sed since the path contains forward slashes
    if ! sed -i "s|alias ec=\"sudo nvim ~/\.zshrc\"|alias ec=\"sudo $NVIM_DIR/bin/nvim ~/\.zshrc\"|" "$ACTUAL_HOME/.zshrc"; then
      log_error "Failed to update ec alias in .zshrc"
    fi
    cat >>"$ACTUAL_HOME/.zshrc" <<EOL
alias nvim='$NVIM_DIR/bin/nvim'
EOL
    log_info "Added Neovim alias to .zshrc"
  else
    log_info "Neovim alias already exists in .zshrc"
  fi

  # Install tree-sitter
  cd /tmp || return 1
  log_info "Step 6/10: Downloading tree-sitter..."
  if ! wget --show-progress https://github.com/tree-sitter/tree-sitter/releases/download/v0.20.8/tree-sitter-linux-x64.gz; then
    log_error "Failed to download tree-sitter"
    return 1
  fi

  log_info "Step 7/10: Extracting and installing tree-sitter..."
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
  log_info "Step 8/10: Installing Neovim Python support..."
  if ! python3.12 -m pip install neovim; then
    log_error "Failed to install Neovim Python support"
    return 1
  fi

  # Create directories for LazyVim
  log_info "Step 9/10: Creating Neovim configuration directory..."
  mkdir -p "$ACTUAL_HOME/.config"

  # Clone LazyVim starter
  log_info "Step 10/10: Setting up LazyVim configuration..."
  if [ ! -d "$ACTUAL_HOME/.config/nvim" ]; then
    log_info "Cloning LazyVim starter repository..."
    if ! su - "$ACTUAL_USER" -c "git clone https://github.com/LazyVim/starter ~/.config/nvim"; then
      log_error "Failed to clone LazyVim starter"
      return 1
    fi

    log_info "Removing git repository from LazyVim starter..."
    if ! su - "$ACTUAL_USER" -c "rm -rf ~/.config/nvim/.git"; then
      log_error "Failed to remove .git directory from LazyVim starter"
      # Not returning 1 here as this is not critical
    fi
  else
    log_info "LazyVim configuration already exists"
  fi

  # Clean up
  log_info "Cleaning up temporary files..."
  rm -f /tmp/nvim-linux-x86_64.tar.gz

  log_info "✅ Neovim v0.11.1 installation completed successfully!"
  log_info "You can start Neovim by typing 'nvim' in your terminal after reloading your shell."
  return 0
}

#-----------------------------------------------------------------------------------------------------------------------------------------------
# Function to configure SSH with real-time priority
#-----------------------------------------------------------------------------------------------------------------------------------------------
configure_ssh_priority() {
  log_info "Configuring SSH with real-time priority..."

  # Create SSH service override directory
  log_info "Step 1/3: Creating SSH service override directory..."
  if ! mkdir -p /etc/systemd/system/ssh.service.d; then
    log_error "Failed to create SSH service override directory"
    return 1
  fi

  # Create override configuration file
  log_info "Step 2/3: Creating SSH service override configuration..."
  cat >/etc/systemd/system/ssh.service.d/override.conf <<'EOL'
[Service]
CPUSchedulingPolicy=rr
CPUSchedulingPriority=99
EOL
  log_info "Created SSH override configuration with real-time priority settings"

  # Reload systemd and restart SSH service
  log_info "Step 3/3: Reloading systemd daemon and restarting SSH service..."
  if ! systemctl daemon-reload; then
    log_error "Failed to reload systemd daemon"
    return 1
  fi
  log_info "Systemd daemon reloaded successfully"

  if ! systemctl restart ssh; then
    log_error "Failed to restart SSH service"
    return 1
  fi
  log_info "SSH service restarted successfully"

  log_info "✅ SSH configured with real-time priority successfully!"
  return 0
}

#-----------------------------------------------------------------------------------------------------------------------------------------------
# Function to install rsync
#-----------------------------------------------------------------------------------------------------------------------------------------------
install_rsync() {
  log_info "Installing rsync..."

  # Install rsync package
  log_info "Step 1/2: Installing rsync package from repositories..."
  if ! apt install -y rsync; then
    log_error "Failed to install rsync"
    return 1
  fi

  # Verify installation
  log_info "Step 2/2: Verifying rsync installation..."
  if ! command -v rsync >/dev/null 2>&1; then
    log_error "rsync command not found after installation"
    return 1
  fi

  # Show version information
  rsync_version=$(rsync --version | head -n 1)
  log_info "Installed $rsync_version"

  log_info "✅ rsync installation completed successfully!"
  return 0
}

#-----------------------------------------------------------------------------------------------------------------------------------------------
# Function to create DEV directory
#-----------------------------------------------------------------------------------------------------------------------------------------------
create_dev_directory() {
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
      configure_ssh_priority
      install_rsync
      create_dev_directory
      optimize_zsh

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
        17) configure_ssh_priority ;;
        18) install_rsync ;;
        19) create_dev_directory ;;
        20) optimize_zsh ;;
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
