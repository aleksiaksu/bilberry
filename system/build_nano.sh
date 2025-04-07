#!/bin/bash
set -e

# Directories and version information.
BUILD_DIR="$(pwd)/build"
ROOTFS_DIR="${BUILD_DIR}/rootfs"
NANO_VERSION="6.4"
NANO_TARBALL="nano-${NANO_VERSION}.tar.xz"
NANO_URL="https://www.nano-editor.org/dist/v6/${NANO_TARBALL}"

# Create build directory if necessary.
mkdir -p "${BUILD_DIR}"
cd "${BUILD_DIR}"

# Download GNU nano source if not already downloaded.
if [ ! -f "${NANO_TARBALL}" ]; then
    echo "Downloading GNU nano ${NANO_VERSION}..."
    wget "${NANO_URL}"
fi

# Extract the source tarball.
if [ ! -d "nano-${NANO_VERSION}" ]; then
    echo "Extracting nano..."
    tar xf "${NANO_TARBALL}"
fi

cd "nano-${NANO_VERSION}"

# Configure nano.
# The following options disable features that might not be needed in a minimal system.
# The --prefix ensures installation goes into / in your rootfs.
./configure --prefix=/ --disable-libmagic --disable-speller --disable-extra --disable-nls LDFLAGS="-static"

# Build GNU nano.
echo "Building GNU nano..."
make -j$(nproc)

# Install GNU nano into the root filesystem.
echo "Installing GNU nano into the root filesystem..."
make DESTDIR="${ROOTFS_DIR}" install

echo "GNU nano is installed in ${ROOTFS_DIR}//bin. You can run it via //bin/nano."
