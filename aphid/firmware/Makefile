# Apple parallel port storage emulator for Cameo
#
# Forfeited into the public domain with NO WARRANTY. Read LICENSE for details.
#
# This file: build Aphid firmware for both PRUs.
#
# While it's recommended that you `make` the firmware as an ordinary user,
# `make install` expects to run as root so that it can install the firmware
# in /lib/firmware.


INSTALL_DIR=/lib/firmware


all: PB-CAMEO-APHID.dtbo
	$(MAKE) -C aphd_pru0_datapump
	$(MAKE) -C aphd_pru1_control


clean:
	$(MAKE) -C aphd_pru0_datapump clean
	$(MAKE) -C aphd_pru1_control clean


install: all
	install --mode=644 \
		aphd_pru0_datapump/aphd_pru0_datapump.fw $(INSTALL_DIR)
	install --mode=644 \
		aphd_pru1_control/aphd_pru1_control.fw $(INSTALL_DIR)
	install --mode=644 --backup=numbered -T \
		aphd_pru0_datapump/aphd_pru0_datapump.fw \
		$(INSTALL_DIR)/am335x-pru0-fw
	install --mode=644 --backup=numbered -T \
		aphd_pru1_control/aphd_pru1_control.fw \
		$(INSTALL_DIR)/am335x-pru1-fw
	install --mode=644 \
		aphd_pru1_control/aphd_pru1_control.fw $(INSTALL_DIR)
	install --mode=644 \
		PB-CAMEO-APHID.dtbo $(INSTALL_DIR)


PB-CAMEO-APHID.preprocessed.dts: PB-CAMEO-APHID.dts
	cpp -I/opt/source/bb.org-overlays/include $< -P -o $@


PB-CAMEO-APHID.dtbo: PB-CAMEO-APHID.preprocessed.dts
	dtc -@ -I dts -O dtb -o $@ $<


.PHONY: all clean install
