#!/bin/sh
# Apple parallel port storage emulator for Cameo
#
# Forfeited into the public domain with NO WARRANTY. Read LICENSE for details.
#
# This shell script disables a variety of system services that are enabled
# by default on PocketBeagle system images. Trimming these images shaves
# around a dozen seconds off of the boot time and cuts back on the number of
# processes that could be writing to disk---handy if we are keeping root
# filesystem changes in RAM via overlayfs.
#
# This script must be run with superuser privileges.

# File listing the BeagleBoard image we're using.
ID_FILE='/ID.txt'

# We disable these systemd entities for the 2018-08-30 image:
DISABLE_20180830="\
    apache2.service \
    atd.service \
    avahi-daemon.service \
    bb-wl18xx-bluetooth.service \
    bb-wl18xx-wlan0.service \
    bluetooth.service \
    bonescript-autorun.service \
    console-setup.service \
    cron.service \
    keyboard-setup.service \
    pppd-dns.service \
    rc_battery_monitor.service \
    robotcontrol.service \
    rsync.service \
    rsyslog.service \
    serial-getty@.service \
    systemd-timesyncd.service \
    apt-daily-upgrade.timer \
    apt-daily.timer"

# Lists of systemd entities to disable in other images should be placed here.


# This function disables each systemd entity listed in its arguments, exiting
# early if any entity is not successfully disabled.
disable_systemd_entities()
{
  for i in $@; do
    echo -n "Disabling $i..."
    if systemctl -q disable $i; then
      echo ' done.'
    else
      echo ' FAILED. Giving up.'
      exit 1
    fi
  done
}


# Make sure we can identify which system image we're running.
if [ ! -f $ID_FILE ]; then
  echo "OS image ID file $ID_FILE is missing; giving up on trimming services."
  exit 1
fi
ID=`cat $ID_FILE`

if [ "$ID" = 'BeagleBoard.org Debian Image 2018-08-30' ]; then
  disable_systemd_entities $DISABLE_20180830
# elif a different image...
else
  echo "I don't know how to trim services for an OS with image ID"
  echo "   \"$ID\""
  echo "so, giving up."
  exit 1
fi
