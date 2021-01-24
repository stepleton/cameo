#!/bin/sh
# Apple parallel port storage emulator for Cameo
#
# Forfeited into the public domain with NO WARRANTY. Read LICENSE for details.
#
# This shell script disables miscellaneous bits of system functionality that
# are enabled by default on PocketBeagle system images. Trimming these items
# hastens the boot process and conserves system resources.
#
# This script must be run with superuser privileges.


# Disable initramfs by moving initrd images aside. This operation renames the
# initrd files by prepending their filenames with "DISABLED-". To re-enable
# initramfs, simply rename the files by removing this prefix.
echo -n 'Renaming initramfs images (if any) so they are not used...'
for i in /boot/initrd.img-*; do
  mv $i `echo $i | sed 's|^/boot/|/boot/DISABLED-|'`
done
echo ' done'
