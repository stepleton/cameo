# Apple parallel port storage emulator for Cameo
#
# Forfeited into the public domain with NO WARRANTY. Read LICENSE for details.
#
# This file: build "data pump" Aphid firmware for PRU 0.

CC=clpru
CFLAGS=-I.. \
       -I/usr/lib/ti/pru-software-support-package/include \
       -I/usr/lib/ti/pru-software-support-package/include/am335x \
       --endian=little --hardware_mac=on --define=am3358 --define=pru0 \
       -v3 -O2

LD=clpru
LDFLAGS=-i/usr/lib/ti/pru-software-support-package/lib \
        --define=am3358 --define=pru0 \
	--heap_size=0 --stack_size=0 --reread_libs --warn_sections


DEPS=../aphd_pru_common.h


all: aphd_pru0_datapump.fw


aphd_pru0_datapump.obj: aphd_pru0_datapump.asm $(DEPS)
	$(CC) -c $< $(CFLAGS)


aphd_pru0_resource_table.obj: aphd_pru0_resource_table.c $(DEPS)
	$(CC) -c $< $(CFLAGS)


aphd_pru0_datapump.fw: aphd_pru0_resource_table.obj aphd_pru0_datapump.obj AM335x_PRU.cmd
	$(LD) -z -o $@ $(LDFLAGS) \
	      aphd_pru0_resource_table.obj aphd_pru0_datapump.obj \
	      AM335x_PRU.cmd -llibc.a


clean:
	rm -f *.obj aphd_pru0_datapump.fw


.PHONY: clean all
