/* Apple parallel port storage emulator for Cameo
 *
 * Forfeited into the public domain with NO WARRANTY. Read LICENSE for details.
 *
 * This file: firmware for PRU1; RPMsg I/O routines.
 */


#include <stdint.h>

#include <pru_intc.h>
#include <pru_rpmsg.h>

#include "aphd_pru_common.h"
#include "aphd_pru1_resource_table.h"
#include "aphd_pru1_rpmsg.h"


/* For reasons elaborated in aphd_pru1_rpmsg.h, we define our own "copy" of the
 * RPMSG_BUF_SIZE value called RPMSG_BUFFER_SIZE. It's essential that our copy
 * track the original, so this type definition will cause a compile failure if
 * RPMSG_BUF_SIZE ever changes from its current value. To fix, all that's likely
 * to be necessary is to change RPMSG_BUFFER_SIZE to the correct value. */
typedef char ______RPMSG_BUF_SIZE_and_RPMSG_BUFFER_SIZE_are_not_the_same______[
    (RPMSG_BUF_SIZE == RPMSG_BUFFER_SIZE) ? 1 : -1];


/* TI RPMsg API data structure for RPMsg communication. */
static struct pru_rpmsg_transport RPMSG_TRANSPORT;

/* RPMsg uses these dynamically-assigned addresses to specify the senders and
 * recipients of messages. */
static uint16_t RPMSG_ARM_ADDRESS;
static uint16_t RPMSG_PRU_ADDRESS;

/* Data buffer mainly for incoming messages. Details in header. */
uint8_t RPMSG_BUFFER[RPMSG_BUFFER_SIZE + RPMSG_BUFFER_SIZE];


/* Built-in symbols used for PRU GPIO pin access and interrupt handling. */
volatile register uint32_t __R30;
volatile register uint32_t __R31;


/* Helper: calls pru_rpmsg_receive with the state variables internal to this
 * module as parameters. */
inline int _receive(uint8_t* buffer, uint16_t* length) {
  return pru_rpmsg_receive(
      &RPMSG_TRANSPORT,
      &RPMSG_ARM_ADDRESS,
      &RPMSG_PRU_ADDRESS,
      buffer,
      length);
}


void aphd_pru1_rpmsg_init() {
  uint16_t received;

  /* Wait until the Linux driver has updated the status byte in the vdev struct
   * inside our resource table. 0x4 is the correct bit to look out for as per
   * virtio_config.h in the Linux kernel source. */
  const uint8_t kVirtioConfigSDriverOk = 0x4;
  volatile uint8_t* status = &PRU1_RESOURCE_TABLE.rpmsg.vdev.status;
  while (!(*status & kVirtioConfigSDriverOk));

  /* Initialise the RPMSG_TRANSPORT structure. */
  pru_rpmsg_init(
      &RPMSG_TRANSPORT,  /* Initialise this transport structure */
      &PRU1_RESOURCE_TABLE.rpmsg.vring0,  /* One of the input/output vrings */
      &PRU1_RESOURCE_TABLE.rpmsg.vring1,  /* The other input/output vring */
      ePRU1toARM,
      eARMtoPRU1);

  /* With that structure, create an RPMsg channel between ARM and the PRU. */
  while (pru_rpmsg_channel(
             RPMSG_NS_CREATE,
             &RPMSG_TRANSPORT,
             "rpmsg-pru",   /* Channel name---loads corresp. kernel module */
             "Channel 31",  /* Channel description */
             31             /* Channel port */
         ) != PRU_RPMSG_SUCCESS);

  /* Await a dummy message from the ARM to populate src and dst addresses. We
   * are hoping at this early stage not to receive any interrupts from PRU0,
   * but if we do, we will just ignore them and let PRU0 time out. */
  CT_INTC.SICR = eARMtoPRU1;  /* Clear ARM to PRU1 interrupt */
  for(;;) {
    if (__R31 & (1U << iAnyToPRU1)) {           /* If we got an interrupt... */
      if (CT_INTC.SECR0 & (1 << eARMtoPRU1)) {   /* ...from the ARM, then... */
        /* ...throw away data from the ARM and clear ARM to PRU1 interrupt. */
        if (_receive(RPMSG_BUFFER, &received) == PRU_RPMSG_SUCCESS) {
          while(_receive(RPMSG_BUFFER, &received) == PRU_RPMSG_SUCCESS);
          CT_INTC.SICR = eARMtoPRU1;
          break;
        }

      } else {          /* But if the interrupt wasn't from the ARM, then... */
        CT_INTC.SICR = ePRU0to1;       /* ...clear PRU0 to PRU1 interrupt... */
      }                                   /* ...and keep waiting for the ARM */
    }
  }
}


int16_t aphd_pru1_rpmsg_send(void* buffer, uint16_t length) {
  return pru_rpmsg_send(
      &RPMSG_TRANSPORT,
      RPMSG_PRU_ADDRESS,
      RPMSG_ARM_ADDRESS,
      buffer,
      length);
}


uint16_t aphd_pru1_rpmsg_receive() {
  uint16_t total_received = 0;
  uint16_t received;
  uint8_t* buf = RPMSG_BUFFER;

  /* Messages can be broken into smaller chunks, so we continue pulling in data
   * until there isn't any left. */
  for (;;) {
    if (_receive(buf, &received) != PRU_RPMSG_SUCCESS) break;

    total_received += received;
    buf += received;

    /* If we've received more than RPMSG_BUFFER_SIZE bytes, we toss any
     * remaining data into the bit bucket until we've exhausted all input. */
    if (total_received > RPMSG_BUFFER_SIZE) {
      for (;;) {
        if (_receive(RPMSG_BUFFER +
                     RPMSG_BUFFER_SIZE, &received) != PRU_RPMSG_SUCCESS) break;
      }
      break;
    }
  }

  return total_received;
}
