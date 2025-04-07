#!/bin/bash

# Directories and version information.
BUILD_DIR="$(pwd)/build"
ROOTFS_DIR="${BUILD_DIR}/rootfs"
NCURSES_VERSION="6.4"
NCURSES_SRC="ncurses-${NCURSES_VERSION}"
NCURSES_TAR="${NCURSES_SRC}.tar.gz"
NCURSES_URL="https://ftp.gnu.org/pub/gnu/ncurses/${NCURSES_TAR}"

# Create build directory if necessary.
mkdir -p "${BUILD_DIR}"
cd "${BUILD_DIR}"

# Download ncurses source code if not already present.
if [ ! -f "${NCURSES_TAR}" ]; then
    echo "Downloading ncurses..."
    wget "${NCURSES_URL}" || { echo "Failed to download ncurses"; exit 1; }
fi

# Extract source code.
echo "Extracting ncurses..."
tar -xf "${NCURSES_TAR}"
cd "${NCURSES_SRC}" || { echo "Failed to enter ncurses source directory"; exit 1; }

# Configure and build ncurses.
./configure \
    --prefix="${ROOTFS_DIR}/usr" \
    --with-shared \
    --with-termlib \
    --enable-widec || { echo "Configuration failed"; exit 1; }

make -j$(nproc) || { echo "Build failed"; exit 1; }
make install || { echo "Installation failed"; exit 1; }

# Cleanup
cd "${BUILD_DIR}"
echo "Cleaning up..."
rm -rf "${NCURSES_SRC}"

# Verify installation.
echo "Checking installation..."
ls "${ROOTFS_DIR}/usr/lib" | grep ncurses
