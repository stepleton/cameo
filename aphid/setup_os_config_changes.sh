#!/bin/sh
# Apple parallel port storage emulator for Cameo
#
# Forfeited into the public domain with NO WARRANTY. Read LICENSE for details.
#
# This shell script makes various changes to operating system configuration
# files in order to improve Cameo/Aphid's compatibility and usefulness (it's
# difficult to be more specific than this!). Note that most of the effort that
# went into file has been focused on the most recent recommended OS image; some
# changes applied to that image may be appropriate for other OS images too, but
# are missing because they simply haven't been tested,
#
# This script must be run with superuser privileges.

# File listing the BeagleBoard image we're using.
ID_FILE='/ID.txt'

# Make sure we can identify which system image we're running.
if [ ! -f $ID_FILE ]; then
  echo "OS image ID file $ID_FILE is missing; giving up on trimming services."
  exit 1
fi
ID=`cat $ID_FILE`

if [ "$ID" = 'BeagleBoard.org Debian Image 2019-07-07' ]; then
  file='/opt/scripts/boot/am335x_evm.sh'
  echo "Changing USB ethernet to use NCM instead of ECM (the same change as"
  echo -n "https://github.com/RobertCNelson/boot-scripts/pull/114/commits)... "
  sed -i.bak 's/ecm.usb0/ncm.usb0/g' $file && echo 'done.' || echo 'failed!'

  echo
  echo "All done."
else
  echo "No configuration changes are specified for an OS with image ID"
  echo "   \"$ID\""
  echo "so, not making any."
fi
