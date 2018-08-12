/* Apple parallel port storage emulator for Cameo
 *
 * Forfeited into the public domain with NO WARRANTY. Read LICENSE for details.
 *
 * This file: the remoteproc resource table for PRU 1.
 */

#ifndef APHD_PRU1_RESOURCE_TABLE_H_
#define APHD_PRU1_RESOURCE_TABLE_H_


#include <stddef.h>
#include <stdint.h>

#include <pru_types.h>
#include <pru_virtio_ids.h>
#include <rsc_types.h>


#ifdef __cplusplus
#extern "C" {
#endif  /* __cplusplus */


struct pru1_resource_table {
  struct resource_table resources;
  uint32_t offsets[2];  /* Size should match the value in resources.num. */

  /* RPMsg configuration; a vdev with two vrings. */
  struct {
    struct fw_rsc_vdev vdev;
    struct fw_rsc_vdev_vring vring0;
    struct fw_rsc_vdev_vring vring1;
  } rpmsg;

  /* PRU INTC configuration. */
  struct fw_rsc_custom intc;
};


extern struct pru1_resource_table PRU1_RESOURCE_TABLE;


#ifdef __cplusplus
}
#endif  /* __cplusplus */

#endif  /* APHD_PRU1_RESOURCE_TABLE_H_ */
