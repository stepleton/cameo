/* Apple parallel port storage emulator for Cameo
 *
 * Forfeited into the public domain with NO WARRANTY. Read LICENSE for details.
 *
 * This file: constants and other shared information for both PRU programs.
 *
 * Comments may refer to various manuals by abbreviations:
 *    TRM: AM335x Technical Reference Manual
 *    PRG: AM335x PRU Reference Guide
 */

#ifndef APHD_PRU_COMMON_H_
#define APHD_PRU_COMMON_H_


/* //////////////////////
//// I/O PIN ALIASES ////
////////////////////// */

/* Control lines are unidirectional, so we can refer to them via constants
 * whether we are retrieving or sending data. */

#define pBSY      r30.t8
#define psBSY     "r30.t8"
#define ppBSY     8

#define pCMD      r31.t9
#define psCMD     "r31.t9"
#define ppCMD     9

#define pPARITY   r30.t14
#define psPARITY  "r30.t14"
#define ppPARITY  14

#define pRW       r31.t15    /* NOTE: This signal is PEX2 on the schematic, */
#define psRW      "r31.t15"  /* not PR/\W. */
#define ppRW      15

#define pSTRB     r31.t16
#define psSTRB    "r31.t16"
#define ppSTRB    16


/* /////////////////////////
//// INTERRUPT HANDLING ////
///////////////////////// */

#define ePRU0to1 16U  /* System event for interrupts from PRU0 to PRU1 */
#define ePRU1to0 17U  /* System event for interrupts from PRU1 to PRU0 */
#define ePRU1toARM 18U  /* System event for interrupts from PRU1 to ARM */
#define eARMtoPRU1 19U  /* System event for interrputs from ARM to PRU1 */
/* Note: The Linux kernel device tree for the Beagles specify system events
 * 16 and 17 for RPMsg kicks between PRU0 and the ARM, and system events
 * 18 and 19 for RPMsg kicks between PRU1 and the ARM. Events 16 and 18 go
 * to the ARM; events 17 and 19 go to the PRU. */

#define sPRU0to1 16U + ePRU0to1  /* For raising a PRU0 to PRU1 system event */
#define sPRU1to0 16U + ePRU1to0  /* For raising a PRU1 to PRU0 system event */
#define sARMtoPRU1 16U + eARMtoPRU1  /* For raising an ARM to PRU1 sysevent */

#define iAnyToPRU1 31U  /* R31 bit indicating any interrupt to PRU1 */
#define iPRU1to0 30U    /* R31 bit indicating an interrupt from PRU1 to PRU0 */
/* Note: The resource table must ultimately map:
 *   system event ePRU0to1 to host interrupt (iAnyToPRU1 - 30),
 *   system event ePRU1to0 to host interrupt (iPRU1to0 - 30), and
 *   system event eARMtoPRU1 to host interrupt (iAnyToPRU1 - 30)
 * for these definitions to be correct. */


/* ////////////////////
//// CONST ALIASES ////
//////////////////// */

/* Aliases for various const registers (PRG 5.2.1). */

#define cINTC    c0   /* Pointer to PRU INTC */
#define cCONFIG  c4   /* Pointer to PRU_SYSCFG */
#define cSHARED  c28  /* Pointer to shared PRU RAM */

/* Aliases for offsets from various const registers. */

#define oINTC_SICR 0x24  /* cINTC offset to SICR register */


/* /////////////////////////
//// DATA PUMP COMMANDS ////
///////////////////////// */

#define dREAD    0x00  /* Read a block of data from the data lines */
#define dWRITE   0x01  /* Write a block of data to the data lines */
#define dINVALID 0x80  /* An intentional nonsense command, used for resets */


#endif  /* APHD_PRU_COMMON_H_ */
