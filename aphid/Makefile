# Apple parallel port storage emulator for Cameo
#
# Forfeited into the public domain with NO WARRANTY. Read LICENSE for details.
#
# This file: build and install Aphid firmware, Linux-side programs, startup
# scripts, and a blank disk image. Installation locations:
#    Firmware: /lib/firmware
#    Disk emulator script and blank disk image: /usr/local/lib/cameo-aphid
#    systemd startup script: /lib/systemd/system


INSTALL_DIR=/usr/local/lib/cameo-aphid
SYSTEMD_DIR=/lib/systemd/system


all:
	$(MAKE) -C firmware
	@echo Creating empty ProFile disk image file profile.image.
	dd if=/dev/zero of=profile.image bs=5175296 count=1


clean:
	$(MAKE) -C firmware clean
	rm -f profile.image


install:
	$(MAKE) -C firmware install
	mkdir -p $(INSTALL_DIR)
	install --mode=775 profile.py $(INSTALL_DIR)
	install --backup=numbered --mode=664 profile.image $(INSTALL_DIR)
	chown -R debian:debian $(INSTALL_DIR)
	chmod -R ug+rw $(INSTALL_DIR)
	install cameo-aphid.service $(SYSTEMD_DIR)
	@echo
	@echo 'To start ProFile emulation on boot, execute:'
	@echo '    sudo systemctl enable cameo-aphid'



.PHONY: all clean install
