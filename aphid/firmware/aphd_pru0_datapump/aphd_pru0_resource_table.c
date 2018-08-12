/* Apple parallel port storage emulator for Cameo
 *
 * Forfeited into the public domain with NO WARRANTY. Read LICENSE for details.
 *
 * This file: the remoteproc resource table for PRU 0.
 */


#include <stddef.h>
#include <stdint.h>

#include <pru_types.h>
#include <rsc_types.h>

#include "aphd_pru_common.h"


/* Define this symbol to embed a resource table that configures the interrupt
 * controller to match the resources that PRU 0 uses. Ordinarily we leave this
 * undefined and use an empty resource table in the expectation that the PRU 1
 * resource table will configure the interrupt controller appropriately. */
#undef PRU_0_STANDALONE


#ifdef PRU_0_STANDALONE
/* Define a resource table that configures the interrupt controller to support
 * the interrupts that PRU 0 will use. */


struct pru0_resource_table {
  struct resource_table resources;
  uint32_t offsets[1];  /* Size should match the value in resources.num. */
  struct fw_rsc_custom intc;   /* PRU intc. */
};


struct ch_map PRU0_INTC_SYSEVENT_TO_CHANNEL[] = {
  {ePRU0to1, 1U},
  {ePRU1to0, 0U},
};


#pragma DATA_SECTION(PRU0_RESOURCE_TABLE, ".resource_table")
#pragma RETAIN(PRU0_RESOURCE_TABLE)
struct pru0_resource_table PRU0_RESOURCE_TABLE = {
  .resources = {
    .ver = 1U,
    .num = 1U,
    .reserved = {0U, 0U},
  },

  .offsets = {
    offsetof(struct pru0_resource_table, intc),
  },

  .intc = {
    .type = TYPE_CUSTOM,
    .sub_type = TYPE_PRU_INTS,
    .rsc_size = sizeof(struct fw_rsc_custom_ints),
    .rsc = {
      .pru_ints = {
        .version = 0U,
        .channel_host = {
          0U,  /* Channel 0 (ePRU1to0): host interrupt 0, so r31 bit 30. */
          1U,  /* Channel 1 (ePRU0to1): host interrupt 1, so r31 bit 31. */
          255U, 255U, 255U, 255U, 255U, 255U, 255U, 255U,  /* 4-9: unused. */
        },
        .num_evts = (sizeof(PRU0_INTC_SYSEVENT_TO_CHANNEL) /
                    sizeof(struct ch_map)),
        .event_channel = PRU0_INTC_SYSEVENT_TO_CHANNEL,
      },
    },
  },
};


#else  /* PRU_0_STANDALONE */
/* Define an empty resource table. */


struct pru0_resource_table {
  struct resource_table resources;
};


#pragma DATA_SECTION(PRU0_RESOURCE_TABLE, ".resource_table")
#pragma RETAIN(PRU0_RESOURCE_TABLE)
struct pru0_resource_table PRU0_RESOURCE_TABLE = {
  .resources = {
    .ver = 1U,
    .num = 0U,
    .reserved = {0U, 0U},
  },
};


#endif  /* PRU_0_STANDALONE */
