#!/bin/bash
set -e

# Directories and file names.
PROJECT_DIR2="$(pwd)/"
BUILD_DIR2="$(pwd)/build"
ROOTFS_DIR2="${BUILD_DIR2}/rootfs"
SOURCE_DIR2="$(pwd)/sources"

# Aksubox ETC


cat > "${ROOTFS_DIR2}/etc/fstab" << "EOF"
# file system  mount-point  type   options          dump  fsck
#                                                         order

rootfs          /               auto    defaults        1      1
proc            /proc           proc    defaults        0      0
sysfs           /sys            sysfs   defaults        0      0
devpts          /dev/pts        devpts  gid=4,mode=620  0      0
tmpfs           /dev/shm        tmpfs   defaults        0      0

EOF

cat > "${ROOTFS_DIR2}/etc/mdev.conf" << "EOF"
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

cat > "${ROOTFS_DIR2}/etc/shadow" << "EOF"
root::19046:0:99999:7:::
aksu::19046:0:99999:7:::

EOF

cat > "${ROOTFS_DIR2}/etc/profile" << "EOF"

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
export EDITOR='/bin/vi'

EOF

cat > "${ROOTFS_DIR2}/etc/passwd" << "EOF"
root:x:0:0:root:/root:/bin/ash
aksu:x:1000:1001:aksu:/tmp:/bin/ash
EOF

cat > "${ROOTFS_DIR2}/etc/issue" << "EOF"
Bilberry Start Management: Starting system...
EOF

cat > "${ROOTFS_DIR2}/etc/inittab" << "EOF"
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

cat > "${ROOTFS_DIR2}/etc/hosts" << "EOF"
127.0.0.1 localhost
EOF

cat > "${ROOTFS_DIR2}/etc/hostname" << "EOF"
localhost
EOF

ln "${ROOTFS_DIR2}/etc/hostname" "${ROOTFS_DIR2}/etc/HOSTNAME"

cat > "${ROOTFS_DIR2}/etc/group" << "EOF"
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
EOF

# NETWORK FIX

mkdir -p "${ROOTFS_DIR2}/etc/network"

cat > "${ROOTFS_DIR2}/etc/network/interfaces" << "EOF"
auto lo
iface lo inet loopback

auto eth0
iface eth0 inet dhcp
EOF

mkdir -p "${ROOTFS_DIR2}/usr/share/udhcpc"

cat > "${ROOTFS_DIR2}/usr/share/udhcpc/default.script" << "EOF"
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
chmod +x "${ROOTFS_DIR2}/usr/share/udhcpc/default.script"


cat > "${ROOTFS_DIR2}/bin/dhcp-setup" << "EOF"
#!/bin/sh
udhcpc -i eth0 -s /usr/share/udhcpc/default.script
EOF
chmod +x "${ROOTFS_DIR2}/bin/dhcp-setup"

cat > "${ROOTFS_DIR2}/bin/cls" << "EOF"
#!/bin/sh
busybox clear
EOF
chmod +x "${ROOTFS_DIR2}/bin/cls"

cat > "${ROOTFS_DIR2}/bin/gen-fstab" << "EOF"
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
chmod +x "${ROOTFS_DIR2}/bin/gen-fstab"

cat > "${ROOTFS_DIR2}/bin/find-system-par" << "EOF"
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
chmod +x "${ROOTFS_DIR2}/bin/find-system-par"

cat > "${ROOTFS_DIR2}/bin/find-data-par" << "EOF"
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
chmod +x "${ROOTFS_DIR2}/bin/find-data-par"

cat > "${ROOTFS_DIR2}/bin/init-system" << "EOF"
#!/bin/sh
/bin/gen-fstab
mkdir -p /newinit /efi /data
mount -a
echo "Very alpha! Type command if sure: start-system"
EOF
chmod +x "${ROOTFS_DIR2}/bin/init-system"

cat > "${ROOTFS_DIR2}/bin/fix-system-fstab" << "EOF"
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
#> /etc/fstab

echo "proc            /proc           proc    defaults        0      0" >> /new_root/etc/fstab
echo "sysfs           /sys            sysfs   defaults        0      0" >> /new_root/etc/fstab
echo "devpts          /dev/pts        devpts  gid=4,mode=620  0      0" >> /new_root/etc/fstab
echo "tmpfs           /dev/shm        tmpfs   defaults        0      0" >> /new_root/etc/fstab

if [[ ! -f "/system/etc/fstab" ]]; then
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
		 echo "UUID=$uuid  /efi  EFI    defaults  0 1" >> /new_root/etc/fstab
	    elif [ "$label" = "SYSTEM" ]; then
		 echo "UUID=$uuid  /    ext4   defaults  0 1" >> /new_root/etc/fstab
	    elif [ "$label" = "DATA" ]; then
		 echo "UUID=$uuid  /data      ext4   defaults  0 2" >> /new_root/etc/fstab
	    fi
	done
fi

# End of script.
EOF
chmod +x "${ROOTFS_DIR2}/bin/fix-system-fstab"

cat > "${ROOTFS_DIR2}/bin/start-system" << "EOF"
#!/bin/sh
/bin/find-system-par
mkdir -p /new_root /efi /data
mount -a
rm /new_root/etc/fstab
/bin/fix-system-fstab
mount --move /sys /new_root/sys
mount --move /proc /new_root/proc
mount --move /dev /new_root/dev
mount --move /run /new_root/run
exec switch_root -c /dev/console /new_root /init || sh
EOF
chmod +x "${ROOTFS_DIR2}/bin/start-system"