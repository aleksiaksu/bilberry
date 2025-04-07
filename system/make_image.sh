#!/bin/bash
#
# This script downloads BusyBox, builds it (statically linked),
# sets up a minimal root filesystem with a working /init,
# and then packages the filesystem into an initramfs image.
#
# Requirements:
#   - wget, tar, make, gcc, and cpio must be installed.
#   - Root privileges might be needed for creating device nodes.
#
# You can boot the generated initramfs with a kernel (for example, using QEMU):
#   qemu-system-x86_64 -kernel /path/to/bzImage -initrd initramfs.cpio -append "console=ttyS0"
#

set -e

# Configuration: BusyBox version and working directories.
BUILD_DIR="$(pwd)/build"
ROOTFS_DIR="${BUILD_DIR}/rootfs"

# Create an initramfs image (using the newc cpio format).
cd "${ROOTFS_DIR}"
echo "Packaging the root filesystem into initramfs.cpio..."
find . | cpio -H newc -o > "${BUILD_DIR}/initramfs.cpio"

echo "Build complete. You can now boot your system with:"
echo "  qemu-system-x86_64 -kernel /path/to/bzImage -initrd ${BUILD_DIR}/initramfs.cpio -append 'console=ttyS0'"
