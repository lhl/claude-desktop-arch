#!/bin/bash
set -e

########################################
# Configuration
########################################

# Update this URL when a new version of Claude Desktop is released
CLAUDE_DOWNLOAD_URL="https://storage.googleapis.com/osprey-downloads-c02f6a0d-347c-492b-a752-3e0651722e97/nest-win-x64/Claude-Setup-x64.exe"
VERSION="0.7.7"

########################################
# Parse command line arguments
########################################

FORCE_DOWNLOAD=false
while [[ $# -gt 0 ]]; do
    case $1 in
        --force-download)
            FORCE_DOWNLOAD=true
            shift
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 [--force-download]"
            exit 1
            ;;
    esac
done

########################################
# Identify real user
########################################

REAL_USER="${SUDO_USER:-$USER}"
REAL_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)
NVM_DIR="$REAL_HOME/.nvm"

########################################
# Sudo helper for general commands
########################################

run_as_user() {
    sudo -H -u "$REAL_USER" HOME="$REAL_HOME" USER="$REAL_USER" "$@"
}

########################################
# Sudo helper that sources NVM + Node
########################################

run_as_user_nvm() {
    # We run as the real user, then inside that user shell we export NVM_DIR,
    # source nvm, ensure Node 20 is installed/used, then run the requested command.
    sudo -E -H -u "$REAL_USER" bash -c "
        export HOME=\"$REAL_HOME\"
        export USER=\"$REAL_USER\"
        export NVM_DIR=\"$NVM_DIR\"
        # shellcheck source=/dev/null
        [ -s \"$NVM_DIR/nvm.sh\" ] && . \"$NVM_DIR/nvm.sh\"
        nvm install 20
        nvm use 20
        $*
    "
}

########################################
# Preliminary checks
########################################

# Check for Arch Linux
if [ ! -f "/etc/arch-release" ]; then
    echo "❌ This script requires Arch Linux"
    exit 1
fi

# Check for sudo
if [ "$EUID" -ne 0 ]; then
    echo "Please run this script with sudo"
    exit 1
fi

# Print system information
echo "System Information:"
echo "Distribution: $(grep 'PRETTY_NAME' /etc/os-release | cut -d'\"' -f2)"

# Check for NVM
if [ ! -f "$NVM_DIR/nvm.sh" ]; then
    echo "❌ NVM is required but not found in $NVM_DIR"
    echo "Please install NVM first by following:"
    echo "  https://github.com/nvm-sh/nvm#installing-and-updating"
    echo "Then run this script again."
    exit 1
fi
echo "✓ NVM found in $REAL_HOME"

########################################
# Function: check if a command exists
########################################

check_command() {
    if ! command -v "$1" &>/dev/null; then
        echo "❌ $1 not found"
        return 1
    else
        echo "✓ $1 found"
        return 0
    fi
}

########################################
# Function: check 7z
########################################

check_7z() {
    if command -v 7z &>/dev/null || command -v p7zip &>/dev/null; then
        echo "✓ 7z functionality found"
        return 0
    else
        echo "❌ 7z functionality not found"
        return 1
    fi
}

########################################
# Function: check for system nodejs
# (Warn user if installed, since nvm is recommended)
########################################

check_system_node() {
    local node_pkgs=(nodejs npm nodejs-lts-hydrogen nodejs-lts-iron)
    local installed_pkgs=()
    
    for pkg in "${node_pkgs[@]}"; do
        if pacman -Qi "$pkg" &>/dev/null; then
            installed_pkgs+=("$pkg")
        fi
    done
    
    if [ ${#installed_pkgs[@]} -gt 0 ]; then
        echo "⚠️  Warning: Found system Node.js packages installed while using NVM:"
        printf "   %s\n" "${installed_pkgs[@]}"
        echo "It's recommended to remove them to avoid conflicts:"
        echo "   sudo pacman -Rns ${installed_pkgs[*]}"
        echo ""
        read -p "Would you like to remove them now? [y/N] " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            pacman -Rns "${installed_pkgs[@]}"
            echo "✓ System Node.js packages removed"
        else
            echo "Continuing with system packages installed..."
        fi
    fi
}

########################################
# Perform system checks
########################################

check_system_node

echo "Checking dependencies..."
DEPS_TO_INSTALL=""

# Map commands to package names (excluding 7z logic)
declare -A package_map=(
    ["wget"]="wget"
    ["wrestool"]="icoutils"
    ["icotool"]="icoutils"
    ["convert"]="imagemagick"
)

# Check 7z
if ! check_7z; then
    if pacman -Ss ^7zip$ &>/dev/null; then
        DEPS_TO_INSTALL="$DEPS_TO_INSTALL 7zip"
    else
        DEPS_TO_INSTALL="$DEPS_TO_INSTALL p7zip"
    fi
fi

# Check other commands
for cmd in wget wrestool icotool convert; do
    if ! check_command "$cmd"; then
        DEPS_TO_INSTALL="$DEPS_TO_INSTALL ${package_map[$cmd]}"
    fi
done

# Install system dependencies if needed
if [ -n "$DEPS_TO_INSTALL" ]; then
    echo "Installing system dependencies: $DEPS_TO_INSTALL"
    pacman -Sy --noconfirm $DEPS_TO_INSTALL
    echo "System dependencies installed successfully"
fi

########################################
# Create directories
########################################

WORK_DIR="$(pwd)/build"
PKG_ROOT="$WORK_DIR/pkg"
INSTALL_DIR="$PKG_ROOT/usr"
CACHE_DIR="$(pwd)/cache"

rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR"
mkdir -p "$INSTALL_DIR/lib/claude-desktop"
mkdir -p "$INSTALL_DIR/share/applications"
mkdir -p "$INSTALL_DIR/share/icons"
mkdir -p "$INSTALL_DIR/bin"
mkdir -p "$CACHE_DIR"

chown -R "$REAL_USER:$REAL_USER" "$WORK_DIR"
chown -R "$REAL_USER:$REAL_USER" "$CACHE_DIR"

########################################
# Download with caching
########################################

CACHED_EXE="$CACHE_DIR/Claude-Setup-x64.exe"
if [[ "$FORCE_DOWNLOAD" = true ]] || [[ ! -f "$CACHED_EXE" ]]; then
    echo "📥 Downloading Claude Desktop installer..."
    run_as_user wget -O "$CACHED_EXE" "$CLAUDE_DOWNLOAD_URL"
    echo "✓ Download complete"
else
    echo "Using cached Claude Desktop installer"
fi

# Copy from cache to build dir
cp "$CACHED_EXE" "$WORK_DIR/Claude-Setup-x64.exe"
cd "$WORK_DIR"

########################################
# Extract resources using run_as_user
########################################

echo "📦 Extracting resources..."
run_as_user 7z x -y "Claude-Setup-x64.exe"
run_as_user 7z x -y "AnthropicClaude-$VERSION-full.nupkg"
echo "✓ Resources extracted"

########################################
# Extract and convert icons
########################################

echo "🎨 Processing icons..."
run_as_user wrestool -x -t 14 "lib/net45/claude.exe" -o claude.ico
run_as_user icotool -x claude.ico
echo "✓ Icons processed"

declare -A icon_files=(
    ["16"]="claude_13_16x16x32.png"
    ["24"]="claude_11_24x24x32.png"
    ["32"]="claude_10_32x32x32.png"
    ["48"]="claude_8_48x48x32.png"
    ["64"]="claude_7_64x64x32.png"
    ["256"]="claude_6_256x256x32.png"
)

for size in 16 24 32 48 64 256; do
    icon_dir="$INSTALL_DIR/share/icons/hicolor/${size}x${size}/apps"
    mkdir -p "$icon_dir"
    if [ -f "${icon_files[$size]}" ]; then
        echo "Installing ${size}x${size} icon..."
        install -Dm 644 "${icon_files[$size]}" "$icon_dir/claude-desktop.png"
    else
        echo "Warning: Missing ${size}x${size} icon"
    fi
done

########################################
# Prepare electron app
########################################

mkdir -p electron-app
cp "lib/net45/resources/app.asar" electron-app/
cp -r "lib/net45/resources/app.asar.unpacked" electron-app/
chown -R "$REAL_USER:$REAL_USER" electron-app

cd electron-app

# Now extract app.asar using npx in the real-user nvm environment
run_as_user_nvm "npx asar extract app.asar app.asar.contents"
chown -R "$REAL_USER:$REAL_USER" app.asar.contents

# Replace the claude-native module with a stub
echo "Creating stub native module..."
cat > app.asar.contents/node_modules/claude-native/index.js << 'EOF'
// Stub implementation of claude-native using KeyboardKey enum values
const KeyboardKey = {
  Backspace: 43,
  Tab: 280,
  Enter: 261,
  Shift: 272,
  Control: 61,
  Alt: 40,
  CapsLock: 56,
  Escape: 85,
  Space: 276,
  PageUp: 251,
  PageDown: 250,
  End: 83,
  Home: 154,
  LeftArrow: 175,
  UpArrow: 282,
  RightArrow: 262,
  DownArrow: 81,
  Delete: 79,
  Meta: 187
};

Object.freeze(KeyboardKey);

module.exports = {
  getWindowsVersion: () => "10.0.0",
  setWindowEffect: () => {},
  removeWindowEffect: () => {},
  getIsMaximized: () => false,
  flashFrame: () => {},
  clearFlashFrame: () => {},
  showNotification: () => {},
  setProgressBar: () => {},
  clearProgressBar: () => {},
  setOverlayIcon: () => {},
  clearOverlayIcon: () => {},
  KeyboardKey
};
EOF

chown -R "$REAL_USER:$REAL_USER" app.asar.contents

# Copy tray icons
mkdir -p app.asar.contents/resources
cp ../lib/net45/resources/Tray* app.asar.contents/resources/ || true

# Repackage app.asar
run_as_user_nvm "npx asar pack app.asar.contents app.asar"

# Copy the final asar and unpacked files
cp app.asar "$INSTALL_DIR/lib/claude-desktop/"
cp -r app.asar.unpacked "$INSTALL_DIR/lib/claude-desktop/"

# fix ownership so fakeroot can read them
chown -R "$REAL_USER:$REAL_USER" "$INSTALL_DIR/lib/claude-desktop"


########################################
# Desktop entry and launcher
########################################

cat > "$INSTALL_DIR/share/applications/claude-desktop.desktop" << EOF
[Desktop Entry]
Name=Claude
Exec=claude-desktop %u
Icon=claude-desktop
Type=Application
Terminal=false
Categories=Office;Utility;
MimeType=x-scheme-handler/claude;
EOF

cat > "$INSTALL_DIR/bin/claude-desktop" << 'EOF'
#!/bin/bash
electron /usr/lib/claude-desktop/app.asar "$@"
EOF
chmod +x "$INSTALL_DIR/bin/claude-desktop"

########################################
# Create PKGBUILD
########################################

cd "$WORK_DIR"
cat > "$WORK_DIR/PKGBUILD" << EOF
# Maintainer: Claude Desktop Linux Maintainers
pkgname=claude-desktop-bin
pkgver=$VERSION
pkgrel=1
pkgdesc="Claude Desktop for Linux"
arch=('x86_64')
url="https://www.anthropic.com"
license=('custom')
depends=('electron')
source=()
sha256sums=()

package() {
    cp -r $PKG_ROOT/* "\$pkgdir/"
}
EOF

chown "$REAL_USER:$REAL_USER" "$WORK_DIR/PKGBUILD"

########################################
# Build package
########################################

echo "Building package as $REAL_USER..."
run_as_user makepkg -f

PACKAGE_FILE="claude-desktop-${VERSION}-1-x86_64.pkg.tar.zst"
if [ -f "$PACKAGE_FILE" ]; then
    echo "✓ Package built successfully at: $PACKAGE_FILE"
    echo "🎉 Done! You can now install the package with: sudo pacman -U build/$PACKAGE_FILE"
else
    echo "❌ Package file not found at expected location: $PACKAGE_FILE"
    exit 1
fi
