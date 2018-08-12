// Aphid: Apple parallel port hard drive emulator for Cameo
//
// Forfeited into the public domain with NO WARRANTY. Read LICENSE for details.
//
// This file: firmware for PRU 1; interrupt and RPMsg buffer handling.
//
// Although this unit contains routines for servicing all kinds of interrupts
// encountered by PRU1, most of the code is for dealing with RPMsg messages
// from the ARM. Some interrupts (particularly those from PRU 0 data pump
// routines) are handled by aphd_pru1_control.cc code directly to minimise
// latency.

#ifndef APHD_PRU1_INTERRUPT_AND_BUFFER_HANDLER_H_
#define APHD_PRU1_INTERRUPT_AND_BUFFER_HANDLER_H_


// Interpretations for R31 bit 31 interrupts to PRU1. These serve as return
// values for `handle_interrupt()`.
enum InterruptMeaning {
  // There was no interrupt, as best we can tell, at least not one that we
  // were equipped to handle. Note that it's preferable to call
  // handle_interrupt() only when there is an interrupt, i.e. R31 bit 31 is
  // actually set.
  kImNone = 0,

  // The interrupt originated from PRU0. It's up to the caller to determine
  // what to do about that.
  kImPru0 = 1,

  // The interrupt came from the ARM sending a message over RPMsg, but it was
  // a buffer-handling request that the interrupt handler serviced on its own.
  // No action is required.
  kImArmHandled = 2,

  // The interrupt came from the ARM sending a message over RPMSG, and although
  // it was a buffer-handling request that the interrupt handler could service
  // on its own, its attempt to do so failed.
  kImArmFailedToHandle = 3,

  // The interrupt came from the ARM sending a message over RPMsg, and it was
  // the ARM advising PRU1 that the ARM has completed all of the buffer
  // operations that PRU1 was waiting on the ARM to complete.
  kImArmProceed = 4,
};


// Handle an R31 bit 31 interrupt.
//
// There are two sources of bit-31 ("for PRU1") interrupts: the ARM and PRU0.
//
// An interrupt from PRU0 is essentially up to the caller to handle---usually
// it means that a data transfer to the Apple has completed, and so the
// controller can go on with the rest of the protocol.
//
// Interrupts from the ARM mainly concern memory that the ARM would like to read
// into or out of sector buffers. The interrupt handler takes care of these on
// its own. Occasionally an ARM interrupt tells PRU1 that the ARM is finished
// with certain critical buffer operations (it's written a sector to the disk
// image, for example) and that the rest of the read or write can continue.
//
// This routine should be called only when PRU1 finds that R31 bit 31 is set.
// It will investigate the interrupt, handle it appropriately, **and finally,
// clear it.**
//
// Returns:
//   an `InterruptMeaning` value indicating the importance (and in some cases,
//   resolution) of the interrupt. See `InterruptMeaning` for details.
InterruptMeaning handle_interrupt();


#endif  // APHD_PRU1_INTERRUPT_AND_BUFFER_HANDLER_H_
