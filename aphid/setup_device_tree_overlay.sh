#!/bin/sh
# Apple parallel port storage emulator for Cameo
#
# Forfeited into the public domain with NO WARRANTY. Read LICENSE for details.
#
# This shell script changes the boot configuration in /boot/uEnv.txt to load
# the Cameo/Aphid device tree overlay, which should have been installed in
# /lib/firmware when you ran `make install`.
#
# Bad modifications to /boot/uEnv.txt can result in an unbootable PocketBeagle
# (although since the microSD card can be removed, it's not the worst thing in
# the world). This script is therefore very conservative in making changes to
# this file and will abort if it detects anything out of the ordinary.
#
# This script must be run with superuser privileges.

# The file we're modifying
UENV_FILE='/boot/uEnv.txt'
# The device tree overlay file we'd like to load on boot
DTBO_FILE='/lib/firmware/PB-CAMEO-APHID.dtbo'
# The suffix for backups of $UENV_FILE
BACKUP_SUFFIX='.bak.no_cameo_aphid_dtbo'

# Here is the modification itself: we want to enable a specific key-value pair
# in the file (but we want to be careful that the user hasn't already done it).
TARGET_PARAMETER='uboot_overlay_addr4'
TARGET_ORIGINAL="#${TARGET_PARAMETER}=/lib/firmware/<file4>.dtbo"
TARGET_MODIFIED="${TARGET_PARAMETER}=${DTBO_FILE}"


# Generic failure message.
fail()
{
  echo "Giving up on setting up the Cameo/Aphid device tree overlay."
  exit 1
}


# Make sure the files that are important to this script exist.
if [ ! -f $UENV_FILE ]; then
  echo "The boot configuration file $UENV_FILE is missing."
  fail
fi
if [ ! -f $DTBO_FILE ]; then
  echo "The compiled device tree overlay file $DTBO_FILE is missing."
  fail
fi

# Make sure that the string we wish to modify can be found in the file.
if ! grep -q "^${TARGET_ORIGINAL}$" $UENV_FILE; then
  echo "The boot configuration file $UENV_FILE doesn't contain the line we know"
  echo "how to modify."
  fail
fi
# But also make sure that the parameter hasn't already been specified in the
# file for some other cape (and whoever did that is just leaving the original
# commented line around).
if grep -q "^${TARGET_PARAMETER}=" $UENV_FILE; then
  echo "The boot configuration file $UENV_FILE has a line that's already using"
  echo "the parameter we'd like to use: ${TARGET_PARAMETER}."
  fail
fi

# Okay, we're finally ready to give it a shot.
echo -n "Modifying ${UENV_FILE}... "
sed_command="s|^${TARGET_ORIGINAL}$|${TARGET_MODIFIED}|"
if sed "-i${BACKUP_SUFFIX}" -e "${sed_command}" $UENV_FILE; then
  echo "success."
else
  echo "failure."
fi
echo "Look for a backup of the original file in ${UENV_FILE}${BACKUP_SUFFIX}."
