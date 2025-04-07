#!/bin/bash
set -e

# Check for target device argument
if [ "$#" -ne 1 ]; then
  echo "Usage: $0 /dev/sdX"
  exit 1
fi

TARGET_DEVICE="$1"

# Confirm that the target device exists and is a block device
if [ ! -b "${TARGET_DEVICE}" ]; then
  echo "Error: ${TARGET_DEVICE} is not a valid block device."
  exit 1
fi

# WARNING: This operation will destroy all data on ${TARGET_DEVICE}.
read -p "WARNING: This will erase all data on ${TARGET_DEVICE}. Are you sure? (yes/no) " answer
if [ "$answer" != "yes" ]; then
  echo "Aborting installation."
  exit 1
fi

# Directories and source locations
PROJECT_DIR="$(pwd)/"
SYSTEM_DIR="$(pwd)/system"
ROOTFS_DIR="${SYSTEM_DIR}/build/rootfs"
SOURCES_DIR="$(pwd)/sources"
INITRAM_DIR="${PROJECT_DIR}/initramfs/build"
KERNEL="${PROJECT_DIR}/old/sources/linux/arch/x86_64/boot/bzImage"
INITRAMFS="${INITRAM_DIR}/initramfs.cpio"

# Image partition parameters (in MB)
EFI_SIZE=100       # EFI partition size (MB)
SYSTEM_SIZE=500    # System partition size (MB)
# Data partition will use the remainder of the USB device

echo "Partitioning ${TARGET_DEVICE} with GPT:"
echo "  Partition 1: EFI (${EFI_SIZE} MB)"
echo "  Partition 2: System (${SYSTEM_SIZE} MB)"
echo "  Partition 3: Data (remainder)"

# Create a new GPT partition table on the target USB device
parted "${TARGET_DEVICE}" --script mklabel gpt

# Partition 1: EFI from 1MiB to (EFI_SIZE+1)MiB
parted "${TARGET_DEVICE}" --script mkpart EFI fat32 1MiB $(( EFI_SIZE + 1 ))MiB
parted "${TARGET_DEVICE}" --script set 1 boot on

# Partition 2: System from (EFI_SIZE+1)MiB to (EFI_SIZE+SYSTEM_SIZE+1)MiB
parted "${TARGET_DEVICE}" --script mkpart System ext4 $(( EFI_SIZE + 1 ))MiB $(( EFI_SIZE + SYSTEM_SIZE + 1 ))MiB

# Partition 3: Data from (EFI_SIZE+SYSTEM_SIZE+1)MiB to 100% of the device
parted "${TARGET_DEVICE}" --script mkpart Data ext4 $(( EFI_SIZE + SYSTEM_SIZE + 1 ))MiB 100%

# Force kernel to re-read the partition table and wait for udev to create device nodes
partprobe "${TARGET_DEVICE}"
sleep 2

# Determine partition device names
if [ -e "${TARGET_DEVICE}p1" ]; then
    EFI_PART="${TARGET_DEVICE}p1"
    SYSTEM_PART="${TARGET_DEVICE}p2"
    DATA_PART="${TARGET_DEVICE}p3"
else
    EFI_PART="${TARGET_DEVICE}1"
    SYSTEM_PART="${TARGET_DEVICE}2"
    DATA_PART="${TARGET_DEVICE}3"
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

# Mount the System partition
echo "Mounting System partition at ${SYSTEM_MNT}..."
mount "${SYSTEM_PART}" "${SYSTEM_MNT}"

# Prepare and mount the EFI partition
echo "Creating EFI mount point at ${SYSTEM_MNT}/boot/efi..."
mkdir -p "${SYSTEM_MNT}/boot/efi"
echo "Mounting EFI partition at ${SYSTEM_MNT}/boot/efi..."
mount "${EFI_PART}" "${SYSTEM_MNT}/boot/efi"

# Mount the Data partition (optional integration into the system)
echo "Mounting Data partition at ${DATA_MNT}..."
mount "${DATA_PART}" "${DATA_MNT}"
mkdir -p "${SYSTEM_MNT}/data"

# Copy the built root filesystem into the System partition
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
echo "Installing GRUB EFI bootloader on ${TARGET_DEVICE}..."
grub-install --target=x86_64-efi \
    --efi-directory="${SYSTEM_MNT}/boot/efi" \
    --boot-directory="${SYSTEM_MNT}/boot" \
    --removable \
    --recheck \
    --no-floppy \
    --root-directory="${SYSTEM_MNT}" \
    "${TARGET_DEVICE}"

# Create a minimal GRUB configuration file:
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

# Unmount partitions
echo "Cleaning up: unmounting partitions..."
umount "${SYSTEM_MNT}/boot/efi"
umount "${SYSTEM_MNT}"
umount "${DATA_MNT}"
rmdir "${SYSTEM_MNT}" "${EFI_MNT}" "${DATA_MNT}"

echo "OS installation complete on USB device: ${TARGET_DEVICE}"
echo "Partition layout:"
echo "  EFI: ${EFI_SIZE} MB"
echo "  System: ${SYSTEM_SIZE} MB (contains kernel, initramfs, and root filesystem)"
echo "  Data: remainder"
