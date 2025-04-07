#!/bin/bash
set -e

# Directories and file names.
PROJECT_DIR="$(pwd)/"
BUILD_DIR="$(pwd)/build"
ROOTFS_DIR="${BUILD_DIR}/rootfs"
SOURCE_DIR="$(pwd)/sources"

# Bilberry ETC


cat > "${ROOTFS_DIR}/etc/fstab" << "EOF"
# file system  mount-point  type   options          dump  fsck
#                                                         order

rootfs          /               auto    defaults        1      1
proc            /proc           proc    defaults        0      0
sysfs           /sys            sysfs   defaults        0      0
devpts          /dev/pts        devpts  gid=4,mode=620  0      0
tmpfs           /dev/shm        tmpfs   defaults        0      0

EOF

cat > "${ROOTFS_DIR}/etc/mdev.conf" << "EOF"
# Devices:
# Syntax: %s %d:%d %s
# devices user:group mode

# null does already exist; therefore ownership has to
# be changed with command
null    root:root 0666  @chmod 666 $MDEV
zero    root:root 0666
grsec   root:root 0660
full    root:root 0666

random  root:root 0666
urandom root:root 0444
hwrandom root:root 0660

# console does already exist; therefore ownership has to
# be changed with command
console root:tty 0600 @mkdir -pm 755 fd && cd fd && for x
 ↪in 0 1 2 3 ; do ln -sf /proc/self/fd/$x $x; done

kmem    root:root 0640
mem     root:root 0640
port    root:root 0640
ptmx    root:tty 0666

# ram.*
ram([0-9]*)     root:disk 0660 >rd/%1
loop([0-9]+)    root:disk 0660 >loop/%1
sd[a-z].*       root:disk 0660 */lib/mdev/usbdisk_link
hd[a-z][0-9]*   root:disk 0660 */lib/mdev/ide_links

tty             root:tty 0666
tty[0-9]        root:root 0600
tty[0-9][0-9]   root:tty 0660
ttyO[0-9]*      root:tty 0660
pty.*           root:tty 0660
vcs[0-9]*       root:tty 0660
vcsa[0-9]*      root:tty 0660

ttyLTM[0-9]     root:dialout 0660 @ln -sf $MDEV modem
ttySHSF[0-9]    root:dialout 0660 @ln -sf $MDEV modem
slamr           root:dialout 0660 @ln -sf $MDEV slamr0
slusb           root:dialout 0660 @ln -sf $MDEV slusb0
fuse            root:root  0666

# misc stuff
agpgart         root:root 0660  >misc/
psaux           root:root 0660  >misc/
rtc             root:root 0664  >misc/

# input stuff
event[0-9]+     root:root 0640 =input/
ts[0-9]         root:root 0600 =input/

# v4l stuff
vbi[0-9]        root:video 0660 >v4l/
video[0-9]      root:video 0660 >v4l/

# load drivers for usb devices
usbdev[0-9].[0-9]       root:root 0660 */lib/mdev/usbdev
usbdev[0-9].[0-9]_.*    root:root 0660

EOF

cat > "${ROOTFS_DIR}/etc/shadow" << "EOF"
root::19046:0:99999:7:::
aksu::19046:0:99999:7:::

EOF

cat > "${ROOTFS_DIR}/etc/profile" << "EOF"

export PATH=/bin:/usr/bin

if [ `id -u` -eq 0 ] ; then
        PATH=/bin:/sbin:/usr/bin:/usr/sbin
        unset HISTFILE
fi


# Set up some environment variables.
export USER=`id -un`
export LOGNAME=$USER
export HOSTNAME=`/bin/hostname`
export HISTSIZE=1000
export HISTFILESIZE=1000
export PAGER='/bin/more '
export EDITOR='/bin/nano'

EOF

cat > "${ROOTFS_DIR}/etc/passwd" << "EOF"
root:x:0:0:root:/root:/bin/ash
aksu:x:1000:1000:tmpuser:/tmp:/bin/ash
EOF

cat > "${ROOTFS_DIR}/etc/issue" << "EOF"
Welcome to Bilberry
Kernel \r on an \m
EOF

cat > "${ROOTFS_DIR}/etc/inittab" << "EOF"
::sysinit:/etc/rc.d/startup

tty1::respawn:/sbin/getty 38400 tty1
tty2::respawn:/sbin/getty 38400 tty2
tty3::respawn:/sbin/getty 38400 tty3
tty4::respawn:/sbin/getty 38400 tty4
tty5::respawn:/sbin/getty 38400 tty5
tty6::respawn:/sbin/getty 38400 tty6

::shutdown:/etc/rc.d/shutdown
::ctrlaltdel:/sbin/reboot

EOF

cat > "${ROOTFS_DIR}/etc/hosts" << "EOF"
127.0.0.1 localhost
EOF

cat > "${ROOTFS_DIR}/etc/hostname" << "EOF"
localhost
EOF

ln "${ROOTFS_DIR}/etc/hostname" "${ROOTFS_DIR}/etc/HOSTNAME"

cat > "${ROOTFS_DIR}/etc/group" << "EOF"
root:x:0:
bin:x:1:
sys:x:2:
kmem:x:3:
tty:x:4:
daemon:x:6:
disk:x:8:
dialout:x:10:
video:x:12:
utmp:x:13:
usb:x:14:
tmpuser:x:1000:
EOF

# Qemu Networking, please comment lines if not needed

cat > "${ROOTFS_DIR}/bin/legacy-networking-static" << "EOF"
#!/bin/sh
ifconfig eth0 0.0.0.0
route add default gw 0.0.0.0
[ "$(date +%s)" -lt 1000 ] && timeout 2 sntp -sq 192.168.10.1 # Ask host
[ "$(date +%s)" -lt 10000000 ] && sntp -sq time.google.com
EOF
chmod +x "${ROOTFS_DIR}/bin/legacy-networking-static"

cat > "${ROOTFS_DIR}/bin/aakeyb" << "EOF"
#!/bin/sh
# This script lists available keymap files from /usr/share/bkeymaps
# and loads the selected layout using loadkmap.

KEYMAP_DIR="/usr/share/bkeymaps"

# Check if the keymap directory exists.
if [ ! -d "$KEYMAP_DIR" ]; then
    echo "Error: Directory '$KEYMAP_DIR' not found."
    exit 1
fi

echo "Available keymaps in $KEYMAP_DIR:"
echo "---------------------------------"
# List keymap files (adjust the file pattern as needed).
ls -1 "$KEYMAP_DIR"
echo "---------------------------------"
echo ""

# Prompt the user to enter the keymap filename.
printf "Enter the keymap filename to load (or press ENTER to cancel): "
read keymap

# Exit if no input provided.
if [ -z "$keymap" ]; then
    echo "No keymap selected. Exiting."
    exit 0
fi

# Check if the selected keymap file exists.
if [ ! -f "$KEYMAP_DIR/$keymap" ]; then
    echo "Error: File '$keymap' does not exist in $KEYMAP_DIR."
    exit 1
fi

echo "Loading keymap '$keymap'..."
# loadkmap typically reads from standard input.
if command -v loadkmap >/dev/null 2>&1; then
    loadkmap < "$KEYMAP_DIR/$keymap"
    echo "Keymap '$keymap' loaded successfully."
else
    echo "Error: 'loadkmap' command not found. Please install an appropriate environment."
    exit 1
fi
EOF
chmod +x "${ROOTFS_DIR}/bin/aakeyb"

cp ${PROJECT_DIR}/linkline_server ${ROOTFS_DIR}/bin
cp ${PROJECT_DIR}/linkline_server ${ROOTFS_DIR}/bin

cp -r ${SOURCE_DIR}/bkeymaps ${ROOTFS_DIR}/usr/share/

# PACKAGE MANAGER (Very alpha)

cat > "${ROOTFS_DIR}/bin/aainstall" << "EOF"
#!/bin/sh
# aainstall - A minimal package manager for a minimal distro.
# Commands:
#   update  - Download repository index from a fixed URL.
#   search  - Search the local repository index for packages.
#   add     - Install a package from source.
#
# Package format: packagename-version.tar.gz (system files only)
#
# Example repository index URL:
#   http://example.com/repo/info.index

# Set repository index URL and local storage directory.
REPO_INDEX_URL="http://repo.local:8080/info.index"
LOCAL_INDEX_DIR="/etc/aainstall"
LOCAL_INDEX_FILE="$LOCAL_INDEX_DIR/info.index"
INSTALL_LOG="$LOCAL_INDEX_DIR/installed.log"

# Ensure the local repository directory exists.
mkdir -p "$LOCAL_INDEX_DIR"

# Function: update - Downloads the repository index.
update_index() {
    echo "Updating repository index from $REPO_INDEX_URL..."
    if command -v wget >/dev/null 2>&1; then
        wget -O "$LOCAL_INDEX_FILE" "$REPO_INDEX_URL"
    elif command -v curl >/dev/null 2>&1; then
        curl -o "$LOCAL_INDEX_FILE" "$REPO_INDEX_URL"
    else
        echo "Error: Neither wget nor curl is available."
        exit 1
    fi
    echo "Repository index updated and saved to $LOCAL_INDEX_FILE."
}

# Function: search - Searches the local repository index for a given term.
search_package() {
    if [ -z "$1" ]; then
        echo "Usage: aainstall search <search-term>"
        exit 1
    fi
    if [ ! -f "$LOCAL_INDEX_FILE" ]; then
        echo "Local repository index not found. Run 'aainstall update' first."
        exit 1
    fi
    echo "Searching for packages matching \"$1\":"
    grep -i -C3 "$1" "$LOCAL_INDEX_FILE" || echo "No matches found for \"$1\"."
}

# Function: add - Installs a package from the repository.
add_package() {
    if [ -z "$1" ]; then
        echo "Usage: aainstall add <package-name>"
        exit 1
    fi
    PACKAGE_NAME="$1"
    if [ ! -f "$LOCAL_INDEX_FILE" ]; then
        echo "Local repository index not found. Run 'aainstall update' first."
        exit 1
    fi

    # Extract the package block from the index.
    PACKAGE_INFO=$(awk -v pkg="Package: $PACKAGE_NAME" 'BEGIN {RS=""; FS="\n"} $0 ~ pkg {print}' "$LOCAL_INDEX_FILE")
    if [ -z "$PACKAGE_INFO" ]; then
        echo "Package '$PACKAGE_NAME' not found in repository index."
        exit 1
    fi

    PACKAGE_VERSION=$(echo "$PACKAGE_INFO" | grep "^Version:" | awk '{print $2}')
    PACKAGE_URL=$(echo "$PACKAGE_INFO" | grep "^URL:" | awk '{print $2}')
    PACKAGE_DESC=$(echo "$PACKAGE_INFO" | grep "^Description:" | cut -d' ' -f2-)

    echo "Found package: $PACKAGE_NAME"
    echo "Version: $PACKAGE_VERSION"
    echo "URL: $PACKAGE_URL"
    echo "Description: $PACKAGE_DESC"

    # Determine the tarball name (assumes format packagename-version.tar.gz).
    TARBALL="${PACKAGE_NAME}-${PACKAGE_VERSION}.tar.gz"

    echo "Downloading $TARBALL ..."
    if command -v wget >/dev/null 2>&1; then
        wget -O "$TARBALL" "$PACKAGE_URL"
    elif command -v curl >/dev/null 2>&1; then
        curl -o "$TARBALL" "$PACKAGE_URL"
    else
        echo "Error: Neither wget nor curl is available."
        exit 1
    fi

    # Create a temporary directory for extraction.
    TMP_DIR=$(mktemp -d)
    echo "Extracting $TARBALL to $TMP_DIR ..."
    tar xzf "$TARBALL" -C "$TMP_DIR"

    # Install the package by copying its files to the root filesystem.
    # (Assumes package tarball contains files with paths relative to '/')
    echo "Installing package $PACKAGE_NAME ..."
    cp -a "$TMP_DIR"/* /

    # Clean up temporary files.
    rm -rf "$TMP_DIR"
    rm -f "$TARBALL"

    echo "Package '$PACKAGE_NAME' installed successfully."

    # Record the installation.
    echo "$PACKAGE_NAME $PACKAGE_VERSION installed on $(date)" >> "$INSTALL_LOG"
}

# Main command dispatcher.
case "$1" in
    update)
        update_index
        ;;
    search)
        shift
        search_package "$*"
        ;;
    add)
        shift
        add_package "$1"
        ;;
    *)
        echo "Usage: $0 {update|search|add}"
        exit 1
        ;;
esac
EOF
chmod +x "${ROOTFS_DIR}/bin/aainstall"

# NETWORK FIX

mkdir -p "${ROOTFS_DIR}/etc/network"

cat > "${ROOTFS_DIR}/etc/network/interfaces" << "EOF"
auto lo
iface lo inet loopback

auto eth0
iface eth0 inet dhcp
EOF

mkdir -p "${ROOTFS_DIR}/usr/share/udhcpc"

cat > "${ROOTFS_DIR}/usr/share/udhcpc/default.script" << "EOF"
#!/bin/ash
#
# Minimal udhcpc script that sets up networking and modifies /etc/network/interfaces.
#

INTERFACES_FILE="/etc/network/interfaces"
RESOLV_CONF="/etc/resolv.conf"

interface="${interface:-eth0}"  # Provided by udhcpc
ip="${ip:-}"                    # Provided by udhcpc
subnet="${subnet:-}"
router="${router:-}"
dns="${dns:-}"

case "$1" in
    deconfig)
        echo "Deconfiguring interface: $interface"

        # Optionally remove interface config from /etc/network/interfaces
        # WARNING: Be careful with sed usage in a production system.
        sed -i "/auto $interface/d" $INTERFACES_FILE 2>/dev/null
        sed -i "/iface $interface inet dhcp/d" $INTERFACES_FILE 2>/dev/null

        # Bring down the interface
        ifconfig $interface 0.0.0.0
        ;;

    bound|renew)
        echo "Configuring interface: $interface"
        
        # 1. Configure IP address and netmask
        ifconfig $interface $ip netmask $subnet

        # 2. Set up default route (gateway)
        # Remove existing default route(s) for interface
        ip route show dev $interface | grep default | while read -r route; do
            ip route del $route
        done
        for gw in $router; do
            route add default gw $gw dev $interface
        done

        # 3. Configure DNS
        echo -n > $RESOLV_CONF
        for ns in $dns; do
            echo "nameserver $ns" >> $RESOLV_CONF
        done

        # 4. Ensure /etc/network/interfaces has a DHCP entry for this interface
        if ! grep -q "auto $interface" $INTERFACES_FILE; then
            echo "auto $interface" >> $INTERFACES_FILE
        fi
        if ! grep -q "iface $interface inet dhcp" $INTERFACES_FILE; then
            echo "iface $interface inet dhcp" >> $INTERFACES_FILE
        fi

        # 5. Logging or any other notifications you need
        echo "Interface $interface configured via DHCP"
        ;;

    *)
        echo "$0: udhcpc script called with unknown action: $1" >&2
        exit 1
        ;;
esac

exit 0
EOF
chmod +x "${ROOTFS_DIR}/usr/share/udhcpc/default.script"


cat > "${ROOTFS_DIR}/bin/dhcp-setup" << "EOF"
#!/bin/sh
udhcpc -i eth0 -s /usr/share/udhcpc/default.script
EOF
chmod +x "${ROOTFS_DIR}/bin/dhcp-setup"

cat > "${ROOTFS_DIR}/bin/cls" << "EOF"
#!/bin/sh
busybox clear
EOF
chmod +x "${ROOTFS_DIR}/bin/cls"

cat > "${ROOTFS_DIR}/bin/tree" << "EOF"
#!/bin/ash
# A simple tree-like directory listing in ash script

# Function: tree
# Recursively prints a directory tree with a visual branch structure.
tree() {
    local dir="$1"
    local prefix="$2"
    local count=0
    local item
    local i=0

    # Count total items in the current directory
    for item in "$dir"/*; do
        # If no matching file is found, the glob expands to itself.
        [ "$item" = "$dir/*" ] && break
        count=$((count + 1))
    done

    # Loop over items in the directory
    for item in "$dir"/*; do
        # If no matching file is found, exit the loop
        [ "$item" = "$dir/*" ] && break
        i=$((i + 1))
        if [ "$i" -eq "$count" ]; then
            echo "${prefix}└── $(basename "$item")"
            new_prefix="${prefix}    "
        else
            echo "${prefix}├── $(basename "$item")"
            new_prefix="${prefix}│   "
        fi
        # If the item is a directory, recursively call tree
        if [ -d "$item" ]; then
            tree "$item" "$new_prefix"
        fi
    done
}

# Determine the starting directory (default to current directory)
dir="."
if [ $# -ge 1 ]; then
    dir="$1"
fi

# Print the base directory name and invoke the tree function
echo "$(basename "$dir")"
tree "$dir" ""
EOF
chmod +x "${ROOTFS_DIR}/bin/tree"

cp ${PROJECT_DIR}/scripts/aafetch.sh ${ROOTFS_DIR}/bin/aafetch
chmod +x ${ROOTFS_DIR}/bin/aafetch

cat > "${ROOTFS_DIR}/bin/gen-fstab" << "EOF"
#!/bin/ash
# This script generates /etc/fstab entries for EFI, SYSTEM and DATA partitions.
# It expects the output of blkid (or a file containing similar output).
#
# EFI is mounted at /boot/efi with type "EFI" (defaults, dump=0, pass=1)
# SYSTEM is mounted at /system with type "ext4" (defaults, dump=0, pass=1)
# DATA is mounted at /data with type "ext4" (defaults, dump=0, pass=2)
#
# Note: blkid output order can be random so we try to verify partition names
# using LABEL if available. If no LABEL is found, we fall back to a simple
# counter based on the partition device number.

# Empty /etc/fstab (or comment out this line if you want to append)
> /etc/fstab

# Read blkid output. If you have it in a file (e.g. /tmp/blkid.out), use:
# while read line; do ... done < /tmp/blkid.out
blkid | while read line; do
    # Extract UUID from the line
    uuid=$(echo "$line" | sed -n 's/.*UUID="\([^"]*\)".*/\1/p')
    
    # Try to extract LABEL if present
    label=$(echo "$line" | sed -n 's/.*LABEL="\([^"]*\)".*/\1/p')
    
    # Fallback: if no label is provided, determine role from device number.
    if [ -z "$label" ]; then
        # Assume device name like /dev/sdaX. Remove the trailing colon.
        dev=$(echo "$line" | awk '{print $1}' | sed 's/://')
        # Extract the last digit(s) from the device name
        partnum=$(echo "$dev" | sed 's/.*[a-z]\+\([0-9]\+\)$/\1/')
        case "$partnum" in
            1) label="EFI" ;;
            2) label="SYSTEM" ;;
            3) label="DATA" ;;
            *) label="" ;;  # unknown, ignore
        esac
    fi

    # Now use if-elif to generate the correct fstab line based on the label.
    if [ "$label" = "EFI" ]; then
         echo "UUID=$uuid  /efi  EFI    defaults  0 1" >> /etc/fstab
    elif [ "$label" = "SYSTEM" ]; then
         echo "UUID=$uuid  /new_root    ext4   defaults  0 1" >> /etc/fstab
    elif [ "$label" = "DATA" ]; then
         echo "UUID=$uuid  /data      ext4   defaults  0 2" >> /etc/fstab
    fi
done

# End of script.
EOF
chmod +x "${ROOTFS_DIR}/bin/gen-fstab"

cat > "${ROOTFS_DIR}/bin/find-system-par" << "EOF"
#!/bin/ash
# This script generates /etc/fstab entries for EFI, SYSTEM and DATA partitions.
# It expects the output of blkid (or a file containing similar output).
#
# EFI is mounted at /boot/efi with type "EFI" (defaults, dump=0, pass=1)
# SYSTEM is mounted at /system with type "ext4" (defaults, dump=0, pass=1)
# DATA is mounted at /data with type "ext4" (defaults, dump=0, pass=2)
#
# Note: blkid output order can be random so we try to verify partition names
# using LABEL if available. If no LABEL is found, we fall back to a simple
# counter based on the partition device number.

# Empty /etc/fstab (or comment out this line if you want to append)
> /etc/fstab

# Read blkid output. If you have it in a file (e.g. /tmp/blkid.out), use:
# while read line; do ... done < /tmp/blkid.out
blkid | while read line; do
    # Extract UUID from the line
    uuid=$(echo "$line" | sed -n 's/.*UUID="\([^"]*\)".*/\1/p')
    
    # Try to extract LABEL if present
    label=$(echo "$line" | sed -n 's/.*LABEL="\([^"]*\)".*/\1/p')
    
    # Fallback: if no label is provided, determine role from device number.
    if [ -z "$label" ]; then
        # Assume device name like /dev/sdaX. Remove the trailing colon.
        dev=$(echo "$line" | awk '{print $1}' | sed 's/://')
        # Extract the last digit(s) from the device name
        partnum=$(echo "$dev" | sed 's/.*[a-z]\+\([0-9]\+\)$/\1/')
        case "$partnum" in
            1) label="EFI" ;;
            2) label="SYSTEM" ;;
            3) label="DATA" ;;
            *) label="" ;;  # unknown, ignore
        esac
    fi

    # Now use if-elif to generate the correct fstab line based on the label.
    if [ "$label" = "SYSTEM" ]; then
         echo "UUID=$uuid  /new_root    ext4   defaults  0 1" >> /etc/fstab
    fi
done

# End of script.
EOF
chmod +x "${ROOTFS_DIR}/bin/find-system-par"

cat > "${ROOTFS_DIR}/bin/find-data-par" << "EOF"
#!/bin/ash
# This script generates /etc/fstab entries for EFI, SYSTEM and DATA partitions.
# It expects the output of blkid (or a file containing similar output).
#
# EFI is mounted at /boot/efi with type "EFI" (defaults, dump=0, pass=1)
# SYSTEM is mounted at /system with type "ext4" (defaults, dump=0, pass=1)
# DATA is mounted at /data with type "ext4" (defaults, dump=0, pass=2)
#
# Note: blkid output order can be random so we try to verify partition names
# using LABEL if available. If no LABEL is found, we fall back to a simple
# counter based on the partition device number.

# Empty /etc/fstab (or comment out this line if you want to append)
> /etc/fstab

# Read blkid output. If you have it in a file (e.g. /tmp/blkid.out), use:
# while read line; do ... done < /tmp/blkid.out
blkid | while read line; do
    # Extract UUID from the line
    uuid=$(echo "$line" | sed -n 's/.*UUID="\([^"]*\)".*/\1/p')
    
    # Try to extract LABEL if present
    label=$(echo "$line" | sed -n 's/.*LABEL="\([^"]*\)".*/\1/p')
    
    # Fallback: if no label is provided, determine role from device number.
    if [ -z "$label" ]; then
        # Assume device name like /dev/sdaX. Remove the trailing colon.
        dev=$(echo "$line" | awk '{print $1}' | sed 's/://')
        # Extract the last digit(s) from the device name
        partnum=$(echo "$dev" | sed 's/.*[a-z]\+\([0-9]\+\)$/\1/')
        case "$partnum" in
            1) label="EFI" ;;
            2) label="SYSTEM" ;;
            3) label="DATA" ;;
            *) label="" ;;  # unknown, ignore
        esac
    fi

    # Now use if-elif to generate the correct fstab line based on the label.
    if [ "$label" = "DATA" ]; then
         echo "UUID=$uuid  /data      ext4   defaults  0 2" >> /system/etc/fstab
    fi
done

# End of script.
EOF
chmod +x "${ROOTFS_DIR}/bin/find-data-par"

cat > "${ROOTFS_DIR}/bin/init-system" << "EOF"
#!/bin/sh

command_disabled=true

if [ "$command_disabled" = "true" ]; then
    echo "Error: Cannot run this command."
    echo "Not recommended to run!"
    exit 1
else
    # Continue with the rest of your script
    echo "Command enabled. Proceeding..."
fi

/bin/gen-fstab
mkdir -p /newinit /efi /data
mount -a
echo "Very alpha! Type command if sure: start-system"
EOF
chmod +x "${ROOTFS_DIR}/bin/init-system"

cat > "${ROOTFS_DIR}/bin/start-system" << "EOF"
#!/bin/sh
/bin/find-system-par
mkdir -p /new_root /efi /data
mount -a
rm /new_root/etc/fstab
mount --move /sys /new_root/sys
mount --move /proc /new_root/proc
mount --move /dev /new_root/dev
mount --move /run /new_root/run
exec switch_root -c /dev/console /new_root /sbin/init
EOF
chmod +x "${ROOTFS_DIR}/bin/start-system"

cat > "${ROOTFS_DIR}/bin/aakeyb-new" << "EOF"
#!/bin/sh
# This script searches for keymap files in /usr/share/bkeymaps based on a user-provided search term
# and loads the selected layout using loadkmap.

KEYMAP_DIR="/usr/share/bkeymaps"

# Check if the keymap directory exists.
if [ ! -d "$KEYMAP_DIR" ]; then
    echo "Error: Directory '$KEYMAP_DIR' not found."
    exit 1
fi

echo "Available keymaps in $KEYMAP_DIR:"
echo "---------------------------------"
ls -1 "$KEYMAP_DIR"
echo "---------------------------------"
echo ""

# Prompt the user to enter a search term for the keymap.
printf "Enter a search term for the keymap to load (or press ENTER to cancel): "
read search_term

# Exit if no input provided.
if [ -z "$search_term" ]; then
    echo "No keymap selected. Exiting."
    exit 0
fi

# Find matching keymaps (case-insensitive).
matches=$(ls -1 "$KEYMAP_DIR" | grep -i "$search_term")
if [ -z "$matches" ]; then
    echo "Error: No keymap files matching '$search_term' found in $KEYMAP_DIR."
    exit 1
fi

# Count the number of matching files.
count=$(echo "$matches" | wc -l)

if [ "$count" -eq 1 ]; then
    keymap="$matches"
    echo "Found keymap: $keymap"
else
    echo "Multiple keymaps found:"
    i=1
    # Display the matches as a numbered list.
    echo "$matches" | while read -r line; do
        echo "$i) $line"
        i=$((i+1))
    done

    printf "Enter the number of the keymap to load: "
    read selection

    # Validate that the input is a number and within range.
    if ! echo "$selection" | grep -Eq '^[0-9]+$'; then
        echo "Invalid selection. Exiting."
        exit 1
    fi

    if [ "$selection" -lt 1 ] || [ "$selection" -gt "$count" ]; then
        echo "Selection out of range. Exiting."
        exit 1
    fi

    # Get the selected keymap.
    keymap=$(echo "$matches" | sed -n "${selection}p")
fi

# Verify that the keymap file exists.
if [ ! -f "$KEYMAP_DIR/$keymap" ]; then
    echo "Error: File '$keymap' does not exist in $KEYMAP_DIR."
    exit 1
fi

echo "Loading keymap '$keymap'..."
# loadkmap typically reads from standard input.
if command -v loadkmap >/dev/null 2>&1; then
    loadkmap < "$KEYMAP_DIR/$keymap"
    echo "Keymap '$keymap' loaded successfully."
else
    echo "Error: 'loadkmap' command not found. Please install an appropriate environment."
    exit 1
fi
EOF
chmod +x "${ROOTFS_DIR}/bin/aakeyb-new"