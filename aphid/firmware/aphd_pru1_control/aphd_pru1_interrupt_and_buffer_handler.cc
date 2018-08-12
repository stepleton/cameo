// Aphid: Apple parallel port hard drive emulator for Cameo
//
// Forfeited into the public domain with NO WARRANTY. Read LICENSE for details.
//
// This file: firmware for PRU 1; interrupt and RPMsg buffer handling.

#include <algorithm>
#include <stdint.h>
#include <string.h>

#include <pru_intc.h>

#include "aphd_pru_common.h"
#include "aphd_pru1_interrupt_and_buffer_handler.h"
#include "aphd_pru1_rpmsg.h"
#include "aphd_pru1_shared_memory.h"


//// CONSTANTS ////


// Set to true to enable various debug features that will slow execution.
// These features are:
// 1. Update (last_)rpmsg_debug_word in the shared memory region with various
//    bits of debug information (mainly: progress in RPMsg transactions).
static const bool kDebug = 1;


// Size of the RPMsg header. The PRU RPMsg library has only RPMSG_BUF_SIZE
// bytes available for messages, and it uses this many of those bytes for
// a header structure. Our data has to fit in what's left over, so we use
// this constant (which must be kept up to date) to do the arithmetic we
// need to avoid buffer overflows.
const size_t kRpmsgHeaderSize = 16;


//// ARM COMMAND SETUP ////


// The following command constants are made from "unusual" values, as
// determined from a survey of about seven images of ProFile and Widget disks
// containing installations of the Lisa Office System or the Lisa Pascal
// Workshop. Not only were these values never observed on these images, no
// ordered pair of adjacent bytes (e.g. $73, $93 in kCommandGoAhead) in the
// constants were ever observed to occur. (Note: little-endian byte ordering
// for uint32 is assumed here.)
//
// In this way, these constants assume the dual role of "magic number" and
// command signifier. We hope framing the communication between the ARM and
// PRU1 won't be that difficult, but it can't hurt to be careful.

// The ARM wants to retrieve data from the Apple sector buffer.
const uint32_t kCommandGetAppleSectorData = 0xf137a98cU;

// The ARM wants to put data into the drive sector buffer.
const uint32_t kCommandPutDriveSectorData = 0xc74b95dbU;

// The ARM wants a 16-bit checksum of the data in the drive sector buffer.
const uint32_t kCommandChecksumDriveSectorData = 0xa35bb99dU;

// The ARM is done fiddling with buffers and the PRU can stop waiting on it.
const uint32_t kCommandGoAhead = 0xea7393a6U;


// A data structure for data transfer commands. All RPMsg messages from the ARM
// will be prefixed with one of these structures.
struct __attribute__((packed)) ArmCommand {
  // One of the kCommand* values above.
  uint32_t command;

  // Where in the buffer should getting or putting begin?
  // Out-of-bounds start addresses will cause 0-byte gets and ignored puts.
  uint16_t start_byte;

  // How many bytes should be got from or put into the buffer?
  // - Byte counts that extend beyond the ends of buffers cause whatever
  //   truncation is necessary to avoid reading/writing beyond buffer ends.
  // - For puts, if a byte count exceeds 488 (the size of the `data` buffer
  //   below), the count will be truncated.
  // - For gets, if a byte count exceeds 496 (the size of the largest RPMsg
  //   message less the size of the RPMsg header), the count will be truncated.
  uint16_t length_bytes;

  // Data that a put command would like to store in the drive sector buffer.
  // Note use of ByteParityPairs---the ARM should compute parity for all the
  // data it wishes to send to the Apple.
  ByteParityPair data[
      (RPMSG_BUFFER_SIZE -
       kRpmsgHeaderSize -
       8 /* Size of the above fields. */) / sizeof(ByteParityPair)];
};


// The one ArmCommand structure we care about is deemed to occupy the RPMsg
// buffer defined in aphd_pru1_rpmsg.cc.
ArmCommand* ARM_COMMAND = reinterpret_cast<ArmCommand*>(&RPMSG_BUFFER);


//// INTERRUPT HANDLING ////


// Predeclarations.
bool handle_get_apple_sector_data_command();
bool handle_put_drive_sector_data_command(uint16_t length);
bool handle_checksum_drive_sector_data_command();


// Handle an R31 bit 31 interrupt.
//
// (Details in header file.)
InterruptMeaning handle_interrupt() {
  // An interrupt from PRU0? We essentially turn it over to the caller.
  if ((CT_INTC.SECR0 & (1 << ePRU0to1)) != 0) {
    CT_INTC.SECR0 = (1 << ePRU0to1);  // Clear this interrupt
    return kImPru0;                   // Tell caller to handle it
  }

  // An interrupt from the ARM? These we try to handle.
  if ((CT_INTC.SECR0 & (1 << eARMtoPRU1)) != 0) {
              if (kDebug) SHMEM.last_rpmsg_debug_word = SHMEM.rpmsg_debug_word;
                                   if (kDebug) SHMEM.rpmsg_debug_word = 0x0000;
    // 0. By default, we say we handled the interrupt.
    InterruptMeaning result = kImArmHandled;

    // 1. Zero out the command field in the ARM_COMMAND structure, since this
    // is one of the things we check to make sure we're reading the ARM's
    // message correctly.
    ARM_COMMAND->command = 0U;

    // 2. Read in data from the ARM. If it was too little data to contain a
    // meaningful command structure, ignore it.
    uint16_t received = aphd_pru1_rpmsg_receive();
                                   if (kDebug) SHMEM.rpmsg_debug_word = 0x0100;
    if (received >= 8) {
                                   if (kDebug) SHMEM.rpmsg_debug_word = 0x0200;
      // 3a. If the magic bytes at the beginning are the "go ahead" command,
      // return the "Proceed" symbol so that the PRU can get on with it.
      if (ARM_COMMAND->command == kCommandGoAhead) {
                                   if (kDebug) SHMEM.rpmsg_debug_word = 0x0300;
        result = kImArmProceed;             // Tell caller to get on with it
      }

      // 3b. Or, send data to the ARM from the Apple sector buffer.
      else if (ARM_COMMAND->command == kCommandGetAppleSectorData) {
                                   if (kDebug) SHMEM.rpmsg_debug_word = 0x0400;
        if (!handle_get_apple_sector_data_command()) {
                                   if (kDebug) SHMEM.rpmsg_debug_word = 0x0499;
          result = kImArmFailedToHandle;
        }
      }

      // 3c. Or, receive data from the ARM into the drive sector buffer.
      else if (ARM_COMMAND->command == kCommandPutDriveSectorData) {
                                   if (kDebug) SHMEM.rpmsg_debug_word = 0x0500;
        if (!handle_put_drive_sector_data_command(received)) {
                                   if (kDebug) SHMEM.rpmsg_debug_word = 0x0599;
          result = kImArmFailedToHandle;
        }
      }

      // 3d. Or, compute a checksum of the drive sector data.
      else if (ARM_COMMAND->command == kCommandChecksumDriveSectorData) {
                                   if (kDebug) SHMEM.rpmsg_debug_word = 0x0600;
        if (!handle_checksum_drive_sector_data_command()) {
                                   if (kDebug) SHMEM.rpmsg_debug_word = 0x0699;
          result = kImArmFailedToHandle;
        }
      }
    }

    CT_INTC.SECR0 = (1 << eARMtoPRU1);    // Clear the interrupt
                                  if (kDebug) SHMEM.rpmsg_debug_word |= 0x1000;
    return result;                        // Report whether we handled it
  }

  // No interrupt we know how to handle was handled.
  return kImNone;
}


// Handle a "get Apple sector" command from the ARM.
//
// This command allows the ARM to retrieve a portion of the apple_sector buffer
// in SHMEM (the shared memory space). The sector data will not fit in a single
// RPMsg transaction, so the ARM will issue multiple commands to retreive the
// entire sector, each command specifying a different range within the buffer.
// Invalid range values are dealt with as described in comments on ArmCommand.
//
// After parsing the command, this function supplies the requested data to the
// ARM in an RPMsg message.
//
// Returns:
//   true iff the command was successfully handled.
bool handle_get_apple_sector_data_command() {
  const int32_t start_index = std::min(
      static_cast<int32_t>(ARM_COMMAND->start_byte),
      static_cast<int32_t>(sizeof(SHMEM.apple_sector)));
  const int32_t end_index = std::min(
      start_index + static_cast<int32_t>(ARM_COMMAND->length_bytes),
      static_cast<int32_t>(sizeof(SHMEM.apple_sector)));

  uint8_t* buffer = const_cast<uint8_t*>(SHMEM.apple_sector);
  const int32_t true_length = std::max(end_index - start_index, 0);

  // Try five times to send the sector, I guess. Return true iff one of the
  // attempts succeeds.
  for (int i = 0; i < 5; ++i) {
                                          if (kDebug) SHMEM.rpmsg_debug_word++;
    if (aphd_pru1_rpmsg_send(buffer + start_index, true_length) == 0) {
      return true;
    }
  }
  return false;
}


// Handle a "put drive sector" command from the ARM.
//
// This command allows the ARM to place data into the drive_sector buffer in
// SHMEM (the shared memory space). The sector data will not fit in a single
// RPMsg transaction, so the ARM will issue multiple commands to upload the
// entire sector, each command specifying a different range within the buffer.
// Invalid range values are dealt with as described in comments on ArmCommand.
//
// Returns:
//   true iff the command was successfully handled.
bool handle_put_drive_sector_data_command(uint16_t received) {
  // Even though SHMEM.drive_sector holds two-byte ByteParityPair values, these
  // indices are in bytes.
  const int32_t start_index = std::min(
      static_cast<int32_t>(ARM_COMMAND->start_byte),
      static_cast<int32_t>(sizeof(SHMEM.drive_sector)));
  const int32_t end_index = std::min(
      start_index + static_cast<int32_t>(ARM_COMMAND->length_bytes),
      static_cast<int32_t>(sizeof(SHMEM.drive_sector)));

  // Determine whether we have received enough data to copy into the drive
  // sector buffer as requested. Note that since the amount of data received
  // can never overflow the .data field of ARM_COMMAND (due to RPMsg message
  // size limitations), we never have to worry about checking whether
  // length_bytes exceeds the size of the .data field---if it did, we'd fail
  // the following check anyway.
  const int32_t true_length = std::max(end_index - start_index, 0);
  if ((received - offsetof(ArmCommand, data)) < true_length) {
    return false; // Not enough data received!
  }

  // We do, so perform the copy.
                                   if (kDebug) SHMEM.rpmsg_debug_word = 0x0501;
  void* src_buffer = const_cast<ByteParityPair*>(ARM_COMMAND->data);
  uint8_t* dest_buffer = reinterpret_cast<uint8_t*>(  // a bit embarrassing.
      const_cast<ByteParityPair*>(SHMEM.drive_sector));
  memcpy(dest_buffer + start_index, src_buffer, true_length);

  // Success!
  return true;
}


// Handle a "get drive sector checksum" command from the ARM.
//
// To confirm that sector data has been successfully transferred between the
// ARM and `SHMEM.drive_sector`, the ARM may request a 16-bit checksum of this
// shared memory region.
//
// After initialising the checksum at 0, the checksum computation iterates
// through each byte in `SHMEM.drive_sector`, doing the following:
//   - adde the current byte to the checksum,
//   - rotate the checksum one bit to the left.
// When finished, this function supplies the checksum to the ARM in an RPMsg
// message as a two-byte little-endian unsigned integer.//
// Returns:
//   true iff the command was successfully handled.

//
// Returns:
//   true iff the command was successfully handled.
bool handle_checksum_drive_sector_data_command() {
  // Compute the checksum. For each byte in the drive sector:
  //   1. Add the byte to the checksum.
  //   2. Rotate the checksum left one bit.
  uint16_t checksum = 0U;
  uint8_t* runner = reinterpret_cast<uint8_t*>(  // a bit embarrassing.
      const_cast<ByteParityPair*>(SHMEM.drive_sector));
  for (uint16_t i = 0; i < sizeof(SHMEM.drive_sector); ++i) {
    // Add next byte to the checksum.
    checksum += *runner++;
    // Rotate the checksum left one bit. Hope the compiler optimises this!
    uint16_t carry = (checksum & 0x8000) >> 15;
    checksum = checksum << 1 + carry;
  }

  // Attempt five times to send the checksum to the ARM.
  for (int i = 0; i < 5; ++i) {
                                          if (kDebug) SHMEM.rpmsg_debug_word++;
    if (aphd_pru1_rpmsg_send(&checksum, sizeof(checksum)) == 0) return true;
  }
  return false;
}
