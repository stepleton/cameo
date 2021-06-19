// Aphid: Apple parallel port hard drive emulator for Cameo
//
// Forfeited into the public domain with NO WARRANTY. Read LICENSE for details.
//
// This file: firmware for PRU1; main program
//
// PRU1 is the "control processor" in charge of data exchange with the ARM and
// parallel port handshaking. PRU1 handles the \PCMD, \PBSY, and PR/\W signal
// lines directly, but issues commands to PRU0 (the "data pump") to move data
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


// An "armless" PRU1 firmware does not request the ARM to copy data into or
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
// Some loops execute enough instructions between iterations that an equivalent
// timeout to the above is a few orders of magnitude fewer cycles.
static const uint32_t kTimeoutSB = kTimeout >> 4;


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


// Predeclarations.
uint8_t _NormalCleanup(const bool& reassert_interrupt_from_arm);
uint8_t _AbnormalCleanup(const bool& reassert_interrupt_from_arm);


// Resets PRU0 to the idle state (where it awaits a new command).
//
// Per the recommended reset procedure described in aphd_pru0_datapump.asm,
// repeatedly issues an invalid command to PRU0 until it receives an error
// response that means "invalid command" (0x01).
//
// Will loop forever until it receives this response.
inline void ResetDataPump() {
  // Repeat forever until we get a 0x01 response from the PRU.
  for (;;) {
    // 1. Await PRU1 to PRU0 interrupt clear. Normally we wouldn't check this
    // ourselves, but in the reset routine we don't know what state PRU0 is in,
    // and we don't want to issue an interrupt until we know that PRU0 is ready
    // for it. As long as the firmware is running, it should clear this
    // interrupt in fairly short order.
    while ((CT_INTC.SECR0 & (1 << ePRU1to0)) != 0);

    // 2. Deliberately prepare an invalid command for the PRU. (Size and address
    // fields don't matter for invalid commands.)
    SHMEM.data_pump_command.return_code = 0xff;  // PRU0 should change this
    SHMEM.data_pump_command.command = dINVALID;  // An invalid command code

    // 3. Try to invoke the data pump.
    CT_INTC.SICR = ePRU0to1;  // Clear PRU0 to PRU1 interrupt
    __R31 = sPRU1to0;         // Wake up PRU0 with an interrupt

    // 4. Wait for the data pump to get back to us.
    for (;;) {
      // If we got an interrupt...
      if ((__R31 & (1U << iAnyToPRU1)) != 0) {
        // ...clear it, and if it came from the ARM, handle it before you do
        // that as well. But if it came from PRU0...
        if (kImPru0 == handle_interrupt()) {
          // ...then return if the return code is 0x01 ("invalid command")...
          if (SHMEM.data_pump_command.return_code == 0x01) return;
          // ...otherwise break and send another invalid command.
          break;
        }
      }
    }
  }
}


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
  // 0. We haven't told the data pump to do anything yet, so clear out any
  // lingering interrupts without worrying about where they came from.
  while ((__R31 & (1U << iAnyToPRU1)) != 0) handle_interrupt();

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
// Args:
//   timeout: If nonzero, polls the control lines this many times before giving
//       up, interrupting the transfer, and returning.
//
// Returns:
//   0: Data transfer was successful.
//   4: Transfer interrupted waiting for \PSTRB to go low.
//   5: Transfer interrupted waiting for \PSTRB to go high.
uint8_t WaitSendBytesWithParity(uint32_t timeout = 0) {
  const register uint32_t ones = 0xffffffffU;  // In a register for fast copy
  register bool reassert_interrupt_from_arm = false;  // Also for speed

  // 3a. Now wait for the data pump to finish. If PR/\W goes low, select input
  // mode for the data lines to avoid bus conflicts; normally, PRU0 will do
  // this when it finishes. Meanwhile, \PCMD may *start* low---rising edges are
  // OK with us. There is hypothetically a *RACE* here: \PCMD could fall just
  // prior to this point, though this would probably be an abnormal and unlucky
  // situation if WaitSendBytesWithParity is called under ordinary conditions.
  while ((__R31 & (1U << ppCMD)) == 0) {
    // Decrement timeout counter where applicable.
    if (timeout != 0) {
      if (--timeout == 0) {
        *GPIO_OE = ones;  // Data pins to input mode NOW!
        return _AbnormalCleanup(reassert_interrupt_from_arm);
      }
    }
    // If the Apple lowers PR/\W, set data pins to input mode immediately! Then
    // send an interrupt to PRU0 to cancel the write.
    if ((__R31 & (1U << ppRW)) == 0) {
      *GPIO_OE = ones;  // Data pins to input mode NOW!
      return _AbnormalCleanup(reassert_interrupt_from_arm);
    }
    // If there is an interrupt, then if it's from the ARM, we'll clear it for
    // now and deal with it later (allowing us to keep monitoring the PR/\W
    // lines closely. Otherwise, we assume that it's from PRU0 and we jump ahead
    // to return. We should try not to get many interrupts from the ARM during
    // this busy time, regardless---this could be a flaky solution.
    if ((__R31 & (1U << iAnyToPRU1)) != 0) {
      if ((CT_INTC.SECR0 & (1 << eARMtoPRU1)) != 0) {
        reassert_interrupt_from_arm = true;
        CT_INTC.SICR = eARMtoPRU1;
      } else {
        // If here, data pins are already in input mode.
        return _NormalCleanup(reassert_interrupt_from_arm);
      }
    }
  }

  // 3b. If \PCMD was originally high or if there was a rising edge, keep on
  // waiting for the data pump to finish, as long as \PCMD stays high. We use
  // the same logic from the previous loop.
  while ((__R31 & (1U << ppCMD)) != 0) {
    if (timeout != 0) {
      if (--timeout == 0) {
        *GPIO_OE = ones;
        return _AbnormalCleanup(reassert_interrupt_from_arm);
      }
    }
    if ((__R31 & (1U << ppRW)) == 0) {
      *GPIO_OE = ones;
      return _AbnormalCleanup(reassert_interrupt_from_arm);
    }
    if ((__R31 & (1U << iAnyToPRU1)) != 0) {
      if ((CT_INTC.SECR0 & (1 << eARMtoPRU1)) != 0) {
        reassert_interrupt_from_arm = true;
        CT_INTC.SICR = eARMtoPRU1;
      } else {
        return _NormalCleanup(reassert_interrupt_from_arm);
      }
    }
  }


  // 4. But if we're here, \PCMD has fallen. We must cancel the data pump's
  // current operation and wait for it to send us an interrupt to indicate that
  // it's done. We
  *GPIO_OE = ones;  // Set data pins to input mode as a precaution.
  return _AbnormalCleanup(reassert_interrupt_from_arm);
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
//   timeout: If nonzero, polls the control lines this many times before giving
//       up, interrupting the transfer, and returning.
//
// Returns:
//   0: Data transfer was successful.
//   4: Transfer interrupted waiting for \PSTRB to go low.
//   5: Transfer interrupted waiting for \PSTRB to go high.
inline uint8_t SendBytesWithParity(const volatile ByteParityPair* const addr,
                                   uint16_t size, uint32_t timeout = 0) {
  StartSendBytesWithParity(addr, size);
  return WaitSendBytesWithParity(timeout);
}


// Commands PRU1 to receive bytes over the data lines.
//
// ReceiveBytes issues a command to PRU0 (the "data pump") to read data in from
// the data lines, clocked externally by the \PSTRB line. The function normally
// waits for PRU0 to complete the transfer, but it will terminate prematurely
// with a nonzero return code on a \PCMD falling edge.
//
// (As an example case where this precaution might be relevant: imagine that
// the Apple crashes halfway through clocking in bytes to write to the disk.
// \PCMD may remain high throughout the Apple's reboot process, but the Apple
// is unlikely to resume the transaction where it left off. When it is finally
// ready to talk to the disk again, it will lower \PCMD to initiate a new
// command, and that's the rising edge that causes us abort the data pump's read
// operation.)
//
// Args:
//   addr: Starting address for the memory region receiving bytes from the data
//       lines. This address should be in PRU0's address space.
//   size: Number of bytes to read from the data lines; should be above 0.
//   timeout: If nonzero, polls the control lines this many times before giving
//       up, interrupting the transfer, and returning.
//
// Returns:
//   0: Data transfer was successful.
//   2: Transfer interrupted waiting for \PSTRB to go low.
//   3: Transfer interrupted waiting for \PSTRB to go high.
uint8_t ReceiveBytes(volatile uint8_t* const addr, uint16_t size,
                     uint32_t timeout = 0) {
  // A useful alias.
  volatile uint8_t* const return_code = &SHMEM.data_pump_command.return_code;

  // 0. We haven't told the data pump to do anything yet, so clear out any
  // lingering interrupts without worrying about where they came from.
  while ((__R31 & (1U << iAnyToPRU1)) != 0) handle_interrupt();

  // 1. Construct the data pump command.
  SHMEM.data_pump_command.return_code = 0xff;  // PRU0 should change this
  SHMEM.data_pump_command.command = dREAD;     // PRU0 should read data in
  SHMEM.data_pump_command.size = size;         // In particular, this many bytes
  SHMEM.data_pump_command.address = reinterpret_cast<uint32_t>(addr);  // Thence

  // 2. Invoke the data pump. PRU0 will start reading data.
  CT_INTC.SICR = ePRU0to1;  // Clear PRU0 to PRU1 interrupt
  __R31 = sPRU1to0;         // Wake up PRU0 with an interrupt

  // 3a. Now wait for the data pump to finish. \PCMD may *start* low---rising
  // edges are OK with us. There is hypothetically a *RACE* here: \PCMD could
  // fall just prior to this point, though this would probably be an abnormal
  // and unlucky situation if ReceiveBytes is called under ordinary conditions.
  while ((__R31 & (1U << ppCMD)) == 0) {
    // Decrement timeout counter where applicable.
    if (timeout != 0) {
      if (--timeout == 0) return _AbnormalCleanup(false);
    }
    // If we got an interrupt...
    if ((__R31 & (1U << iAnyToPRU1)) != 0) {
      // ...and if it came from PRU0, then break. If it came from the ARM, the
      // interrupt handler will just do whatever data transfer thing the ARM
      // needed to do. Either way, the PRU0 to PRU1 interrupt will be cleared
      // upon breaking out of the loop.
      if (kImPru0 == handle_interrupt()) return *return_code;
    }
  }

  // 3b. If \PCMD was originally high or if there was a rising edge, keep on
  // waiting for the data pump to finish, as long as \PCMD stays high. We use
  // the same logic from the previous loop.
  while ((__R31 & (1U << ppCMD)) != 0) {
    if (timeout != 0) {
      if (--timeout == 0) return _AbnormalCleanup(false);
    }
    if ((__R31 & (1U << iAnyToPRU1)) != 0) {
      if (kImPru0 == handle_interrupt()) return *return_code;
    }
  }

  // 4. But if we're here, \PCMD has fallen. We must cancel the data pump's
  // current operation and wait for it to send us an interrupt to indicate that
  // it's done.
  return _AbnormalCleanup(false);
}


// Helper for ReceiveBytes, WaitSendBytesWithParity: handle "normal" cleanup.
//
// Call only after PRU0 has issued an interrupt indicating that the transfer
// is complete!
//
// Args:
//   reassert_interrupt_from_arm: If set, the caller has deferred an interrupt
//       from the ARM, and this routine should reassert this interrupt and
//       then handle it. The caller should endeavour not to allow more than one
//       interrupt from the ARM to be deferred; only one interrupt can be
//       handled in this way.
//
// Returns:
//   See return details at ReceiveBytes or WaitSendBytesWithParity, depending on
//   who the caller was.
inline uint8_t _NormalCleanup(const bool& reassert_interrupt_from_arm) {
  if(reassert_interrupt_from_arm) {
    __R31 = sARMtoPRU1;
    handle_interrupt();
  }
  return SHMEM.data_pump_command.return_code;
}


// Helper for ReceiveBytes, WaitSendBytesWithParity: handle "abnormal" cleanup.
//
// Issues an interrupt to PRU0 to terminate a data transfer operation in
// progress, then awaits an interrupt from PRU0 signalling that termination has
// occurred and that PRU0 has returned to the idle state.
//
// Args:
//   reassert_interrupt_from_arm: If set, the caller has deferred an interrupt
//       from the ARM, and this routine should reassert this interrupt and
//       then handle it. The caller should endeavour not to allow more than one
//       interrupt from the ARM to be deferred; only one interrupt can be
//       handled in this way.
//
// Returns:
//   See return details at ReceiveBytes or WaitSendBytesWithParity, depending on
//   who the caller was.
inline uint8_t _AbnormalCleanup(const bool& reassert_interrupt_from_arm) {
  __R31 = sPRU1to0;  // Trigger an interrupt of PRU0.
  for (;;) {
    if ((__R31 & (1U << iAnyToPRU1)) != 0) {  // Await the PRU0 response...
      if (kImPru0 == handle_interrupt()) { //...and here it is.
        return _NormalCleanup(reassert_interrupt_from_arm);
      }
    }
  }
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
  if (SendBytesWithParity(&SHMEM.bytes_with_parity[1], 1U, kTimeoutSB)) return;

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
  if (WaitSendBytesWithParity(kTimeoutSB)) return;  // Goto state machine start.

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
  if (WaitSendBytesWithParity(kTimeoutSB)) return;  // Goto state machine start.

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
  ReceiveBytes(SHMEM.apple_sector, 532U);  // <532 is fine; Apple /// uses 512.

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
  if (WaitSendBytesWithParity(kTimeoutSB)) return;  // Goto state machine start.

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
  ResetDataPump();  // Force data pump into a known state

  // Main loop.
  for (;;) state_machine_idle();

#pragma diag_suppress=112
  // PRU core halts, or it would if we could reach this line.
  __halt();
}
