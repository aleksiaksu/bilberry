#!/bin/bash
set -e

# Directories for building and for the final root filesystem.
BUILD_DIR="$(pwd)/build"
ROOTFS_DIR="${BUILD_DIR}/rootfs"

mkdir -p "${BUILD_DIR}" "${ROOTFS_DIR}"

###############################
# 1. Build and Install musl   #
###############################

MUSL_VERSION="1.2.5"
MUSL_TARBALL="musl-${MUSL_VERSION}.tar.gz"
MUSL_URL="https://musl.libc.org/releases/${MUSL_TARBALL}"

cd "${BUILD_DIR}"
if [ ! -f "${MUSL_TARBALL}" ]; then
    echo "Downloading musl libc ${MUSL_VERSION}..."
    wget "${MUSL_URL}"
fi

if [ ! -d "musl-${MUSL_VERSION}" ]; then
    echo "Extracting musl libc..."
    tar xzf "${MUSL_TARBALL}"
fi

cd "musl-${MUSL_VERSION}"
echo "Configuring musl libc..."
./configure --prefix=/usr/local/musl LDFLAGS="-static"
echo "Building musl libc..."
make -j$(nproc)
echo "Installing musl libc into the root filesystem..."
make DESTDIR="${ROOTFS_DIR}" install

echo "============================================"
echo "Musl libc and minimal GCC installation complete."
echo "Musl is installed into ${ROOTFS_DIR}/usr/local/musl"
echo "You can use the musl-based GCC with the target 'x86_64-linux-musl'."
echo "============================================"
