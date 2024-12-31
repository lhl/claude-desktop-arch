#!/bin/bash
set -e

# Update this URL when a new version of Claude Desktop is released
CLAUDE_DOWNLOAD_URL="https://storage.googleapis.com/osprey-downloads-c02f6a0d-347c-492b-a752-3e0651722e97/nest-win-x64/Claude-Setup-x64.exe"
VERSION="0.7.7"

# Get the actual user when script is run with sudo
REAL_USER="${SUDO_USER:-$USER}"
REAL_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)

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
echo "Distribution: $(cat /etc/os-release | grep "PRETTY_NAME" | cut -d'"' -f2)"

# Function to check if a command exists
check_command() {
    if ! command -v "$1" &> /dev/null; then
        echo "❌ $1 not found"
        return 1
    else
        echo "✓ $1 found"
        return 0
    fi
}

# Function to check for 7z functionality
check_7z() {
    if command -v 7z &> /dev/null || command -v p7zip &> /dev/null; then
        echo "✓ 7z functionality found"
        return 0
    else
        echo "❌ 7z functionality not found"
        return 1
    fi
}

# Install dependencies
echo "Checking dependencies..."
DEPS_TO_INSTALL=""

# Map commands to package names, excluding 7z which we'll handle separately
declare -A package_map=(
    ["wget"]="wget"
    ["wrestool"]="icoutils"
    ["icotool"]="icoutils"
    ["convert"]="imagemagick"
    ["npx"]="nodejs npm"
)

# Check for 7z
if ! check_7z; then
    if pacman -Ss ^7zip$ > /dev/null 2>&1; then
        DEPS_TO_INSTALL="$DEPS_TO_INSTALL 7zip"
    else
        DEPS_TO_INSTALL="$DEPS_TO_INSTALL p7zip"
    fi
fi

# Check other dependencies
for cmd in wget wrestool icotool convert npx; do
    if ! check_command "$cmd"; then
        DEPS_TO_INSTALL="$DEPS_TO_INSTALL ${package_map[$cmd]}"
    fi
done

# Install system dependencies if any
if [ ! -z "$DEPS_TO_INSTALL" ]; then
    echo "Installing system dependencies: $DEPS_TO_INSTALL"
    pacman -Sy --noconfirm $DEPS_TO_INSTALL
    echo "System dependencies installed successfully"
fi

# Install electron globally via npm if not present
if ! check_command "electron"; then
    echo "Installing electron via npm..."
    npm install -g electron
    if ! check_command "electron"; then
        echo "Failed to install electron. Please install it manually:"
        echo "sudo npm install -g electron"
        exit 1
    fi
    echo "Electron installed successfully"
fi

# Install asar if needed
if ! npm list -g asar > /dev/null 2>&1; then
    echo "Installing asar package globally..."
    npm install -g asar
fi

# Create working directories
WORK_DIR="$(pwd)/build"
PKG_ROOT="$WORK_DIR/pkg"
INSTALL_DIR="$PKG_ROOT/usr"

# Clean previous build and ensure proper permissions
echo "Cleaning previous build..."
rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR"
mkdir -p "$INSTALL_DIR/lib/claude-desktop"
mkdir -p "$INSTALL_DIR/share/applications"
mkdir -p "$INSTALL_DIR/share/icons"
mkdir -p "$INSTALL_DIR/bin"

# Set permissions for build directory
chown -R "$REAL_USER:$REAL_USER" "$WORK_DIR"

# Function to run commands as the real user
run_as_user() {
    sudo -u "$REAL_USER" "$@"
}

# Download and process as real user
cd "$WORK_DIR"
echo "📥 Downloading Claude Desktop installer..."
run_as_user wget -O "Claude-Setup-x64.exe" "$CLAUDE_DOWNLOAD_URL"
echo "✓ Download complete"

# Extract resources
echo "📦 Extracting resources..."
run_as_user 7z x -y "Claude-Setup-x64.exe"
run_as_user 7z x -y "AnthropicClaude-$VERSION-full.nupkg"
echo "✓ Resources extracted"

# Extract and convert icons
echo "🎨 Processing icons..."
run_as_user wrestool -x -t 14 "lib/net45/claude.exe" -o claude.ico
run_as_user icotool -x claude.ico
echo "✓ Icons processed"

# Map icon sizes to their corresponding extracted files
declare -A icon_files=(
    ["16"]="claude_13_16x16x32.png"
    ["24"]="claude_11_24x24x32.png"
    ["32"]="claude_10_32x32x32.png"
    ["48"]="claude_8_48x48x32.png"
    ["64"]="claude_7_64x64x32.png"
    ["256"]="claude_6_256x256x32.png"
)

# Install icons
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

# Process app.asar
mkdir -p electron-app
cp "lib/net45/resources/app.asar" electron-app/
cp -r "lib/net45/resources/app.asar.unpacked" electron-app/

# Ensure electron-app directory and contents are owned by real user
chown -R "$REAL_USER:$REAL_USER" electron-app

cd electron-app
run_as_user npx asar extract app.asar app.asar.contents

# Ensure extracted contents are owned by real user
chown -R "$REAL_USER:$REAL_USER" app.asar.contents

# Replace native module with stub implementation
echo "Creating stub native module..."
cat > app.asar.contents/node_modules/claude-native/index.js << EOF
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

# Copy Tray icons
mkdir -p app.asar.contents/resources
cp ../lib/net45/resources/Tray* app.asar.contents/resources/

# Repackage app.asar
run_as_user npx asar pack app.asar.contents app.asar

# Copy app files
cp app.asar "$INSTALL_DIR/lib/claude-desktop/"
cp -r app.asar.unpacked "$INSTALL_DIR/lib/claude-desktop/"

# Create desktop entry
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

# Create launcher script
cat > "$INSTALL_DIR/bin/claude-desktop" << EOF
#!/bin/bash
electron /usr/lib/claude-desktop/app.asar "\$@"
EOF
chmod +x "$INSTALL_DIR/bin/claude-desktop"

# Create PKGBUILD
cat > PKGBUILD << EOF
# Maintainer: Claude Desktop Linux Maintainers
pkgname=claude-desktop
pkgver=$VERSION
pkgrel=1
pkgdesc="Claude Desktop for Linux"
arch=('x86_64')
url="https://www.anthropic.com"
license=('custom')
depends=('nodejs' 'npm' 'electron')
makedepends=('nodejs-lts-hydrogen')
source=()
sha256sums=()

package() {
    cp -r $PKG_ROOT/* "\$pkgdir/"
}
EOF

chown "$REAL_USER:$REAL_USER" PKGBUILD

# Build package as real user
echo "Building package as $REAL_USER..."
cd "$WORK_DIR"
run_as_user makepkg -f

PACKAGE_FILE="claude-desktop-${VERSION}-1-x86_64.pkg.tar.zst"
if [ -f "$PACKAGE_FILE" ]; then
    echo "✓ Package built successfully at: $PACKAGE_FILE"
    echo "🎉 Done! You can now install the package with: sudo pacman -U $PACKAGE_FILE"
else
    echo "❌ Package file not found at expected location: $PACKAGE_FILE"
    exit 1
fi
