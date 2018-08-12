; Aphid: Apple parallel port hard drive emulator for Cameo
;
; Forfeited into the public domain with NO WARRANTY. Read LICENSE for details.
;
; This file: firmware for PRU 0
;
; PRU 0 is a "data pump" and parity calculator that controls the parallel
; port's data lines and \PPARITY signal. It operates in any of three modes:
;   1. Idling: it polls the data lines to compute the \PPARITY signal.
;   2. Reading: incoming data, clocked by \PSTRB, is stored in shared RAM;
;      the \PPARITY signal is also calculated as in idle mode.
;   3. Writing: outgoing data, clocked by \PSTRB, is served from shared RAM;
;      the \PPARITY signal is precomputed externally and also served from RAM.
;
; PRU 0 loops in idle mode by default. When it receives a host 0 interrupt
; (i.e. when r31.t30 goes high), it examines the following command data
; structure at the low end of the shared memory space:
;
;   Byte 0: (reserved for "return code")
;        1: command; 0x00 for reading in data, 0x01 for writing data out
;      2-3: number of bytes/words to read in/write out
;      4-7: address (in PRU0's address space) to read/write data from/to.
;
; After entering the corresponding mode and completing the specified command,
; the PRU places a "return value" in byte 0 above and dispatches a host 0
; interrupt. Return codes are:
;
;   0: Last operation was successful
;   1: Command dispatch unsuccessful (usually means: command unrecognised)
;   2: Read mode timed out waiting for \PSTRB to go low
;   3: Read mode timed out waiting for \PSTRB to go high
;   4: Write mode timed out waiting for \PSTRB to go low
;   5: Write mode timed out waiting for \PSTRB to go high
;   6: Write mode was cancelled prematurely.
;
; The write operation (but not reads) can be cancelled by issuing an ePRU1to0
; system event while the operation is in progress. See WRITE for details.
;
; When reading, PRU 0 stores bytes from the data lines contiguously in memory,
; starting from the address specified in the command data structure. When
; writing, PRU 0 expects the memory at the specified address to contain a
; sequence of precomputed <data byte><parity byte> pairs: <data byte> will be
; placed onto the data lines, and the sixth bit of <parity byte> will be copied
; to the \PPARITY line. (All other <parity byte> bits are ignored, so it's safe
; to use values like 0x00 and 0xff.)
;
; Although the code in this file is arranged into "subroutine-like" blocks,
; there are no subroutines per se; the JAL instruction is not used. Instead,
; control jumps between the various blocks as shown:
;
;               read ordered ,--->[READ]----. read complete
;                            |              |
;                            |              v
;       ----->[INIT]----->[IDLE]<-------[REPORT]
;                            |              ^
;                            |              |
;              write ordered `--->[WRITE]---' write complete
;
; The interrupt controller setup assumed by this firmware is described by a
; resource table definition in the accompanying file aphd_pru0_resource_table.c.
; Note that ordinarily an empty resource table is used in lieu of this
; definition, since it's expected that the PRU 1 firmware will specify
; interrupt controller configuration.
;
; Registers used:
;   Initialisation <INIT>:
;      R0: scratch
;      R1: scratch
;   Awaiting a command <IDLE>
;      R2: scratch
;   Reading a byte off of the data lines <mRead>:
;      R3: data in
;   Writing a byte onto the data lines <mWrite>:
;      R4: data out
;   Computing parity for last byte read off of the data lines <mParity>:
;      R5: scratch
;   Idling and then interpreting the command data structure <IDLE>:
;      R6: command data structure, first half
;      R7: read/write memory buffer pointer
;   Externally-clocked multiple byte reads <READ>:
;      R8: address receiving the next byte read from the data lines
;      R9: one byte beyond the address receiving the last byte
;     R10: scratch
;   Externally-clocked multiple byte writes <WRITE>:
;     R11: address of the next word to send out over the data and parity lines
;     R12: two bytes beyond the address of the last word to send
;     R13: scratch
;
;   Statistics:
;     R15: total bytes the datapump has been requested to read in
;     R16: total bytes the datapump has successfully read in
;     R17: total words the datapump has been requested to write out
;     R18: total words the datapump has successfully written out
;
;   Constants:
;     R20: Value to write to INTC SICR to clear interrupt from PRU 1
;     R21: GPIO3 base address plus 0x100: 0x481Ae100
;     R22: 16-bit odd parity bit lookup constant: 0x9669
;     R23: 0x00000000
;     R24: 0x11111111
;
; Revision history:
;   1: New file, by stepleton@gmail.com, London


;;;;;;;;;;;;;;;;;;;;;
;;;; FRONTMATTER ;;;;
;;;;;;;;;;;;;;;;;;;;;


    ; Naming conventions:
    ;   - cTHING:   Const register for "THING"
    ;   - eEVENT:   Identifier for system event "EVENT"
    ;   - iINT:     Bit for interrupt "INT"
    ;   - oOFFSET:  Memory offset pertaining to "OFFSET"
    ;   - pSIGNAL:  PRU input or output (r31/r30) AND pin for signal "SIGNAL"
    ;   - ppSIGNAL: PRU input or output pin for signal "SIGNAL"
    ;   - rFOO:     register for important variable or constant "FOO"
    ;   - rs_BAR:   scratch register for "BAR" subroutine
    ;   - sEVENT:   Value to use to raise system event "EVENT"

    .cdecls "aphd_pru_common.h"

    .asg    r0, rs_INITD             ; Scratch register for data, in INIT
    .asg    r1, rs_INITA             ; Scratch register for addresses, in INIT
    .asg    r2, rs_IDLE              ; Scratch register for IDLE
    .asg    r3, rGPIO_IN             ; Register storing input from data lines
    .asg    r4, rGPIO_OUT            ; Register for data to write to data lines
    .asg    r5, rs_PRTY              ; Scratch register for mParity
    .asg    r6, rCOMMAND             ; First half of the command data structure
    .asg    r7, rBUFFER              ; Second half: read/write buffer address
    .asg    r8, rREAD                ; Read buffer pointer
    .asg    r9, rREAD_END            ; End of read buffer
    .asg    r10, rs_READ             ; Scratch register for READ
    .asg    r11, rWRITE              ; Write buffer pointer
    .asg    r12, rWRITE_END          ; End of write buffer
    .asg    r13, rs_WRITE            ; Scratch register for WRITE

    .asg    r15, rR_ASK              ; Total bytes we were requested to read
    .asg    r16, rR_DONE             ; Total bytes actually read from data lines
    .asg    r17, rW_ASK              ; Total words we were requested to write
    .asg    r18, rW_DONE             ; Total words actually written out

    .asg    r20, rCLEAR_INT          ; Register storing interrupt-clearing value
    .asg    r21, rGPIO_B100          ; Register storing GPIO3 base address+0x100
    .asg    r22, rPRTY_TABL          ; Register storing parity lookup table
    .asg    r23, rZEROS              ; Register storing 0x00000000
    .asg    r24, rONES               ; Register storing 0xFFFFFFFF

    ; These constants are offsets from the GPIO base address less 0x100.
    ; Placing 0x100 of the base offset in rGPIO_B100 (instead of just
    ; adding an offset directly to the GPIO base address) means that we
    ; can use LBBO and SBBO with these values as immediate value offsets.
    .asg    0x34, oGPIO_OE           ; GPIO output enable reg. offset less 0x100
    .asg    0x38, oGPIO_DIN          ; GPIO DATAIN register offset less 0x100
    .asg    0x3C, oGPIO_DOUT         ; GPIO DATAOUT register offset less 0x100


;;;;;;;;;;;;;;;;
;;;; MACROS ;;;;
;;;;;;;;;;;;;;;;


;;;;; mRead -- Read a byte off of the data lines
;;;;; Args:
;;;;;   rGPIO_IN: register receiving the byte from the data lines
    ;   rGPIO_B100: <constant> base addr+0x100 for GPIO memory-mapped registers
    ; Notes:
    ;   The data lines should be in input mode (see the mDirIn macro).
    ;   Only the LSbyte of rGPIO_IN will contain valid data.
    ;   No other contents of rGPIO_IN will be preserved.
mRead         .macro
      LBBO    &rGPIO_IN, rGPIO_B100, oGPIO_DIN, 4  ; Read GPIO global address
      LSR     rGPIO_IN, rGPIO_IN, 14   ; Shift data into least-significant byte
              .endm


;;;;; mWrite -- Write a byte onto the data lines
;;;;; Args:
;;;;;   rGPIO_OUT: register whose LSbyte is the data to write to the data lines
    ;   rGPIO_B100: <constant> base addr+0x100 for GPIO memory-mapped registers
    ; Notes:
    ;   The data lines should be in output mode (see the mDirOut macro).
    ;   All contents of rGPIO_OUT will be destroyed.
mWrite        .macro
      LSL     rGPIO_OUT, rGPIO_OUT, 14   ; Shift data from LSbyte
      SBBO    &rGPIO_OUT, rGPIO_B100, oGPIO_DOUT, 4  ; Write to GPIO glob. addr.
              .endm


;;;;; mDirIn -- Switch data lines to input mode to receive data in
;;;;; Args:
;;;;;   rONES: <constant> 0xFFFFFFFF
    ;   rGPIO_B100: <constant> base addr+0x100 for GPIO memory-mapped registers
    ; Notes:
    ;   (none)
mDirIn        .macro
      SBBO    &rONES, rGPIO_B100, oGPIO_OE, 4  ; Make all GPIO pins inputs
              .endm


;;;;; mDirOut -- Switch data lines to output mode to send data out
;;;;; Args:
;;;;;   rZEROS: <constant> 0x00000000
    ;   rGPIO_B100: <constant> base addr+0x100 for GPIO memory-mapped registers
    ; Notes:
    ;   (none)
mDirOut       .macro
      SBBO    &rZEROS, rGPIO_B100, oGPIO_OE, 4   ; Make all GPIO pins outputs
              .endm


;;;;; mParity -- Set pPARITY for the last byte read from the data lines
;;;;; Args:
;;;;;   rGPIO_IN: mParity sets the pPARITY line for data in rGPIO_IN's LSbyte.
    ;   rPRTY_TABL: <constant> value 0x6996 for even parity, 0x9669 for odd.
    ; Notes:
    ;   Based on
    ;       http://graphics.stanford.edu/~seander/bithacks.html#ParityParallel
    ;   Trashes rs_PRTY.
mParity       .macro
      LSR     rs_PRTY.b0, rGPIO_IN.b0, 4             ; v  = data >> 4
      XOR     rs_PRTY.b0, rGPIO_IN.b0, rs_PRTY.b0    ; v ^= data
      AND     rs_PRTY.b0, rs_PRTY.b0, 0x0f           ; v &= 0x0f
      LSR     rs_PRTY.w0, rPRTY_TABL.w0, rs_PRTY.b0  ; v  = 0x6996 >> v
      QBBS    __On?, rs_PRTY, 0      ; Parity bit is now in rs_PRTY, bit 0
      CLR     r30, pPARITY           ; It was 0, so clear the parity line
      QBA     __Done?
__On?:
      SET     r30, pPARITY           ; It was 1, so set the parity line
__Done?:
              .endm


;;;;;;;;;;;;;;
;;;; CODE ;;;;
;;;;;;;;;;;;;;


;;;;; INIT -- Global initialisation for the "datapump" firmware
;;;;; Args:
;;;;;   (none)
    ; Notes:
    ;   Entry point to the firmware.
    ;   Sets important constants for macros, etc.
    ;   Falls through to IDLE.
    .global INIT
INIT:
    ; Enable OCP master port so we can control pins through the GPIO subsystem.
    LBCO    &rs_INITD, cCONFIG, 4, 4   ; Load PRU SYSCFG register contents
    CLR     rs_INITD, rs_INITD, 4    ; Zap STANDBY_INIT; enables OCP master port
    SBCO    &rs_INITD, cCONFIG, 4, 4   ; Store updated PRU SYSCFG
    ; Configure the shared memory offset for the cSHARED const register.
    LDI32   rs_INITA, 0x00022000     ; Load location of PRU 0 control registers
    LBBO    &rs_INITD, rs_INITA, 0x28, 4   ; Load PRU CTPPR0 register contents
    LDI     rs_INITD.w0, 0x0100      ; Set 0x10000 shared memory offset
    SBBO    &rs_INITD, rs_INITA, 0x28, 4   ; Store updated PRU CTPPR0
    ; Clear statistics.
    LDI     rR_ASK, 0                ; Total bytes we were requested to read
    LDI     rR_DONE, 0               ; Total bytes actually read from data lines
    LDI     rW_ASK, 0                ; Total words we were requested to write
    LDI     rW_DONE, 0               ; Total words actually written out
    ; Set constants.
    LDI32   rCLEAR_INT, ePRU1to0     ; Set interrupt-clearing value
    LDI32   rGPIO_B100, 0x481AE100   ; Set GPIO base address + 0x100
    LDI     rPRTY_TABL.w0, 0x9669    ; Set parity word for mParity
    LDI32   rZEROS, 0x00000000       ; Set all-zeros register
    LDI32   rONES, 0xFFFFFFFF        ; Set all-ones register
    ; Configure data pins as inputs.
    mDirIn
    ; Clear the interrupt PRU 1 uses to invoke a datapump operation.
    SBCO    &rCLEAR_INT, cINTC, oINTC_SICR, 4  ; Write to SICR to clear int.
    ; Fall through now to IDLE.


;;;;; IDLE -- Idle loop and command dispatch
;;;;; Args:
;;;;;   (none)
    ; Notes:
    ;   Awaits a host 1 interrupt from PRU 1, signifying that a new command has
    ;       been placed at the beginning of PRU shared RAM. See documentation
    ;       at the top of this file for details on the contents and formatting
    ;       of the command structure.
    ;   After handling a read command, the host 1 interrupt will be cleared by
    ;       the REPORT subroutine. For write commands, the interrupt clearing
    ;       happens prior to the jump to WRITE; this allows it to detect and
    ;       handle operation-cancelling interrupts from PRU1.
    ;   Error codes from command dispatch and I/O routines are placed in the
    ;       first byte of shared PRU RAM. Values are:
    ;         0: Success
    ;         1: Unrecognised command
    ;         2-3: Errors in READ (see READ documentation)
    ;         4-6: Errors in WRITE (see WRITE documentation).
IDLE:
    mRead                            ; Read data lines
    mParity                          ; Update parity bit for data on lines
    QBBC    IDLE, r31, iPRU1to0      ; Keep idling if no interrupt
    ; Interrupt received; download command data structure and decode.
    LBCO    &rCOMMAND, cSHARED, 0, 8   ; Download command data structure
    QBEQ    _I_READ, rCOMMAND.b1, dREAD    ; Handle a read command
    QBEQ    _I_WRITE, rCOMMAND.b1, dWRITE  ; Handle a write command
    ; Unrecognised command; report error and resume idling.
    LDI     rCOMMAND.b0, 0x01        ; Error 1 means unrecognised command
    SBCO    &rCOMMAND.b0, cSHARED, 0, 1  ; Store result in bottom of shared RAM
    QBA     REPORT                   ; Report to PRU 1; return to idle loop

    ; Handle a read command and resume idling.
_I_READ:
    MOV     rREAD, rBUFFER           ; Make buffer start address arg for READ
    ADD     rREAD_END, rREAD, rCOMMAND.w2  ; Make buffer end address (exclusive)
    QBA     READ                     ; Perform read; return to idle loop

    ; Handle a write command and resume idling.
_I_WRITE:
    SBCO    &rCLEAR_INT, cINTC, oINTC_SICR, 4  ; Write to SICR to clear int.
    SBCO    &rONES.b0, cSHARED, 1, 1   ; Preset command to cancel in shared mem.
    MOV     rWRITE, rBUFFER          ; Make buffer start address arg for WRITE
    LSL     rs_IDLE.w0, rCOMMAND.w2, 1   ; Convert word count to byte count
    ADD     rWRITE_END, rWRITE, rs_IDLE.w0   ; Make buffer end addr. (exclusive)
    QBA     WRITE                    ; Perform write; return to idle loop


;;;;; READ -- Externally-clocked data read to memory from the data lines
;;;;; Args:
;;;;;   rREAD: lower bound byte address of the buffer for incoming data
    ;   rREAD_END: upper bound byte address (exclusive) of the buffer
    ; Notes:
    ;   READ places a result code in the first byte of shared PRU RAM. Values:
    ;       0: Buffer filled; all data successfully read.
    ;       2: Timed out waiting for host to lower \PSTRB.
    ;       3: Timed out waiting for host to raise \PSTRB.
READ:
_R_OUTER:
    ; Outer READ loop begins immediately.
    QBGE    _R_SUCCESS, rREAD_END, rREAD   ; Jump to exit if all bytes are read

    ; Wait for \PSTRB to go low.
    LDI     rs_READ.w0, 0xffff       ;   65536 iterations of the following:
    LOOP    _R_INNER_1, rs_READ.w0   ;     Loop waiting for \PSTRB to go low
    mRead                            ;     Read data lines
    mParity                          ;     Update parity bit for data on lines
    QBBC    _R_PSTRB_LO, r31, ppSTRB   ;   Exit loop if \PSTRB is low
_R_INNER_1:
    LDI     rCOMMAND.b0, 2           ;   Error 2 means we timed out waiting...
    QBA     _R_DONE                  ;   ...for \PSTRB to go low

    ; Wait for \PSTRB to go high.
_R_PSTRB_LO:
    LDI     rs_READ.w0, 0xffff       ;   65536 iterations of the following:
    LOOP    _R_INNER_2, rs_READ.w0   ;     Loop waiting for \PSTRB to go high
    mRead                            ;     Read data lines
    mParity                          ;     Update parity bit for data on lines
    QBBS    _R_PSTRB_HI, r31, ppSTRB   ;   Exit loop if \PSTRB is high
_R_INNER_2:
    LDI     rCOMMAND.b0, 3           ;   Error 3 means we timed out waiting...
    QBA     _R_DONE                  ;   ...for \PSTRB to go high

    ; Add the byte to the data buffer, then return to the top of the outer loop
    ; for the next byte.
_R_PSTRB_HI:
    SBBO    &rGPIO_IN, rREAD, 0, 1   ;   Copy last input byte to the buffer
    ADD     rREAD, rREAD, 1          ;   Point rREAD to the next byte in memory
    QBA     _R_OUTER                 ; End outer loop

_R_SUCCESS:
    LDI     rCOMMAND.b0, 0           ; Successful read: error 0
_R_DONE:
    ; Update statistics.
    ADD     rR_ASK, rR_ASK, rCOMMAND.w2  ; Update read-requested total
    SUB     rs_READ, rREAD_END, rREAD  ; How many bytes were left to read?
    SUB     rs_READ, rCOMMAND.w2, rs_READ  ; Compute bytes successfully read
    ADD     rR_DONE, rR_DONE, rs_READ  ; Update read-successfully total
    ; Export error result (value in rCOMMAND.b0) via shared RAM, then return.
    SBCO    &rCOMMAND.b0, cSHARED, 0, 1  ; Store result on bottom of shared RAM
    QBA     REPORT                   ; Signal PRU 1; return to idle loop


;;;;; WRITE -- Externally-clocked data write from memory to the data lines
;;;;; Args:
;;;;;   rWRITE: lower bound word address of the buffer for incoming data
    ;   rWRITE_END: upper bound word address (exclusive) of the buffer
    ; Notes:
    ;   Write data must be supplied as <data byte><parity byte> pairs, with
    ;       the sixth bit of <parity byte> supplying odd parity for <data byte>.
    ;       The other bits are ignored, so it is safe to use values like 0x00
    ;       and 0xFF, provided the sixth bit is set appropriately.
    ;   WRITE places a result code in the first byte of shared PRU RAM. Values:
    ;       0: Buffer filled; all data successfully read.
    ;       4: Timed out waiting for host to lower \PSTRB.
    ;       5: Timed out waiting for host to raise \PSTRB.
    ;       6: WRITE was interrupted prematurely.
    ;   It is possible to cancel WRITE operations in progress by issuing an
    ;       ePRU1to0 system event. WRITE will complete with result code 0
    ;       (success) if it has already placed the final byte from memory onto
    ;       the data lines, but a cancelling interrupt at any other time will
    ;       yield result code 6. The ProFile handshake undertaken by some Apple
    ;       Lisa software (including the Office System) requires this
    ;       complication, as certain handshake bytes are not clocked via \PSTRB.
    ;   WRITE changes the command in the command data structure in shared memory
    ;       space from $01 (the command that invoked WRITE in the first place)
    ;       to $FF. It does this to avoid a race condition in which the WRITE
    ;       completes just before a cancelling interrupt is received, at which
    ;       point the cancelling interrupt would just look like an interrupt
    ;       intended to start a new data pump operation.
WRITE:
    mDirOut                          ; Set data lines to output mode
    ; Outer WRITE loop begins.
_W_OUTER:
    QBGE    _W_SUCCESS, rWRITE_END, rWRITE   ; Jump to exit if all words written

    ; Copy out the next word (data byte and byte with the parity bit).
    LBBO    &rs_WRITE, rWRITE, 0, 2  ;   Copy word from RAM to scratch register
    ADD     rWRITE, rWRITE, 2        ;   Point rWRITE to the next word in memory
    MOV     rGPIO_OUT.b0, rs_WRITE.b0  ; Copy data byte to data out register
    mWrite                           ;   Write data byte to data lines
    MOV     r30.b1, rs_WRITE.b1      ;   Write parity bit to PRU output lines

    ; Wait for \PSTRB to go low.
    LDI     rs_WRITE.w0, 0xffff      ;   65536 iterations of the following
    LOOP    _W_INNER_1, rs_WRITE.w0  ;     Loop waiting for \PSTRB to go low
    QBBC    _W_PSTRB_LO, r31, ppSTRB   ;   Exit loop if \PSTRB is low
    QBBS    _W_INTR, r31, iPRU1to0   ;     Handle cancellation if interrupted
_W_INNER_1:
    LDI     rCOMMAND.b0, 4           ;     Error 4 means we timed out waiting...
    QBA     _W_DONE                  ;     ...for PSTRB to go low

    ; Wait for \PSTRB to go high. Note the jump to the top of the outer loop...
_W_PSTRB_LO:
    LDI     rs_WRITE.w0, 0xffff      ;   65536 iterations of the following
    LOOP    _W_INNER_2, rs_WRITE.w0  ;     Loop waiting for \PSTRB to go high
    QBBS    _W_OUTER, r31, ppSTRB    ;     Exit loop if \PSTRB is high
    QBBS    _W_INTR, r31, iPRU1to0   ;     Handle cancellation if interrupted
_W_INNER_2:
    LDI     rCOMMAND.b0, 5           ;     Error 5 means we timed out waiting...
    QBA     _W_DONE                  ;     ...for PSTRB to go high

    ; If here, all bytes are successfully written.
_W_SUCCESS:
    LDI     rCOMMAND.b0, 0           ; We mark success with error 0
_W_DONE:
    mDirIn                           ; Set data lines to input mode
    ; Update statistics.
    ADD     rW_ASK, rW_ASK, rCOMMAND.w2  ; Update write-requested total
    SUB     rs_WRITE, rWRITE_END, rWRITE   ; How many bytes were left to write?
    LSR     rs_WRITE, rs_WRITE, 1    ; Convert bytes to words
    SUB     rs_WRITE, rCOMMAND.w2, rs_WRITE  ; Compute words successfully wrote
    ADD     rW_DONE, rW_DONE, rs_WRITE   ; Add to successfully-written total
    ; Export error result (value in rCOMMAND.b0) via shared RAM, then return.
    SBCO    &rCOMMAND.b0, cSHARED, 0, 1  ; Store result on bottom of shared RAM
    QBA     REPORT                   ; Signal PRU 1; return to idle loop

    ; If here, PRU1 has interrupted the write operation.
_W_INTR:
    mDirIn                           ; Set data lines to input mode
    ; Update statistics.
    ADD     rW_ASK, rW_ASK, rCOMMAND.w2  ; Update write-requested total
    SUB     rs_WRITE, rWRITE_END, rWRITE   ; How many bytes were left to write?
    LSR     rs_WRITE, rs_WRITE, 1    ; Convert bytes to words
    SUB     rs_WRITE, rCOMMAND.w2, rs_WRITE  ; Compute words successfully wrote
    ADD     rW_DONE, rW_DONE, rs_WRITE   ; Add to successfully-written total
    ; Base error result on whether this interrupt stopped us prematurely.
    QBEQ    _W_INTR_OK, rs_WRITE, rCOMMAND.w2  ; Did we write all the words?
    LDI     rCOMMAND.b0, 6           ; No, we were interrupted prematurely
    SBCO    &rCOMMAND.b0, cSHARED, 0, 1  ; Store result on bottom of shared RAM
    QBA     REPORT                   ; Signal PRU 1; return to idle loop
_W_INTR_OK:
    LDI     rCOMMAND.b0, 0           ; Yes, we did write all the words!
    SBCO    &rCOMMAND.b0, cSHARED, 0, 1  ; Store result on bottom of shared RAM
    ; QBA     REPORT                 ; Signal PRU 1; return to idle loop
                                     ; Or just fall through instead of branching


;;;;; REPORT -- Report completion of a datapump operation to PRU 1
;;;;; Args:
;;;;;   (none)
    ; Notes:
    ;   Updates the copy of the usage statistics in shared memory.
    ;   Clears the host 1 interrupt that IDLE received from PRU 1.
    ;   Triggers a host 0 interrupt to inform PRU 1 that the datapump operation
    ;       has completed.
REPORT:
    ; Update the copy of the usage statistics in shared memory.
    SBCO    &rR_ASK, cSHARED, 8, 16  ; Place them just after the command struct
    ; Clear the interrupt PRU 1 used to invoke a datapump operation.
    SBCO    &rCLEAR_INT, cINTC, oINTC_SICR, 4  ; Write to SICR to clear int.
    LDI     r31.b0, sPRU0to1         ; Fire off an interrupt to PRU1
    QBA     IDLE                     ; Return to the idle loop
