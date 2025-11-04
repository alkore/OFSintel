#!/bin/bash
# OFS FunGen Edition - macOS Build Script
# Supports both Intel (x86_64) and Apple Silicon (arm64) architectures

set -e  # Exit on error

echo "=========================================="
echo "OFS FunGen Edition - macOS Build Script"
echo "=========================================="
echo ""

# Check for required tools
if ! command -v cmake &> /dev/null; then
    echo "ERROR: CMake is not installed. Please install it via Homebrew:"
    echo "  brew install cmake"
    exit 1
fi

if ! command -v git &> /dev/null; then
    echo "ERROR: Git is not installed."
    exit 1
fi

# Detect architecture
ARCH=$(uname -m)
echo "Detected system architecture: $ARCH"
echo ""

# Determine correct Homebrew path and brew command based on architecture
if [ "$ARCH" = "arm64" ]; then
    BREW_PREFIX="/opt/homebrew"
    BREW_CMD="$BREW_PREFIX/bin/brew"
    REQUIRED_MPV_ARCH="arm64"
    MPV_LIB_PATH="$BREW_PREFIX/opt/mpv/lib/libmpv.dylib"
else
    BREW_PREFIX="/usr/local"
    BREW_CMD="$BREW_PREFIX/bin/brew"
    REQUIRED_MPV_ARCH="x86_64"
    MPV_LIB_PATH="$BREW_PREFIX/opt/mpv/lib/libmpv.dylib"
fi

# Check if correct Homebrew is installed
if [ ! -f "$BREW_CMD" ]; then
    echo "WARNING: Homebrew not found at $BREW_PREFIX"
    if [ "$ARCH" = "arm64" ]; then
        echo "You appear to be on Apple Silicon, but ARM64 Homebrew is not installed."
        echo ""
        read -p "Install ARM64 Homebrew now? (y/n) " -n 1 -r
        echo ""
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            echo "Installing ARM64 Homebrew..."
            arch -arm64 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

            # Add to PATH if not already there
            if ! grep -q "/opt/homebrew/bin/brew shellenv" ~/.zprofile 2>/dev/null; then
                echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile
            fi
            eval "$(/opt/homebrew/bin/brew shellenv)"
        else
            echo "Cannot continue without Homebrew. Exiting."
            exit 1
        fi
    else
        echo "Please install Homebrew from https://brew.sh"
        exit 1
    fi
fi

# Check for libmpv
echo "Checking for mpv library..."
MPV_INSTALLED=false
MPV_CORRECT_ARCH=false

if "$BREW_CMD" list mpv &> /dev/null; then
    MPV_INSTALLED=true
    echo "  mpv is installed via Homebrew"

    # Check if the mpv library exists and has correct architecture
    if [ -f "$MPV_LIB_PATH" ]; then
        MPV_ARCH=$(file "$MPV_LIB_PATH" | grep -o "arm64\|x86_64" | head -1)
        echo "  mpv library architecture: $MPV_ARCH"

        if [ "$MPV_ARCH" = "$REQUIRED_MPV_ARCH" ]; then
            MPV_CORRECT_ARCH=true
            echo "  ✓ mpv architecture matches build target"
        else
            echo "  ✗ Architecture mismatch! mpv is $MPV_ARCH, but need $REQUIRED_MPV_ARCH"
        fi
    else
        echo "  ✗ mpv library not found at expected location: $MPV_LIB_PATH"
    fi
else
    echo "  mpv is not installed"
fi

echo ""

# Handle mpv installation/reinstallation
if [ "$MPV_INSTALLED" = false ] || [ "$MPV_CORRECT_ARCH" = false ]; then
    if [ "$MPV_INSTALLED" = false ]; then
        echo "WARNING: libmpv not found via Homebrew."
        echo "OFS requires libmpv to play videos."
    else
        echo "WARNING: mpv is installed but with wrong architecture."
        echo "Your system is $ARCH, but mpv is $MPV_ARCH."
        echo "This will cause runtime errors when trying to load mpv."
    fi
    echo ""

    if [ "$ARCH" = "arm64" ]; then
        echo "Recommended action: Install ARM64 version of mpv"
        echo "Command: $BREW_CMD install mpv"
    else
        echo "Recommended action: Install mpv"
        echo "Command: $BREW_CMD install mpv"
    fi
    echo ""

    read -p "Install/reinstall mpv now? (y/n) " -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        if [ "$MPV_INSTALLED" = true ]; then
            echo "Uninstalling existing mpv..."
            # Use the architecture-specific brew to uninstall
            if [ "$ARCH" = "arm64" ] && [ -f "/usr/local/bin/brew" ]; then
                # If on ARM but mpv was installed with Intel brew, use Intel brew to uninstall
                /usr/local/bin/brew uninstall mpv 2>/dev/null || true
            fi
            "$BREW_CMD" uninstall mpv 2>/dev/null || true
        fi

        echo "Installing mpv with correct architecture..."
        "$BREW_CMD" install mpv

        # Verify installation
        if [ -f "$MPV_LIB_PATH" ]; then
            INSTALLED_ARCH=$(file "$MPV_LIB_PATH" | grep -o "arm64\|x86_64" | head -1)
            echo "✓ Successfully installed mpv ($INSTALLED_ARCH)"
        else
            echo "ERROR: mpv installation completed but library not found"
            exit 1
        fi
    else
        echo ""
        echo "WARNING: Continuing without correct mpv installation."
        echo "The build may succeed, but the application will fail to load videos at runtime."
        echo ""
        read -p "Continue anyway? (y/n) " -n 1 -r
        echo ""
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
fi

echo ""

# Initialize submodules if needed
if [ ! -f "lib/SDL2/CMakeLists.txt" ]; then
    echo ""
    echo "Initializing git submodules..."
    git submodule update --init --recursive
fi

# Build configuration
BUILD_TYPE="${BUILD_TYPE:-Release}"
BUILD_DIR="build"
UNIVERSAL_BINARY="${UNIVERSAL_BINARY:-no}"

echo ""
echo "Build Configuration:"
echo "  Build Type: $BUILD_TYPE"
if [ "$UNIVERSAL_BINARY" = "yes" ]; then
    echo "  Build Target: Universal (x86_64 + ARM64)"
else
    echo "  Build Target: ARM64 only"
fi
echo ""

# Create build directory
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

# Configure CMake
echo "Configuring CMake..."
if [ "$UNIVERSAL_BINARY" = "yes" ]; then
    cmake .. \
        -DCMAKE_BUILD_TYPE="$BUILD_TYPE" \
        -DCMAKE_OSX_DEPLOYMENT_TARGET=11.0 \
        -DCMAKE_OSX_ARCHITECTURES="x86_64;arm64" \
        -DOFS_BUILD_UNIVERSAL=ON
else
    cmake .. \
        -DCMAKE_BUILD_TYPE="$BUILD_TYPE" \
        -DCMAKE_OSX_DEPLOYMENT_TARGET=11.0 \
        -DCMAKE_OSX_ARCHITECTURES="arm64" \
        -DOFS_BUILD_UNIVERSAL=OFF
fi

# Build
echo ""
echo "Building OFS..."
cmake --build . --config "$BUILD_TYPE" -j$(sysctl -n hw.ncpu)

cd ..

echo ""
echo "=========================================="
echo "Build complete!"
echo "=========================================="
echo ""
echo "Binary location: bin/OpenFunscripter"

if [ -f "bin/OpenFunscripter" ]; then
    echo ""
    echo "Binary architecture(s):"
    file bin/OpenFunscripter | grep -o 'executable \w\+'
    lipo -info bin/OpenFunscripter 2>/dev/null || true
    echo ""
    echo "To run: ./bin/OpenFunscripter"
fi
