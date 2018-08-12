// Aphid: Apple parallel port hard drive emulator for Cameo
//
// Forfeited into the public domain with NO WARRANTY. Read LICENSE for details.
//
// This file: firmware for PRU 1; shared memory setup.


#include "aphd_pru1_shared_memory.h"

// This defines a shared memory structure that starts at the beginning of the
// PRU shared memory space. We also initialise the bytes_with_parity table that
// it holds, as well as the drive_sector table (originally for testing, but it
// can't hurt to have something besides zeros there regardless) and the debug
// word. The other elements are basically left uninitialised.
#pragma DATA_SECTION(".shmem")
volatile __far SharedMemory SHMEM = {
    /* data_pump_command: */ {},
    /* data_pump_statistics: */ {},
    /* apple_handshake: */ {},
    /* apple_command: */ {},
    /* drive_status: */ {},
    /* drive_sector: */ {
#include <aphd_pru1_data_drive_sector.h>
    },
    /* apple_sector: */ {},
    /* bytes_with_parity: */ {
#include <aphd_pru1_data_bytes_with_parity.h>
    },
    /* control_debug_word: */ 0xffff,
    /* last_control_debug_word: */ 0xfdfd,
    /* rpmsg_debug_word: */ 0xffff,
    /* last_rpmsg_debug_word: */ 0xfdfd,
};
