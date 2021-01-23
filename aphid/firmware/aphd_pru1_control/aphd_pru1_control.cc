// Aphid: Apple parallel port hard drive emulator for Cameo
//
// Forfeited into the public domain with NO WARRANTY. Read LICENSE for details.
//
// This file: firmware for PRU 1; main program
//
// PRU 1 is the "control processor" in charge of data exchange with the ARM and
// parallel port handshaking. PRU 1 handles the \PCMD, \PBSY, and PR/\W signal
// lines directly, but issues commands to PRU 0 (the "data pump") to move data
// in and out over the data lines whilst handling \PSTRB and \PPARITY.


#include <stdint.h>

#include <pru_cfg.h>
#include <pru_intc.h>

#include "aphd_pru_common.h"
#include "aphd_pru1_interrupt_and_buffer_handler.h"
#include "aphd_pru1_rpmsg.h"
#include "aphd_pru1_shared_memory.h"


/////////////////////
//// FRONTMATTER ////
/////////////////////


//// CONFIGURATION ////


// An "armless" PRU 1 firmware does not request the ARM to copy data into or
// out of the buffers on reads or writes. The firmware is still capable of
// responding to buffer manipulation commands from the ARM, but it does not
// report to the ARM any commands received from the Apple.
#undef ARMLESS_MODE


// Set to true to enable various debug features that will slow execution.
// These features are:
// 1. Update (last_)control_debug_word in the shared memory region with various
//    bits of debug information (mainly: state machine state).
static const bool kDebug = true;


// This firmware has numerous loops where it waits on signal line changes,
// information from the ARM, and so forth. It shouldn't wait forever for these
// things to happen, so if this many iterations of the polling loop go past,
// it will eventually give up and wait for a new transaction. The particulars
// of each loop determine how long this many iterations will be in practice;
// suffice it to say, this value aims to be "a while" without being "too long".
//
// Certain loops multiply this value by 4; take care that the multiply would
// not overflow uint32.
static const uint32_t kTimeout = 0x10000000U;


//// REGISTER SETUP ////


// Built-in symbols used for PRU GPIO pin access and interrupt handling.
extern "C" {
volatile register uint32_t __R30;
volatile register uint32_t __R31;
}  // extern "C"

// GPIO output enable control register. Usually PRU0 will set this itself; we
// use it only to throw data pins back into input mode in SendBytesWithParity*.
uint32_t volatile * const GPIO_OE =
    reinterpret_cast<uint32_t*>(0x481ae134U);

// GPIO data in register. Usually PRU0 will handle nearly all dealings with
// the data bus, but occasionally we need to spy on it ourselves.
uint32_t volatile * const GPIO_DATAIN =
    reinterpret_cast<uint32_t*>(0x481ae138U);


//////////////
//// CODE ////
//////////////


//// LOW-LEVEL I/O ////


// Commands PRU0 to send bytes with parity information over the data lines.
//
// StartSendBytesWithParity issues a command to PRU0 (the "data pump") to send
// data accompanied by parity information out over the data lines, clocked
// externally by the \PSTRB line. The function returns immediately after issuing
// the command.
//
// The data to send must be supplied as <data byte><parity byte> pairs, with
// the sixth bit of <parity byte> supplying odd parity for <data byte>. The
// other bits are ignored, so it is safe to use values like 0x00 and 0xFF,
// provided the sixth bit is set appropriately.
//
// The WaitSendBytesWithParity function blocks until the data pump either
// completes the transfer or times out. **Any call to StartSendBytesWithParity
// MUST be followed very shortly by a call to WaitSendBytesWithParity**, which
// must be running to avoid data line contention if the Apple ever unexpectedly
// drops the PR/\W line.
//
// Args:
//   addr: Starting address for <data byte><parity byte> pairs to write to the
//       data lines. This address should be in PRU0's address space; take care
//       that none of the data to write lives in the first eight bytes of the
//       shared memory space.
//   size: Number of <data byte><parity byte> pairs to write to the data lines.
inline void StartSendBytesWithParity(const volatile ByteParityPair* const addr,
                                     uint16_t size) {
  // 1. Construct the data pump command in shared memory.
  SHMEM.data_pump_command.return_code = 0xff;  // PRU0 should change this
  SHMEM.data_pump_command.command = dWRITE;    // PRU0 should send data out
  SHMEM.data_pump_command.size = size;         // In particular, this many pairs
  SHMEM.data_pump_command.address = reinterpret_cast<uint32_t>(addr);  // Hence

  // 2. Invoke the data pump. PRU0 will select output mode for the data lines
  // and start sending data.
  CT_INTC.SICR = ePRU0to1;  // Clear PRU0 to PRU1 interrupt
  __R31 = sPRU1to0;         // Wake up PRU0 with an interrupt
}


// Loop until PRU0 finishes sending bytes with parity info over the data lines.
//
// This function should only (and must) be called after a call to
// StartSendBytesWithParity: it waits for termination of the data transfer
// operation that that function initiates.
//
// While waiting for PRU0 to complete the transfer (or time out), this function
// monitors the PR/\W line. If it falls, it immediately reverts the data pins to
// input mode, since the Apple has claimed the bus; it then sends an interrupt
// interrupt to PRU0 to cancel the write. Note that PRU0 might still indicate
// that the command was successful: if the last byte went out on the bus, we
// assume the Apple has read it (sometimes it doesn't clock the last byte and
// instead just toggles PR/\W in preparation to send a $55 acknowledgement).
//
// In order to perform PR/\W monitoring reliably, this function should be called
// as soon as possible after StartSendBytesWithParity returns.
//
// Returns:
//   0: Data transfer was successful.
//   4: Transfer timed out waiting for \PSTRB to go low.
//   5: Transfer timed out waiting for \PSTRB to go high.
//   6: Transfer was interrupted prematurely.
uint8_t WaitSendBytesWithParity() {
  const register uint32_t ones = 0xffffffffU;  // In a register for fast copy
  register bool reassert_interrupt_from_arm = false;  // Also for speed

  // 3a. Wait for the data pump to finish. If PR/\W goes low, select input mode
  // for the data lines to avoid bus conflicts; normally, PRU0 will do this when
  // it finishes.
  for (;;) {
    // If the Apple lowers PR/\W, set data pins to input mode immediately! Then
    // send an interrupt to PRU0 to cancel the write.
    if ((__R31 & (1U << ppRW)) == 0) {
      *GPIO_OE = ones;
      __R31 = sPRU1to0;  // Hey PRU0: cancel the write!
      break;
    }
    // If there is an interrupt, then if it's from the ARM, we'll clear it for
    // now and deal with it later. Otherwise, we assume that it's from PRU0
    // and we forge ahead. We should try not to get many interrupts from the ARM
    // during this busy time, regardless.
    if ((__R31 & (1U << iAnyToPRU1)) != 0) {
      if ((CT_INTC.SECR0 & (1 << eARMtoPRU1)) != 0) {
        reassert_interrupt_from_arm = true;
        CT_INTC.SICR = eARMtoPRU1;
      } else {
        break;  // Note: no clearing this interrupt yet because of 3b below.
      }
    }
  }

  // 3b. Just in case we broke out of the last loop owing to PR/\W going low, we
  // continue waiting for PRU0 or the ARM interrupts in the same way as before.
  for (;;) {
    if ((__R31 & (1U << iAnyToPRU1)) != 0) {
      if ((CT_INTC.SECR0 & (1 << eARMtoPRU1)) != 0) {
        reassert_interrupt_from_arm = true;
        CT_INTC.SICR = eARMtoPRU1;
      } else {
        break;  // Keep waiting, we'll clear ePRU0to1 soon enough.
      }
    }
  }

  // 4. Clear the interrupt from PRU0 at last. Re-assert the ARM interrupt if
  // there was one, and then handle it.
  CT_INTC.SICR = ePRU0to1;
  if (reassert_interrupt_from_arm) {
    __R31 = sARMtoPRU1;
    handle_interrupt();
  }

  // 5. Return the return code from PRU0.
  return SHMEM.data_pump_command.return_code;
}


// Commands PRU0 to send bytes with parity information over the data lines.
//
// Calls StartSendBytesWithParity and WaitSendBytesWithParity. See documentation
// at those functions for details.
//
// Args:
//   addr: Starting address for <data byte><parity byte> pairs to write to the
//       data lines. This address should be in PRU0's address space; take care
//       that none of the data to write lives in the first eight bytes of the
//       shared memory space.
//   size: Number of <data byte><parity byte> pairs to write to the data lines.
//
// Returns:
//   0: Data transfer was successful.
//   4: Transfer timed out waiting for \PSTRB to go low.
//   5: Transfer timed out waiting for \PSTRB to go high.
//   6: Transfer was interrupted prematurely.
inline uint8_t SendBytesWithParity(const volatile ByteParityPair* const addr,
                                   uint16_t size) {
  StartSendBytesWithParity(addr, size);
  return WaitSendBytesWithParity();
}


// Commands PRU1 to receive bytes over the data lines.
//
// ReceiveBytes issues a command to PRU0 (the "data pump") to read data in from
// the data lines, clocked externally by the \PSTRB line. The function waits for
// PRU0 to complete the transfer (or time out).
//
// Args:
//   addr: Starting address for the memory region receiving bytes from the data
//       lines. This address should be in PRU0's address space.
//   size: Number of bytes to read from the data lines.
//
// Returns:
//   0: Data transfer was successful.
//   2: Transfer timed out waiting for \PSTRB to go low.
//   3: Transfer timed out waiting for \PSTRB to go high.
inline uint8_t ReceiveBytes(volatile uint8_t* const addr,
                            uint16_t size) {
  // 1. Construct the data pump command.
  SHMEM.data_pump_command.return_code = 0xff;  // PRU0 should change this
  SHMEM.data_pump_command.command = dREAD;     // PRU0 should read data in
  SHMEM.data_pump_command.size = size;         // In particular, this many bytes
  SHMEM.data_pump_command.address = reinterpret_cast<uint32_t>(addr);  // Thence

  // 2. Invoke the data pump. PRU0 will start reading data.
  CT_INTC.SICR = ePRU0to1;  // Clear PRU0 to PRU1 interrupt
  __R31 = sPRU1to0;         // Wake up PRU0 with an interrupt

  // 3. Wait for the data pump to finish.
  for (;;) {
    // If we got an interrupt...
    if ((__R31 & (1U << iAnyToPRU1)) != 0) {
      // ...and if it came from PRU0, then break. If it came from the ARM, the
      // interrupt handler will just do whatever data transfer thing the ARM
      // needed to do. Either way, the PRU0 to PRU1 interrupt will be cleared
      // upon breaking out of the loop.
      if (kImPru0 == handle_interrupt()) break;
    }
  }

  // 4. Return the return code from PRU0.
  return SHMEM.data_pump_command.return_code;
}


//// OTHER HELPERS ////


// Send the six command bytes from the Apple to the ARM via RPMsg.
//
// The transfer is attempted up to five times. Returns true on success.
inline bool send_apple_command_to_arm() {
  for (int i = 0; i < 5; ++i) {
    void* buffer = const_cast<uint8_t*>(SHMEM.apple_command);
    if (aphd_pru1_rpmsg_send(buffer, sizeof(SHMEM.apple_command)) == 0) {
      return true;
    }
  }
  return false;
}


//// STATE MACHINE ////


// Predeclarations.
void state_machine_read();
void state_machine_write(const uint8_t command);


// State machine idle wait state, command read, and dispatch.
//
// Awaits the start of the ProFile handshake; once received, continues through
// receiving the command from the Apple. If the command is well-formed,
// invokes state_machine_read() or state_machine_write() to complete the
// operation. Returns immediately afterward. Call again to resume waiting for
// another command.
//
// The state_machine* routines have been designed so that they can all return
// early if they encounter an error, and so that it's safe to call
// state_machine_idle anew immediately after that.
void state_machine_idle() {
  // We use this counter to time out while waiting for signal changes, etc.
  register uint32_t t;

  // Copy debug word from the last run through the state machine outer loop.
          if (kDebug) SHMEM.last_control_debug_word = SHMEM.control_debug_word;

  // The state machine is open for business. Raise \PBSY.
  __asm(" SET r30," psBSY);

  // State IDLE/0: Await \PCMD low.
  //               While waiting, service any ARM interrupts.
                                 if (kDebug) SHMEM.control_debug_word = 0x0000;
  while ((__R31 & (1U << ppCMD)) != 0) {
    // The result of interrupt handling doesn't matter to us right here.
    if ((__R31 & (1U << iAnyToPRU1)) != 0) handle_interrupt();
  }

  // State 1a: Lower \PBSY.
  //           Await PR/\W high.
                                 if (kDebug) SHMEM.control_debug_word = 0x0100;
  __asm(" CLR r30," psBSY);
  for (t = 0U; (__R31 & (1U << ppRW)) == 0; ++t) {
    if (t > kTimeout) return;  // Abandon handshake after a while.
  }

  // State 1b: Emit $01 to bus.
                                 if (kDebug) SHMEM.control_debug_word = 0x0101;
  if (SendBytesWithParity(&SHMEM.bytes_with_parity[1], 1U)) return;

  // State 2: Await \PCMD high; when it is, PR/\W must already be low.
  //          Attempt to snoop $55 handshake byte from the bus.
                                 if (kDebug) SHMEM.control_debug_word = 0x0200;
  for (t = 0U; (__R31 & (1U << ppCMD)) == 0; ++t) {
    if (t > kTimeout) return;  // Abandon handshake after a while.
  }
  if ((__R31 & (1U << ppRW)) != 0) return;  // Abandon handshake if PR/\W high.
  SHMEM.apple_handshake[0] = static_cast<uint8_t>(*GPIO_DATAIN >> 14);

  // State 3: Raise \PBSY.
  //          Read command.
                                 if (kDebug) SHMEM.control_debug_word = 0x0300;
  __asm(" SET r30," psBSY);
  if (SHMEM.apple_handshake[0] != 0x55) return;
                                 if (kDebug) SHMEM.control_debug_word = 0x0301;
  if (ReceiveBytes(SHMEM.apple_command, 6U)) return;

  // State 4: Dispatch command.
                                 if (kDebug) SHMEM.control_debug_word = 0x0400;
  switch (SHMEM.apple_command[0]) {
    case 0:  // ProFile "read block" command.
      state_machine_read();
      break;
    case 1:  // ProFile "write block" command.
    case 2:  // ProFile "write block+verify" command.
    case 3:  // ProFile "write block+force sparing" command.
      state_machine_write(SHMEM.apple_command[0]);
      break;
  }
}


// State machine for handling read commands from the Apple.
//
// After further handshaking, requests whatever sector the Apple was interested
// in from the ARM, then transfers it to the Apple.
//
// Returns early if any part of the handshaking times out; otherwise, errors
// are reported to the Apple as dictated by the ProFile protocol.
void state_machine_read() {
  // We use this counter to time out while waiting for signal changes, etc.
  register uint32_t t;

  // State R0: Await \PCMD low and PR/\W high.
                                 if (kDebug) SHMEM.control_debug_word = 0x1000;
  for (t = 0; (__R31 & ((1U << ppCMD) | (1U << ppRW))) != (1U << ppRW); ++t) {
    if (t > kTimeout) return;  // Abandon handshake after a while.
  }

  // State R1: Emit $02 to bus.
  //           Lower \PBSY.
                                 if (kDebug) SHMEM.control_debug_word = 0x1100;
  StartSendBytesWithParity(&SHMEM.bytes_with_parity[2], 1U);
  __asm(" CLR r30," psBSY);
  if (WaitSendBytesWithParity()) return;  // Back to state machine start.

  // State R2a: Await \PCMD high and PR/\W low.
  //            Attempt to snoop $55 handshake byte from the bus.
                                 if (kDebug) SHMEM.control_debug_word = 0x1200;
  for (t = 0; (__R31 & ((1U << ppCMD) | (1U << ppRW))) != (1U << ppCMD); ++t) {
    if (t > kTimeout) return;  // Abandon handshake after a while.
  }
  SHMEM.apple_handshake[0] = static_cast<uint8_t>(*GPIO_DATAIN >> 14);
  // 0x81 means "handshake wasn't 0x55, operation failed" in ProFile-speak.
  uint8_t status = (SHMEM.apple_handshake[0] == 0x55U ? 0x00U : 0x81U);

  // State R2b: Tell ARM to supply data from disk image.
                                 if (kDebug) SHMEM.control_debug_word = 0x1300;
#ifndef ARMLESS_MODE
  // 0x05 means "timeout, operation failed" in ProFile-speak.
  if (status == 0x00U) status = (send_apple_command_to_arm() ? 0x00U : 0x05U);
#endif

  // State R2c: Wait for ARM to supply data from disk image.
  //            Compose status bytes.
  //            Raise \PBSY.
                                 if (kDebug) SHMEM.control_debug_word = 0x1400;
#ifndef ARMLESS_MODE
  if (status == 0x00U) do {
    for (t = 0; (__R31 & (1U << iAnyToPRU1)) == 0; ++t) {
      // We abandon the read if the ARM takes too long to supply us with data.
      // We're a bit more patient with the ARM than we are with signal lines.
      if (t > (kTimeout << 2)) {
        status = 0x05U;  // "Timeout, operation failed."
        break;
      }
    }
  } while ((status == 0x00U) && (handle_interrupt() != kImArmProceed));
#endif
  // The const_casts here should not be necessary, but clpru 2.1.5 seems to
  // need them. clpru 2.2.1 does not.
  SHMEM.drive_status[0] =
      const_cast<ByteParityPair&>(SHMEM.bytes_with_parity[status]);
  SHMEM.drive_status[1] = 
      const_cast<ByteParityPair&>(SHMEM.bytes_with_parity[0]);
  SHMEM.drive_status[2] =
      const_cast<ByteParityPair&>(SHMEM.bytes_with_parity[0]);
  SHMEM.drive_status[3] =
      const_cast<ByteParityPair&>(SHMEM.bytes_with_parity[0]);
  __asm(" SET r30," psBSY);

  // State R2d: Await PR/\W high.
  //            Send status bytes; sector bytes too if the handshake was $55.
                                 if (kDebug) SHMEM.control_debug_word = 0x1500;
  for (t = 0; (__R31 & (1U << ppRW)) == 0; ++t) {
    if (t > kTimeout) return;  // Abandon read after a while.
  }
  SendBytesWithParity(SHMEM.drive_status, 4 + ((status == 0U) ? 532U : 0U));
}


// State machine for handling write commands from the Apple.
//
// After further handshaking, obtains the sector data from the Apple, then more
// handshaking, then the data is transferred to the ARM for storage.
//
// Args:
//   command: the command byte the Apple used to request this read. (The
//       ProFile protocol requires us to repeat back this command, plus two.)
//
// Returns early if any part of the handshaking times out; otherwise, errors
// are reported to the Apple as dictated by the ProFile protocol.
void state_machine_write(const uint8_t command) {
  // We use this counter to time out while waiting for signal changes, etc.
  register uint32_t t;

  // State W0: Await \PCMD low and PR/\W high.
                                 if (kDebug) SHMEM.control_debug_word = 0x2000;
  for (t = 0; (__R31 & ((1U << ppCMD) | (1U << ppRW))) != (1U << ppRW); ++t) {
    if (t > kTimeout) return;  // Abandon handshake after a while.
  }

  // State W1: Emit (command + $02) to bus.
  //           Lower \PBSY.
                                 if (kDebug) SHMEM.control_debug_word = 0x2100;
  StartSendBytesWithParity(&SHMEM.bytes_with_parity[command + 2U], 1U);
  __asm(" CLR r30," psBSY);
  if (WaitSendBytesWithParity()) return;  // Back to state machine start.

  // State W2: Await \PCMD high and PR/\W low.
  //           Attempt to snoop $55 handshake byte from the bus.
                                 if (kDebug) SHMEM.control_debug_word = 0x2200;
  for (t = 0; (__R31 & ((1U << ppCMD) | (1U << ppRW))) != (1U << ppCMD); ++t) {
    if (t > kTimeout) return;  // Abandon handshake after a while.
  }
  SHMEM.apple_handshake[0] = static_cast<uint8_t>(*GPIO_DATAIN >> 14);

  // State W3: Raise \PBSY.
  //           Receive data.
                                 if (kDebug) SHMEM.control_debug_word = 0x2300;
  __asm(" SET r30," psBSY);
  if (SHMEM.apple_handshake[0] != 0x55) return;
                                 if (kDebug) SHMEM.control_debug_word = 0x2301;
  if (ReceiveBytes(SHMEM.apple_sector, 532U)) return;

  // State W4: Await \PCMD low and PR/\W high.
                                 if (kDebug) SHMEM.control_debug_word = 0x2400;
  for (t = 0; (__R31 & ((1U << ppCMD) | (1U << ppRW))) != (1U << ppRW); ++t) {
    if (t > kTimeout) return;  // Abandon handshake after a while.
  }

  // State W5: Emit $06 to bus.
  //           Lower \PBSY.
                                 if (kDebug) SHMEM.control_debug_word = 0x2500;
  StartSendBytesWithParity(&SHMEM.bytes_with_parity[6], 1U);
  __asm(" CLR r30," psBSY);
  if (WaitSendBytesWithParity()) return;  // Back to state machine start.

  // State W6a: Await \PCMD high and PR/\W low.
  //            Attempt to snoop $55 handshake byte from the bus.
                                 if (kDebug) SHMEM.control_debug_word = 0x2600;
  for (t = 0; (__R31 & ((1U << ppCMD) | (1U << ppRW))) != (1U << ppCMD); ++t) {
    if (t > kTimeout) return;  // Abandon handshake after a while.
  }
  SHMEM.apple_handshake[0] = static_cast<uint8_t>(*GPIO_DATAIN >> 14);
  // 0x81 means "handshake wasn't 0x55, operation failed" in ProFile-speak.
  uint8_t status = (SHMEM.apple_handshake[0] == 0x55U ? 0x00U : 0x81U);

  // State W6b: Tell ARM to commit data to disk image.
                                 if (kDebug) SHMEM.control_debug_word = 0x2700;
#ifndef ARMLESS_MODE
  // 0x05 means "timeout, operation failed" in ProFile-speak.
  if (status == 0x00U) status = (send_apple_command_to_arm() ? 0x00U : 0x05U);
#endif

  // State W6c: Wait for ARM to commit data to disk image.
  //            Compose status bytes.
  //            Raise \PBSY.
                                 if (kDebug) SHMEM.control_debug_word = 0x2800;
#ifndef ARMLESS_MODE
  if (status == 0x00U) do {
    for (t = 0; (__R31 & (1U << iAnyToPRU1)) == 0; ++t) {
      // We abandon the read if the ARM takes too long to read out the data.
      // We're a bit more patient with the ARM than we are with signal lines.
      if (t > (kTimeout << 2)) {
        status = 0x05U;  // "Timeout, operation failed."
        break;
      }
    }
  } while ((status == 0x00U) && (handle_interrupt() != kImArmProceed));
#endif
  // The const_casts here should not be necessary, but clpru 2.1.5 seems to
  // need them. clpru 2.2.1 does not.
  SHMEM.drive_status[0] =
      const_cast<ByteParityPair&>(SHMEM.bytes_with_parity[status]);
  SHMEM.drive_status[1] =
      const_cast<ByteParityPair&>(SHMEM.bytes_with_parity[0]);
  SHMEM.drive_status[2] =
      const_cast<ByteParityPair&>(SHMEM.bytes_with_parity[0]);
  SHMEM.drive_status[3] =
      const_cast<ByteParityPair&>(SHMEM.bytes_with_parity[0]);
  __asm(" SET r30," psBSY);

  // State W6d: Await PR/\W high.
  //            Send status bytes.
                                 if (kDebug) SHMEM.control_debug_word = 0x2900;
  for (t = 0; (__R31 & (1U << ppRW)) == 0; ++t) {
    if (t > kTimeout) return;  // Abandon status report after a while.
  }
  SendBytesWithParity(SHMEM.drive_status, 4U);
}


//// MAIN PROGRAM ////


void main(void) {
  // Setup.
  CT_CFG.SYSCFG_bit.STANDBY_INIT = 0;  // Enable OCP master port
  aphd_pru1_rpmsg_init();  // Initialise RPMsg system

  // Main loop.
  for (;;) state_machine_idle();

#pragma diag_suppress=112
  // PRU core halts, or it would if we could reach this line.
  __halt();
}
