/* Apple parallel port storage emulator for Cameo
 *
 * Forfeited into the public domain with NO WARRANTY. Read LICENSE for details.
 *
 * This file: firmware for PRU1; RPMsg I/O routines
 *
 * RPMsg is the communication mechanism for transferring data to and from the
 * ARM. Once initialised, ARM programs will be able to send and receive data
 * to and from PRU1 by writing to/reading from /dev/rpmsg_pru31, a character
 * device.
 *
 * All individual data transactions should be limited to 512 - 16 = 496 bytes:
 * the empty space in RPMsg message buffers once the TI RPMsg libraries claim
 * part of it for a header. When sending, the ARM program should probably use
 * `select()` or `poll()` to make sure that PRU1 is ready for new data.
 */

#ifndef APHD_PRU1_RPMSG_H_
#define APHD_PRU1_RPMSG_H_


#include <stdint.h>


#ifdef __cplusplus
extern "C" {
#endif  /* __cplusplus */


/* This symbol has the exact same meaning and value as RPMSG_BUF_SIZE from
 * pru_rpmsg.h, but since C++ code can have a hard time including that file, we
 * redefine that number here. There is a "static assert" of sorts at the
 * beginning of aphd_pru1_rpmsg.c that will cause a compilation failure if the
 * value of this symbol no longer matches the value of RPMSG_BUF_SIZE. */
#define RPMSG_BUFFER_SIZE 512


/* A buffer for RPMsg messages. All inbound messages land here; outbound
 * messages can originate from anywhere in RAM.
 *
 * (This buffer is twice the size of the largest RPMsg message in the spirit of
 * "defensive programming". RPMsg provides no way to know how big a message is
 * before you receive it. Since `aphd_pru1_rpmsg_receive()` flushes all pending
 * incoming messages each time it's called, but promises to keep the first
 * RPMSG_BUFFER_SIZE bytes it loads, it needs room for the messages to overflow
 * this limit before it knows to throw the extra information into the void.) */
extern uint8_t RPMSG_BUFFER[RPMSG_BUFFER_SIZE + RPMSG_BUFFER_SIZE];


/* Initialise internal RPMsg I/O control state.
 *
 * This function must be called before calling any of the other functions in
 * this file---ideally right when the firmware starts running. Loops forever if
 * certain initialisation conditions on the Linux side are not met; since the
 * PRU1 firmware is not much use without being able to talk to the ARM, this
 * seems like a reasonable simplification. */
void aphd_pru1_rpmsg_init();


/* Send data to the ARM via RPMsg.
 *
 * Args:
 *   buffer: starting address of data to send.
 *   length: amount of data to send in bytes. Successful sends require this
 *       value to be no larger than 496.
 *
 * Returns:
 *   See return value documentation for `pru_rpmsg_send()` in the TI RPMsg API's
 *   pru_rpmsg.h. Success causes a return value of 0. */
int16_t aphd_pru1_rpmsg_send(void* buffer, uint16_t length);


/* Receive data from the ARM via RPMsg.
 *
 * Retrieves all inbound RPMsg messages waiting to be delivered to PRU1 from the
 * ARM. Up to the first RPMSG_BUFFER_SIZE bytes of data in these messages will
 * be stored in RPMSG_BUFFER. (Occasionally a bit more may be retrieved if there
 * is more than that amount waiting, but only the first RPMSG_BUFFER_SIZE are
 * guaranteed to be saved; the rest may be discarded.)
 *
 * Returns:
 *   Amount of data received in bytes.
 */
uint16_t aphd_pru1_rpmsg_receive();


#ifdef __cplusplus
}
#endif  /* __cplusplus */

#endif  /* APHD_PRU1_RPMSG_H_ */
