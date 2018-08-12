# Apple parallel port storage emulator for Cameo
#
# Forfeited into the public domain with NO WARRANTY. Read LICENSE for details.
#
# This file: build "control" Aphid firmware for PRU 1.

CC=clpru

CC=clpru
CFLAGS=-I. -I.. \
       -I/usr/lib/ti/pru-software-support-package/include \
       -I/usr/lib/ti/pru-software-support-package/include/am335x \
       --endian=little --hardware_mac=on --define=am3358 --define=pru0 \
       -v3 -O2

LD=clpru
LDFLAGS=-i/usr/lib/ti/pru-software-support-package/lib \
        --define=am3358 --define=pru0 \
	--heap_size=0 --stack_size=0 --reread_libs --warn_sections


DEPS=../aphd_pru_common.h \
     aphd_pru1_data_bytes_with_parity.h \
     aphd_pru1_data_drive_sector.h \
     aphd_pru1_interrupt_and_buffer_handler.h \
     aphd_pru1_resource_table.h \
     aphd_pru1_rpmsg.h \
     aphd_pru1_shared_memory.h


all: aphd_pru1_control.fw


aphd_pru1_control.obj: aphd_pru1_control.cc $(DEPS)
	$(CC) -c $< $(CFLAGS)


aphd_pru1_interrupt_and_buffer_handler.obj: aphd_pru1_interrupt_and_buffer_handler.cc $(DEPS)
	$(CC) -c $< $(CFLAGS)


aphd_pru1_resource_table.obj: aphd_pru1_resource_table.c $(DEPS)
	$(CC) -c $< $(CFLAGS)


aphd_pru1_rpmsg.obj: aphd_pru1_rpmsg.c $(DEPS)
	$(CC) -c $< $(CFLAGS)


aphd_pru1_shared_memory.obj: aphd_pru1_shared_memory.cc $(DEPS)
	$(CC) -c $< $(CFLAGS)


aphd_pru1_control.fw: aphd_pru1_control.obj aphd_pru1_interrupt_and_buffer_handler.obj aphd_pru1_resource_table.obj aphd_pru1_rpmsg.obj aphd_pru1_shared_memory.obj
	$(LD) -z -o $@ $(LDFLAGS) \
	      aphd_pru1_control.obj \
	      aphd_pru1_interrupt_and_buffer_handler.obj \
	      aphd_pru1_resource_table.obj \
	      aphd_pru1_rpmsg.obj \
	      aphd_pru1_shared_memory.obj \
	      AM335x_PRU.cmd -llibc.a -lrpmsg_lib.lib


clean:
	rm -f *.obj aphd_pru1_control.fw


.PHONY: clean all
