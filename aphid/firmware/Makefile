# Apple parallel port storage emulator for Cameo
#
# Forfeited into the public domain with NO WARRANTY. Read LICENSE for details.
#
# This file: build Aphid firmware for both PRUs.
#
# While it's recommended that you `make` the firmware as an ordinary user,
# `make install` expects to run as root so that it can install the firmware
# in /lib/firmware.

all:
	$(MAKE) -C aphd_pru0_datapump
	$(MAKE) -C aphd_pru1_control


clean:
	$(MAKE) -C aphd_pru0_datapump clean
	$(MAKE) -C aphd_pru1_control clean


install: all
	cp aphd_pru0_datapump/aphd_pru0_datapump.fw /lib/firmware
	cp aphd_pru1_control/aphd_pru1_control.fw /lib/firmware


.PHONY: all clean install
