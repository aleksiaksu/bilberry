#!/bin/bash
set -e

# Directories and source locations
PROJECT_DIR="$(pwd)/"
SYSTEM_DIR="$(pwd)/system"
BUILD_DIR="$(pwd)/build"
ROOTFS_DIR="${SYSTEM_DIR}/build/rootfs"
SOURCES_DIR="$(pwd)/sources"
INITRAM_DIR="${PROJECT_DIR}/initramfs/build"
KERNEL="${PROJECT_DIR}/sources/linux/arch/x86_64/boot/bzImage"
INITRAMFS="${INITRAM_DIR}/initramfs.cpio"

mkdir -p ${BUILD_DIR}

# Image parameters (in MB)
TOTAL_SIZE=1024    # Total image size (e.g., 1024 MB)
EFI_SIZE=100       # EFI partition size (MB)
SYSTEM_SIZE=500    # System partition size (MB)
# Data partition will use the remainder

# Output image file
IMG_FILE="${BUILD_DIR}/distro.img"

echo "Creating a ${TOTAL_SIZE} MB blank disk image at ${IMG_FILE}..."
dd if=/dev/zero of="${IMG_FILE}" bs=1M count="${TOTAL_SIZE}" status=progress

echo "Partitioning image with GPT:"
echo "  Partition 1: EFI (${EFI_SIZE} MB)"
echo "  Partition 2: System (${SYSTEM_SIZE} MB)"
echo "  Partition 3: Data (remainder)"
parted "${IMG_FILE}" --script mklabel gpt
# Partition 1: EFI from 1MiB to (EFI_SIZE+1)MiB
parted "${IMG_FILE}" --script mkpart EFI fat32 1MiB $(( EFI_SIZE + 1 ))MiB
parted "${IMG_FILE}" --script set 1 boot on
# Partition 2: System from (EFI_SIZE+1)MiB to (EFI_SIZE+SYSTEM_SIZE+1)MiB
parted "${IMG_FILE}" --script mkpart System ext4 $(( EFI_SIZE + 1 ))MiB $(( EFI_SIZE + SYSTEM_SIZE + 1 ))MiB
# Partition 3: Data from (EFI_SIZE+SYSTEM_SIZE+1)MiB to 100% of the image
parted "${IMG_FILE}" --script mkpart Data ext4 $(( EFI_SIZE + SYSTEM_SIZE + 1 ))MiB 100%

# Map the image to a loop device
LOOP_DEV=$(losetup -f --show "${IMG_FILE}")
echo "Image mapped to loop device: ${LOOP_DEV}"
partprobe "${LOOP_DEV}"

# Determine partition device names (they might be /dev/loopXp1, /dev/loopXp2, /dev/loopXp3)
if [ -e "${LOOP_DEV}p1" ]; then
    EFI_PART="${LOOP_DEV}p1"
    SYSTEM_PART="${LOOP_DEV}p2"
    DATA_PART="${LOOP_DEV}p3"
else
    EFI_PART="${LOOP_DEV}1"
    SYSTEM_PART="${LOOP_DEV}2"
    DATA_PART="${LOOP_DEV}3"
fi
echo "EFI partition: ${EFI_PART}"
echo "System partition: ${SYSTEM_PART}"
echo "Data partition: ${DATA_PART}"

# Format the partitions
echo "Formatting EFI partition as FAT32..."
mkfs.fat -F32 "${EFI_PART}"
echo "Formatting System partition as ext4..."
mkfs.ext4 "${SYSTEM_PART}"
echo "Formatting Data partition as ext4..."
mkfs.ext4 "${DATA_PART}"

# Create mount points
SYSTEM_MNT=$(mktemp -d)
EFI_MNT=$(mktemp -d)
DATA_MNT=$(mktemp -d)

echo "Mounting System partition at ${SYSTEM_MNT}..."
mount "${SYSTEM_PART}" "${SYSTEM_MNT}"
echo "Creating EFI mount point at ${SYSTEM_MNT}/boot/efi..."
mkdir -p "${SYSTEM_MNT}/boot/efi"
echo "Mounting EFI partition at ${SYSTEM_MNT}/boot/efi..."
mount "${EFI_PART}" "${SYSTEM_MNT}/boot/efi"
echo "Mounting Data partition at ${DATA_MNT}..."
mount "${DATA_PART}" "${DATA_MNT}"
# Optionally, integrate the data partition into the system:
mkdir -p "${SYSTEM_MNT}/data"

# Copy your built root filesystem into the System partition
echo "Copying root filesystem from ${ROOTFS_DIR} to ${SYSTEM_MNT}..."
cp -a "${ROOTFS_DIR}/." "${SYSTEM_MNT}/"

# Copy kernel and initramfs into /boot of the System partition
echo "Copying kernel and initramfs to ${SYSTEM_MNT}/boot..."
mkdir -p "${SYSTEM_MNT}/boot"
cp "${KERNEL}" "${SYSTEM_MNT}/boot/bzImage"
cp "${INITRAMFS}" "${SYSTEM_MNT}/boot/initramfs.cpio"

# Capture the UUID of the System partition to use in grub.cfg.
SYSTEM_UUID=$(blkid -s UUID -o value "${SYSTEM_PART}")
echo "System partition UUID: ${SYSTEM_UUID}"

# Install GRUB for EFI:
echo "Installing GRUB EFI bootloader..."
grub-install --target=x86_64-efi \
    --efi-directory="${SYSTEM_MNT}/boot/efi" \
    --boot-directory="${SYSTEM_MNT}/boot" \
    --removable \
    --recheck \
    --no-floppy \
    --root-directory="${SYSTEM_MNT}" \
    "${LOOP_DEV}"

# Create a minimal grub.cfg file:
echo "Creating GRUB configuration..."
mkdir -p "${SYSTEM_MNT}/boot/grub"
cat > "${SYSTEM_MNT}/boot/grub/grub.cfg" <<EOF
set default=0
set timeout=5

menuentry "Minimal Distro" {
    linux /boot/bzImage
    initrd /boot/initramfs.cpio
}
EOF

# Unmount partitions and detach loop device
echo "Cleaning up: unmounting partitions..."
umount "${SYSTEM_MNT}/boot/efi"
umount "${SYSTEM_MNT}"
umount "${DATA_MNT}"
rmdir "${SYSTEM_MNT}" "${EFI_MNT}" "${DATA_MNT}"
losetup -d "${LOOP_DEV}"

echo "Bootable IMG file created at: ${IMG_FILE}"
echo "Partitions:"
echo "  EFI: ${EFI_SIZE} MB"
echo "  System: ${SYSTEM_SIZE} MB (contains kernel, initramfs, and root filesystem)"
echo "  Data: remainder"
echo "You can now flash this image to a disk or use it with UEFI-capable hardware."
