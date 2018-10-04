#!/bin/sh
# Apple parallel port storage emulator for Cameo
#
# Forfeited into the public domain with NO WARRANTY. Read LICENSE for details.
#
# Together with setup_dos_partition_part2.sh, this shell script puts a fat32
# partition in spare space on your MicroSD card, establishes a mount point for
# it, and modifies /etc/fstab to mount the partition automatically. Usage:
#
#    setup_dos_partition_part2.sh
#
# This script continues the setup process that setup_dos_partition_part1.sh
# begins. Before running this script, you should have run that script and
# rebooted your PocketBeagle.
#
# This script must be run with superuser privileges.

#### CONFIGURATION ####

DEVICE='/dev/mmcblk0'                     # Should be the SD card.
MOUNT_POINT='/usr/local/lib/cameo-aphid'  # The Aphid images directory.


#### SAFETY CHECKS #####

# Check for the presence of the file that indicates that we're picking up where
# we left off from the previous script.
if [ ! -e "$MOUNT_POINT/ready_to_run_setup_dos_partition_part2" ]; then
  echo "It looks like setup_dos_partition_part1.sh wasn't run successfully"
  echo 'just before now. If you believe it was, and would like this script to'
  echo 'proceed as if it did, run the following command:'
  echo
  echo "  touch $MOUNT_POINT/ready_to_run_setup_dos_partition_part2"
  echo
  echo 'then try this script again.'
  echo 'Giving up.'
  exit 1
fi

# Stop if the DOS partition is already mountable.
if findmnt $MOUNT_POINT > /dev/null; then
  echo "It looks like $MOUNT_POINT is already a filesystem that this "
  echo 'PocketBeagle can mount. Giving up.'
  exit 1
fi

# Stop if the device already has a second partition. Ths won't work if the user
# hasn't got privileges, but the next check will fail in that case.
if ! sfdisk -l -q "${DEVICE}p2" 2>/dev/null; then
  echo 'The partition that setup_dos_partition_part1.sh should have made on'
  echo "$DEVICE does not appear to exist; giving up."
  exit 1
fi


#### MAKING CHANGES ####

# Delete the sentinel file.
rm -f "$MOUNT_POINT/ready_to_run_setup_dos_partition_part2"

# Format the new partition.
echo -n 'Formatting the new partition...'
if mkfs.vfat -n 'CAMEO_APHID' "${DEVICE}p2" > /dev/null; then
  echo ' done.'
else
  echo ' FAILED. Giving up.'
  exit 1
fi

# Add the partition to /etc/fstab.
FSTAB="${DEVICE}p2\
  $MOUNT_POINT\
  vfat\
  rw,exec,nodev,check=strict,flush,umask=000\
  0  2"
echo -n 'Adding the new partition to /etc/fstab...'
if echo "$FSTAB" >> /etc/fstab; then
  echo ' done.'
else
  echo ' FAILED. Giving up.'
  exit 1
fi

# Lastly, mount the partition.
echo -n "Mounting the new partition at $MOUNT_POINT..."
if mount --target $MOUNT_POINT; then
  echo ' done.'
  echo 'Partition setup complete.'
else
  echo ' FAILED. Giving up.'
  exit 1
fi
