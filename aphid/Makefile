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
	gunzip - < selector/selector.image.zip > profile.image
	$(MAKE) -C firmware


clean:
	$(MAKE) -C firmware clean
	rm -f profile.image


install:
	$(MAKE) -C firmware install
	mkdir -p $(INSTALL_DIR)
	install --mode=775 profile.py $(INSTALL_DIR)
	install --mode=664 profile_plugin_FFFEFD_system_info.py $(INSTALL_DIR)
	install --mode=664 profile_plugin_FFFEFE_filesystem_ops.py $(INSTALL_DIR)
	install --mode=664 profile_plugin_FFFEFF_key_value_store.py $(INSTALL_DIR)
	install --mode=664 profile_plugins.py $(INSTALL_DIR)
	install --backup=numbered --mode=664 profile.image $(INSTALL_DIR)
	chown -R debian:debian $(INSTALL_DIR) | true  # Ignore error: dir may be
	chmod -R ug+rw $(INSTALL_DIR) | true          # on another filesystem.
	install --mode=644 cameo-aphid.service $(SYSTEMD_DIR)
	@echo
	@echo 'To start ProFile emulation on boot, execute:'
	@echo '    sudo systemctl enable cameo-aphid'



.PHONY: all clean install
