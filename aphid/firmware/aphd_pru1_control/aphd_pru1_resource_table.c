/* Apple parallel port storage emulator for Cameo
 *
 * Forfeited into the public domain with NO WARRANTY. Read LICENSE for details.
 *
 * This file: the remoteproc resource table for PRU 1.
 */


#include "aphd_pru_common.h"
#include "aphd_pru1_resource_table.h"


struct ch_map PRU1_INTC_SYSEVENT_TO_CHANNEL[] = {
  {ePRU0to1, 1U},
  {ePRU1to0, 0U},
  {ePRU1toARM, 2U},
  {eARMtoPRU1, 3U},
};


#pragma DATA_SECTION(PRU1_RESOURCE_TABLE, ".resource_table")
#pragma RETAIN(PRU1_RESOURCE_TABLE)
struct pru1_resource_table PRU1_RESOURCE_TABLE = {
  .resources = {
    .ver = 1U,
    .num = 2U,
    .reserved = {0U, 0U},
  },

  .offsets = {
    offsetof(struct pru1_resource_table, rpmsg),
    offsetof(struct pru1_resource_table, intc),
  },

  .rpmsg = {
    .vdev = {
      .type = TYPE_VDEV,
      .id = VIRTIO_ID_RPMSG,
      .notifyid = 0U,  /* Host populates this notify ID. */
      .dfeatures = 0x00000001U,  /* Supports name service notifications. */
      .gfeatures = 0U,  /* Host populates with its own features. */
      .config_len = 0U,
      .status = 0U,  /* Host populates this status byte. */
      .num_of_vrings = 2U,  /* For RX and TX (not sure which is which). */
      .reserved = {0U, 0U},
    },
    .vring0 = {
      .da = 0U,  /* Host populates this device address. */
      .align = 16U,
      .num = 16U,  /* Number of buffers must be a power of 2. */
      .notifyid = 0U, /* Host populates this notify ID. */
      .reserved = 0U,
    },
    .vring1 = {
      .da = 0U,  /* Host populates this device address. */
      .align = 16U,
      .num = 16U,  /* Number of buffers must be a power of 2. */
      .notifyid = 0U, /* Host populates this notify ID. */
      .reserved = 0U,
    },
  },

  .intc = {
    .type = TYPE_CUSTOM,
    /* The rsc_types.h header changed between versions 9.4 and 9.5 of the OS to
     * provide two ways to specify the custom resource sub-type. The change also
     * defined the macro TYPE_PRELOAD_VENDOR, which was undefined before. We use
     * this macro to identify which version of rsc_types.h we're using. */
#ifdef TYPE_PRELOAD_VENDOR
    .u = {
      .sub_type = TYPE_PRU_INTS,
    },
#else
    .sub_type = TYPE_PRU_INTS,
#endif
    .rsc_size = sizeof(struct fw_rsc_custom_ints),
    .rsc = {
      .pru_ints = {
      /* The pru_types.h header changed between versions 9.4 and 9.5 of the OS
       * to deprecate the version field of fw_rsc_custom_ints. The change also
       * defined the macro PRU_INTS_VER0, which was undefined before. We use
       * this macro to identify which version of pru_types.h we're using. */
#ifdef PRU_INTS_VER0
        .reserved = 0U,
#else
        .version = 0U,
#endif
        .channel_host = {
          0U,  /* Channel 0 (ePRU1to0): host interrupt 0, so r31 bit 30. */
          1U,  /* Channel 1 (ePRU0to1): host interrupt 1, so r31 bit 31. */
          2U,  /* Channel 2 (ePRU1toARM): host interrupt 2. */
          1U,  /* Channel 3 (eARMtoPRU1): host interrupt 1, so r31 bit 31. */
          255U, 255U, 255U, 255U, 255U, 255U,  /* Channels 4-9: unused. */
        },
        .num_evts = (sizeof(PRU1_INTC_SYSEVENT_TO_CHANNEL) /
                    sizeof(struct ch_map)),
        .event_channel = PRU1_INTC_SYSEVENT_TO_CHANNEL,
      },
    },
  },
};
