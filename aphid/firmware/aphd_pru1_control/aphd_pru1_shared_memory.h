// Aphid: Apple parallel port hard drive emulator for Cameo
//
// Forfeited into the public domain with NO WARRANTY. Read LICENSE for details.
//
// This file: firmware for PRU 1; shared memory setup.

#ifndef APHD_PRU1_SHARED_MEMORY_H_
#define APHD_PRU1_SHARED_MEMORY_H_


#include <stdint.h>


// The data pump command structure sits at the base of the shared memory region.
// PRU 1 can invoke the data pump (i.e. PRU 0) by placing values in this
// structure and sending PRU 0 an interrupt. PRU 0 will perform the operation,
// deposit a return value in the return_code field, and send an interrupt
// back to PRU 1. This invocation mechanism is automated by functions in the
// "LOW LEVEL I/O" section of aphd_pru1_control.cc.
//
// Note: for details on .command values besides 0x00 and 0x01, see documentation
// in aphd_pru0_datapump/aphd_pru0_datapump.asm.
struct __attribute__((packed)) DataPumpCommand {
  uint8_t return_code;  // Return code for the data pump operation
  uint8_t command;      // Command: 0x0: read, 0x1: write, other: see above
  uint16_t size;        // Number of bytes/words affected by the operation
  uint32_t address;     // Location of bytes/words affected by the operation
};


// After each I/O operation, PRU 0 copies updated versions of several
// accumulated performance statistics into shared memory.
struct __attribute__((packed)) DataPumpStatistics {
  // These four values total the number of bytes/words requested and
  // successfully received/emitted for reading/writing operations.
  uint32_t data_pump_read_bytes_requested;
  uint32_t data_pump_read_bytes_succeeded;
  uint32_t data_pump_write_words_requested;
  uint32_t data_pump_write_words_succeeded;
};


// When the data pump (PRU 0) sends data from shared memory to the Apple, the
// odd parity bit for each data byte must be precomputed. Data bytes and parity
// bits sit side-by-side in RAM in pairs described by this data structure. The
// sixth bit of the parity member of ByteParityPair supplies the actual value
// assigned to the \PPARITY line, but since all other bits are ignored, it's
// fine to use values like 0x00 and 0xff.
struct __attribute__((packed)) ByteParityPair {
  uint8_t data;
  uint8_t parity;

  // We need to define this in order to enable copies between ByteParityPair
  // values in shared memory.
  volatile ByteParityPair& operator=(volatile ByteParityPair& other) volatile {
    this->data = other.data;
    this->parity = other.parity;
    return *this;
  }
};


// This structure defines the layout of the shared memory space.
struct __attribute__((packed)) SharedMemory {
  // The data pump command structure; see DataPumpCommand for details.
  DataPumpCommand data_pump_command;

  // Data pump usage statistics; see DataPumpStatistics for details.
  DataPumpStatistics data_pump_statistics;

  // The most recent handshake byte from the Apple. We only need a single byte,
  // but we use two for the sake of (not strictly necessary) 16-bit alignment.
  // It just feels tidier.
  uint8_t apple_handshake[2];

  // The most recent six command bytes from the Apple.
  uint8_t apple_command[6];

  // The most recent four byte-parity pairs that encode the status information
  // that the drive returns to the Apple.
  ByteParityPair drive_status[4];

  // Whole disk sector data that the drive sends to the Apple. It's important
  // that this immediately follows drive_status.
  ByteParityPair drive_sector[532];

  // Whole disk sector data that the Apple sends to the drive.
  uint8_t apple_sector[532];

  // Often we may need to send single bytes to the Apple, or assemble short
  // sequences to send to the Apple. For this we make use of a big precomputed
  // table of bytes and parity values.
  ByteParityPair bytes_with_parity[256];

  // The remaining shared memory items are supplemental debugging data items.
  // There is no standard means of exporting these items from PRU1 to the ARM;
  // if you'd like to do it yourself, I recommend writing a program that mmaps
  // /dev/mem and starts reading from address 0x4a310000...

  // If kDebug in aphd_pru1_control.cc is true, then this word will be updated
  // with various symbols that indicate the control state machine's state.
  uint16_t control_debug_word;

  // If kDebug in aphd_pru1_control.cc is true, then this word will contain the
  // value of control_debug_word just before it was last reset at the top of the
  // state machine outer loop.
  uint16_t last_control_debug_word;

  // If kDebug in aphd_pru1_interrupt_and_buffer_handler.cc is true, then this
  // word will be updated with various symbols that indicate progress through
  // RPMsg transactions with the ARM.
  uint16_t rpmsg_debug_word;

  // If kDebug in aphd_pru1_interrupt_and_buffer_handler.cc is true, then this
  // word will contain the value of rpmsg_debug_word just before it was last
  // reset in the interrupt handler.
  uint16_t last_rpmsg_debug_word;
};


// Declare the shared memory itself.
extern volatile __far SharedMemory SHMEM;


#endif  // APHD_PRU0_SHARED_MEMORY_H_
