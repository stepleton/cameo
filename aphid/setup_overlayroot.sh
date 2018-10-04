#!/bin/sh
# Apple parallel port storage emulator for Cameo
#
# Forfeited into the public domain with NO WARRANTY. Read LICENSE for details.
#
# This shell script enables overlayroot filesystem protection for the root
# filesystem---the last step in setting up your Cameo/Aphid stack as an
# embedded appliance. With this option enabled, no changes to the root
# filesystem will be saved to the MicroSD card---instead, changes are only
# saved to RAM and will be lost whenever the PocketBeagle is shut down or
# rebooted. Cameo/Aphid drive images must reside on a second disk partition
# that does not have overlayroot protection; the setup_dos_partition* scripts
# prepare such a partition for you.
#
# Before running this script, you should have run all of the other setup
# scripts and completed the installation of the Cameo/Aphid software.
#
# This script must be run with superuser privileges.
#
#  XXX   XXX   XXX   XXX   XXX   XXX   XXX   XXX   XXX   XXX   XXX   XXX
# THIS SCRIPT MAKES FURTHER CHANGES IMPOSSIBLE. NO "UNDO" ACTION IS PROVIDED!
#  XXX   XXX   XXX   XXX   XXX   XXX   XXX   XXX   XXX   XXX   XXX   XXX

#### CONFIGURATION ####

MOUNT_POINT='/usr/local/lib/cameo-aphid'  # The Aphid images directory.
OVERLAY_CONF='/etc/overlayroot.conf'      # OverlayFS config file.


#### SAFETY CHECKS ####

# Stop if overlayfs isn't installed---it's only been available on the
# BeagleBoard image since the 2018-08-30 release.
if [ ! -e $OVERLAY_CONF ]; then
  echo "It looks like overlayfs capability isn't available on this "
  echo 'PocketBeagle system software image. Giving up.'
  exit 1
fi

# Stop if there's no secondary partition for Cameo/Aphid drive images.
if ! findmnt $MOUNT_POINT > /dev/null; then
  echo "It looks like $MOUNT_POINT does not reside on a secondary"
  echo 'filesystem, which overlayfs requires (otherwise writes to an emulated '
  echo 'ProFile will not be saved once Cameo/Aphid is powered down). Make sure '
  echo 'to run the setup_dos_partition* scripts before running this script.'
  echo 'Giving up.'
  exit 1
fi

# Stop if no Cameo/Aphid software is installed 
if ! systemctl status cameo-aphid 2>/dev/null | grep -q active ; then
  echo 'It looks like the Cameo/Aphid system service is not enabled. Once'
  echo 'overlayfs is active, it will not be very easy to enable it. Please'
  echo "install the Cameo/Aphid system software if you haven't yet."
  echo 'Giving up.'
  exit 1
fi

# Stop if overlayfs is already enabled.
if ! grep -v '^#' $OVERLAY_CONF | grep -q '^overlayroot=""$'; then
  echo 'It looks like overlayfs is already enabled on this PocketBeagle.'
  echo 'Giving up.'
  exit 1
fi
# At last. It looks like we're ready to go.


#### MAKING CHANGES ####

SED_COMMAND='s/^overlayroot=""$/overlayroot="tmpfs:recurse=0"/'
echo -n "Modifying overlayfs configuration in ${OVERLAY_CONF}..."
if sed -i.orig "$SED_COMMAND" $OVERLAY_CONF; then
  echo ' done.'
  echo
  echo 'NOTE: On the next boot, overlayfs will be enabled, with no easy way to'
  echo 'disable it. The root filesystem will be locked in its current state.'
  echo 'Your last chance to back out of this change is now, with this command:'
  echo
  echo "  mv ${OVERLAY_CONF}.orig $OVERLAY_CONF"
  echo
  echo "Otherwise, if you're happy to enable overlayfs, reboot now."
else
  echo ' FAILED.'
  echo 'Do you have superuser privileges? Giving up.'
  exit 1
fi
