#!/bin/sh
# Apple parallel port storage emulator for Cameo
#
# Forfeited into the public domain with NO WARRANTY. Read LICENSE for details.
#
# Together with setup_dos_partition_part2.sh, this shell script puts a fat32
# partition in spare space on your microSD card, establishes a mount point for
# it, and modifies /etc/fstab to mount the partition automatically. Usage:
#
#    setup_dos_partition_part1.sh <size>
#
# where <size> is an optional size in bytes. The actual partition size that
# this script will use will be this value rounded down to the nearest multiple
# of 512. If no size is specified, a 512 MB partition size is assumed.
#
# This script must be run with superuser privileges.
#
#  XXX   XXX   XXX   XXX   XXX   XXX   XXX   XXX   XXX   XXX   XXX   XXX
# THIS SCRIPT MODIFIES YOUR PARTITION TABLE. NO "UNDO" ACTION IS PROVIDED!
#  XXX   XXX   XXX   XXX   XXX   XXX   XXX   XXX   XXX   XXX   XXX   XXX

#### CONFIGURATION ####

DEVICE='/dev/mmcblk0'                          # Should be the SD card.
PARTITION_SIZE=`expr "${1:-536870912}" / 512`  # 512 MB by default; in sectors.
MOUNT_POINT='/usr/local/lib/cameo-aphid'       # The Aphid images directory.


#### SAFETY CHECKS AND INFO GATHERING ####

# Stop if we've already got this partition.
if findmnt $MOUNT_POINT > /dev/null; then
  echo "It looks like $MOUNT_POINT is already a filesystem that this"
  echo 'PocketBeagle can mount. Giving up.'
  exit 1
fi

# Stop if we've already got a directory at $MOUNT_POINT.
if [ -e $MOUNT_POINT ]; then
  echo "It looks like $MOUNT_POINT is already a file or directory. Giving up."
  exit 1
fi

# Stop if the device already has a second partition. Ths won't work if the user
# hasn't got privileges, but the next check will fail in that case.
if sfdisk -l "${DEVICE}p2" 2>/dev/null; then
  echo "A second partition already exists on $DEVICE; giving up."
  exit 1
fi

# Get the starting address and the amount of free space. All units are sectors.
FREE_START=`sfdisk -F $DEVICE | awk 'END{print $1}'`
FREE_SIZE=`sfdisk -F $DEVICE | awk 'END{print $3}'`
if [ -z "$FREE_START" -o -z "$FREE_SIZE" ]; then
  echo "Couldn't find the start or size of free space beyond the last"
  echo "partition on $DEVICE; giving up. (Try again as root?)"
  exit 1
fi

# Quit if there isn't enough free space left.
if [ "$PARTITION_SIZE" -gt "$FREE_SIZE" ]; then
  echo "Not enough room on $DEVICE to add a partition with $PARTITION_SIZE "
  echo "sectors; only $FREE_SIZE sectors remain beyond the last partition."
  echo "Giving up."
  exit 1
fi


#### MAKING CHANGES ####

# Create the mount point.
echo -n "Creating mount point at $MOUNT_POINT..."
if mkdir -p $MOUNT_POINT; then
  chown debian:debian $MOUNT_POINT  # While we're at it, let's assign friendly
  chmod ug+rw $MOUNT_POINT          # ownership and permissions.
  echo ' done.'
else
  echo ' FAILED. Giving up.'
  exit 1
fi

# Add the new partition. Hang on to your hat...
echo
echo "[[ Creating a new ${PARTITION_SIZE}-sector partition ]]"
echo "------------------------------------------------------------------------"
PARTITION="${DEVICE}p2 : start=$FREE_START, size=$PARTITION_SIZE, type=c"
echo $PARTITION | sfdisk $DEVICE -a --no-reread
SFDISK_RESULT="$?"
# Now touch a file inside the mount point to indicate that we're ready to run
# part 2 of the script.
touch "$MOUNT_POINT/ready_to_run_setup_dos_partition_part2"
echo "------------------------------------------------------------------------"
if [ "$SFDISK_RESULT" -eq "0" ]; then
  echo '[[ Done ]]'
  echo
  echo 'Warnings about being unable to refresh the partition table are normal.'
  echo 'Please reboot the PocketBeagle and run setup_dos_partition_part2.sh'
  echo 'with superuser privileges.'
else
  echo '[[ FAILED. Giving up. Apologies and best of luck. ]]'
  exit 1
fi
