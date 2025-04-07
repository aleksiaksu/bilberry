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
BB_VERSION="1.36.1"
BB_TARBALL="busybox-${BB_VERSION}.tar.bz2"
BB_URL="https://busybox.net/downloads/${BB_TARBALL}"
BUILD_DIR="$(pwd)/build"
ROOTFS_DIR="${BUILD_DIR}/rootfs"

# Create working directories.
mkdir -p "${BUILD_DIR}"
mkdir -p "${ROOTFS_DIR}"

# Download BusyBox if not already downloaded.
if [ ! -f "${BUILD_DIR}/${BB_TARBALL}" ]; then
    echo "Downloading BusyBox ${BB_VERSION}..."
    wget -P "${BUILD_DIR}" "${BB_URL}"
fi

# Extract BusyBox source.
cd "${BUILD_DIR}"
if [ ! -d "busybox-${BB_VERSION}" ]; then
    echo "Extracting BusyBox..."
    tar xjf "${BB_TARBALL}"
fi

cd "busybox-${BB_VERSION}"

# Clean previous builds.
make distclean

# Create default configuration.
make defconfig

# Enable static compilation by forcing CONFIG_STATIC=y.
# (This sed command replaces the default line; adjust if needed.)
sed -i 's/^# CONFIG_STATIC is not set/CONFIG_STATIC=y/' .config
sed -i 's/# CONFIG_UDHCPC is not set/CONFIG_UDHCPC=y/' .config
# More commands
sed -i 's/# CONFIG_UDHCPD is not set/CONFIG_UDHCPD=y/' .config
sed -i 's/# CONFIG_IFUP is not set/CONFIG_IFUP=y/' .config
sed -i 's/# CONFIG_IFDOWN is not set/CONFIG_IFDOWN=y/' .config
sed -i 's/# CONFIG_MDEV is not set/CONFIG_MDEV=y/' .config
sed -i 's/# CONFIG_LOGGER is not set/CONFIG_LOGGER=y/' .config
sed -i 's/# CONFIG_TELNETD is not set/CONFIG_TELNETD=y/' .config
sed -i 's/# CONFIG_HTTPD is not set/CONFIG_HTTPD=y/' .config
sed -i 's/# CONFIG_FTPD is not set/CONFIG_FTPD=y/' .config
sed -i 's/# CONFIG_CHVT is not set/CONFIG_CHVT=y/' .config
sed -i 's/# CONFIG_SETFONT is not set/CONFIG_SETFONT=y/' .config
sed -i 's/# CONFIG_NOHUP is not set/CONFIG_NOHUP=y/' .config
sed -i 's/# CONFIG_TIMEOUT is not set/CONFIG_TIMEOUT=y/' .config
sed -i 's/# CONFIG_PIDOF is not set/CONFIG_PIDOF=y/' .config
sed -i 's/# CONFIG_PGREP is not set/CONFIG_PGREP=y/' .config
sed -i 's/# CONFIG_MKTEMP is not set/CONFIG_MKTEMP=y/' .config
sed -i 's/# CONFIG_USLEEP is not set/CONFIG_USLEEP=y/' .config
sed -i 's/# CONFIG_WATCH is not set/CONFIG_WATCH=y/' .config
sed -i 's/# CONFIG_TREE is not set/CONFIG_TREE=y/' .config
# More commands yet
sed -i 's/# CONFIG_DD is not set/CONFIG_DD=y/' .config
sed -i 's/# CONFIG_MD5SUM is not set/CONFIG_MD5SUM=y/' .config
sed -i 's/# CONFIG_SHA1SUM is not set/CONFIG_SHA1SUM=y/' .config
sed -i 's/# CONFIG_SHA256SUM is not set/CONFIG_SHA256SUM=y/' .config
sed -i 's/# CONFIG_TAR is not set/CONFIG_TAR=y/' .config
sed -i 's/# CONFIG_GUNZIP is not set/CONFIG_GUNZIP=y/' .config
sed -i 's/# CONFIG_LOGGER is not set/CONFIG_LOGGER=y/' .config
sed -i 's/# CONFIG_DMESG is not set/CONFIG_DMESG=y/' .config
sed -i 's/# CONFIG_IFCONFIG is not set/CONFIG_IFCONFIG=y/' .config
sed -i 's/# CONFIG_ARP is not set/CONFIG_ARP=y/' .config
sed -i 's/# CONFIG_NETSTAT is not set/CONFIG_NETSTAT=y/' .config
sed -i 's/# CONFIG_PING is not set/CONFIG_PING=y/' .config
sed -i 's/# CONFIG_TRACEROUTE is not set/CONFIG_TRACEROUTE=y/' .config
sed -i 's/# CONFIG_TOP is not set/CONFIG_TOP=y/' .config
sed -i 's/# CONFIG_PS is not set/CONFIG_PS=y/' .config
sed -i 's/# CONFIG_CLEAR is not set/CONFIG_CLEAR=y/' .config

# Build BusyBox (you can adjust -j to use more parallel jobs).
echo "Building BusyBox..."
make -j$(nproc) CFLAGS+=" -Wno-error=deprecated-declarations"

# Install BusyBox into our rootfs.
echo "Installing BusyBox into rootfs..."
make CONFIG_PREFIX="${ROOTFS_DIR}" install

# Create additional necessary directories in the rootfs.
cd "${ROOTFS_DIR}"
for dir in proc sys dev etc tmp var root; do
    mkdir -p ${dir}
done

chown -R root:root "${ROOTFS_DIR}/root"
chmod -R 760 "${ROOTFS_DIR}/root"

# Create a simple /init script.
cat << 'EOF' > init
#!/bin/sh
# Mount virtual filesystems
mount -t proc none /proc
mount -t sysfs none /sys
mount -t devtmpfs devtmpfs /dev

# (Optional) Create necessary device nodes if they do not exist.
if [ ! -c /dev/console ]; then
    echo "Creating /dev/console and /dev/null..."
    mknod -m 622 /dev/console c 5 1
    mknod -m 666 /dev/null c 1 3
    mknod -m 600 /dev/tty1    c 4 1
    mknod -m 600 /dev/tty2    c 4 2
    mknod -m 600 /dev/tty3    c 4 1
    mknod -m 600 /dev/tty4    c 4 2
fi

echo "Remounting mounts..."
mount -a

echo "Loading interactive shell..."
# Start an interactive shell.
exec /sbin/init
EOF

# Make /init executable.
chmod +x init

# (Optional) Set ownership to root (if building as non-root, this may be a no-op).
chown root:root init

# BASED ON PACKAGE clfs-embedded-bootscripts-1.0-pre5.tar.bz2
# ETC

mkdir -p "${ROOTFS_DIR}/etc/init.d"; mkdir -p "${ROOTFS_DIR}/etc/rc.d"

cat > "${ROOTFS_DIR}/etc/init.d/rcS" << "EOF"
#!/bin/sh
exec /etc/rc.d/startup

EOF
chmod a+x "${ROOTFS_DIR}/etc/init.d/rcS"
cp -r ${BUILD_DIR}/../sources/init/rc.d/* "${ROOTFS_DIR}/etc/rc.d/"
