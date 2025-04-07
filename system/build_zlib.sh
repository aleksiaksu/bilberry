#!/bin/bash
set -e

ZLIB_VERSION="1.3.1"
ZLIB_TARBALL="zlib-${ZLIB_VERSION}.tar.gz"
ZLIB_URL="https://zlib.net/${ZLIB_TARBALL}"
SOURCES_DIR="$(pwd)/sources"
BUILD_DIR="$(pwd)/build"
ROOTFS_DIR="${BUILD_DIR}/rootfs"

mkdir -p "${SOURCES_DIR}" "${BUILD_DIR}" "${ROOTFS_DIR}"

cd "${SOURCES_DIR}"
if [ ! -f "${ZLIB_TARBALL}" ]; then
    wget "${ZLIB_URL}"
fi

tar xzf "${ZLIB_TARBALL}"
cd "zlib-${ZLIB_VERSION}"
./configure --prefix=/usr/local
make -j$(nproc)
make DESTDIR="${ROOTFS_DIR}" install

echo "zlib installed in ${ROOTFS_DIR}/usr/local"
