* Cameo/Aphid disk image selector: Screensaver
* ============================================
*
* Forfeited into the public domain with NO WARRANTY. Read LICENSE for details.
*
* A compact implementation of Rule 30 that scrolls up the screen, hopefully
* averting burn-in.
*
* These procedures make use of the `lisa_console_kbmouse.x68` and
* `lisa_console_screen.x68` components from the `lisa_io` library. Before using
* any routine defined below, both of those components must have been initialised
* via the `InitLisaConsoleKbMouse` and `InitLisaConsoleScreen` procedures.
*
* Public procedures:
*    - UiScreensaver -- Display a pattern that occupies the screen
*    - UiScreensaverWaitForKb -- Await keypress or do screensaver after a delay


* ui_screensaver Code ---------------------------


    SECTION kSecCode


    ; UiScreensaverWaitForKb -- Await keypress or do screensaver after a delay
    ; Args:
    ;   (none)
    ; Notes:
    ;   Flushes the COPS input buffer immediately after being called
    ;   The delay to jump to the screensaver is fixed at about 90 seconds
    ;   Z is set if the user pressed a glyph key; if clear, the screensaver ran
    ;       instead and the user has interrupted it, so redraw and start over
    ;   Note: this means the loops you build around this routine will differ
    ;       from ones you make for the LisaConsole___KbMouse routines.
    ;   Trashes D0-D1/A0-A1
UiScreensaverWaitForKb:
    MOVEM.W D2-D3,-(SP)          ; Save registers we use
    BSR     FlushCops            ; Dump out the COPS input buffer
    MOVE.W  #$0059,D3            ; Repeat 90 times
.pl MOVE.W  #$FFFE,D2            ; Number of times to poll the COPS
    BSR     LisaConsoleDelayForKbMouse   ; Poll the COPS for input
    BEQ.S   .rt                  ; Glyph key pressed? Jump to exit
    BCS.S   .pl                  ; Other COPS byte? Restart this polling round
    DBRA    D3,.pl               ; Otherwise onto the next round of polling

    BSR.S   UiScreensaver        ; Timed out; run the screensaver
    ANDI.B  #$FB,CCR             ; Clear Z to tell the caller we timed out
.rt MOVEM.W (SP)+,D2-D3          ; Restore saved registers
    RTS


    ; UiScreensaver -- Display a pattern that occupies the screen
    ; Args:
    ;   (none)
    ; Notes:
    ;   Press a key to exit the screensaver
    ;   Trashes D0-D1/A0-A1
UiScreensaver:
    MOVEM.L D2-D6/A2,-(SP)       ; Save registers we use

    ; Hint that the Lisa isn't glitching out
    mUiGotoRc   #$23,#$10        ; Jump to the bottom of the screen
    mUiPrint  <'[Screensaver]'>  ; Note no descenders to interfere with the FA

    ; Initialise constants and other state
    MOVE.L  #$1E1E1E1E,D3        ; Repeated Rule 30 bitmap for BTST lookups
    LEA.L   zLisaConsoleKbCode(PC),A2   ; Point A2 at the last raw keycode
    MOVE.W  $1BE,D6              ; Seed RNG with bits from the boot time

    ; Initialise the bottom row of the display --- plus the last word of the row
    ; before that
.in MOVEA.L zLisaConsoleScreenBase(PC),A0  ; Start of the display buffer into A0
    ADDA.W  #$7F9C,A0            ; Advance to bottom line of the screen (almost)
    MOVEQ.L #$2D,D1              ; Prepare to clear 46 words
.cl CLR.W   (A0)+                ; Clear this word, advance the pointer
    DBRA    D1,.cl               ; Loop to clear the next word
    ADDQ.B  #$1,-46(A0)          ; Make the very tip of the Rule 30 pyramid

    ; Scroll the entire display up one pixel; leave bottom row unchanged
    ; This is the top of the outermost loop
.lo MOVE.W  SR,-(SP)             ; Save current interrupts
    ORI.W   #$700,SR             ; Now clear the interrupts for speed
    MOVEA.L zLisaConsoleScreenBase(PC),A0  ; Start of the display buffer into A0
    LEA.L   $5A(A0),A1           ; Point A1 90 bytes ahead
    MOVE.W  #$3FCE,D1            ; Prepare to move 16,635 words
.sl MOVE.W  (A1)+,(A0)+          ; Copy this word, advance pointers
    DBRA    D1,.sl               ; Loop to copy the next word

    ; Initialise the input sliding window for the rightmost edge, where we
    ; imagine the state of the bit just to the right of the edge of the screen
    ; to be 0 if the rightmost bit of the prior line is 0 and random if it is 1
    CLR.W   D1                   ; Clear bottom of the input sliding window
    BTST.B  #$0,-1(A0)           ; Should we inject randomness into this edge?
    BEQ.S   .no                  ; No, the bit was 0
    MOVE.L  D6,D1                ; Yes, put it in there
.no SWAP.W  D1                   ; And move whatever out of the way of the...
    MOVE.W  -(A0),D1             ; ...rightmost word of the prior line
    ROL.L   #$2,D1               ; Now set it up for the loop

    ; The middle loop computes all 45 words of the current line
    MOVEQ.L #$2C,D5              ; Prepare to repeat 45 times
.lm CLR.W   D2                   ; Clear the output sliding window

    ; First we compute just two of the bits of the output word
    MOVEQ.L #$1,D4               ; Prepare to repeat twice
.l1 ROR.L   #$1,D1               ; Advance the input sliding window one bit
    BTST.L  D1,D3                ; Should we set this bit in the output window?
    BEQ.S   .c1                  ; No, leave it clear
    ADDQ.B  #$1,D2               ; Yes, set the bit (short instruction)
.c1 ROR.W   #$1,D2               ; Advance the output sliding window one bit
    DBRA    D4,.l1               ; Loop to do the second bit

    ; Load the next input word from the prior generation into the upper word
    SWAP.W  D1                   ; Move input window contents out of the way
    MOVE.W  -(A0),D1             ; Copy in the next word from prior generation
    SWAP.W  D1                   ; Move input window contents back

    ; Now we compute the remaining 14 bits of the output word
    MOVEQ.L #$D,D4               ; Prepare to repeat 14 times
.l2 ROR.L   #$1,D1               ; Advance the input sliding window one bit
    BTST.L  D1,D3                ; Should we set this bit in the output window?
    BEQ.S   .c2                  ; No, leave it clear
    ADDQ.B  #$1,D2               ; Yes, set the bit (short instruction)
.c2 ROR.W   #$1,D2               ; Advance the output sliding window one bit
    DBRA    D4,.l2               ; Loop to do another bit

    ; The output word is full; write it to the screen, start a new output word
    MOVE.W  D2,-(A1)             ; Commit the output sliding window
    DBRA    D5,.lm               ; Repeat middle loop

    ; Now that we're out of the loop, advance the Galois LFSR that gives us the
    ; randomness that we inject into the rightmost edge
    ROL.W   #$1,D6               ; The LFSR's rotate step
    BCC.S   .kb                  ; Skip ahead if the rotated bit was 0
    EORI.W  #$002C,D6            ; Otherwise, flip certain bits

    ; See if there's a key-up event or if the mouse has moved
.kb MOVE.W  (SP)+,SR             ; Restore interrupts
.kp CLR.B   (A2)                 ; Clear the last raw keycode
    BSR     LisaConsolePollKbMouse  ; Poll the COPS for events
    BCC.S   .lo                  ; No byte at all? Another round please
    ROXR.W  #$1,D4               ; Rotate the X bit into D4's MSBit
    BMI.S   .kp                  ; If X had been set, we need to poll again
    TST.B   (A2)                 ; Did we get a key event from the COPS?
    BLE.S   .lo                  ; No, or it was a keydown, so one more round

    ; If the key-up was the Backspace key, then it's an easter egg: XOR the
    ; lower word of the Rule 30 bitmap in D3 with LFSR state, rotate it one bit
    ; left, and start all over; note that this results in an automaton that's
    ; different to an elementary cellular automaton, since a bits value depends
    ; on the value of itself, its right neighbour, and its *3* left neighbours.
    CMPI.B  #$45,(A2)            ; Was it key-up on the Backspace key?
    BNE.S   .rt                  ; No, jump to return to the caller
    EOR.W   D6,D3                ; XOR the LFSR state with the bitmap lower half
    ROL.L   #$1,D3               ; Rotate the bitmap one bit left.

    ; Photosensitivity guard! Any D3 bitmap where the MSBit is 0 and the LSBit
    ; is 1 will make a pattern with a rapidly alternating black and white lines,
    ; and since this produces a flickering image that could be hazardous to some
    ; users, we edit the bitmap to make this condition impossible
    BMI     .in                  ; If MSBit is 1, safe to start the pattern
    BCLR.L  #$0,D3               ; Otherwise we force the LSBit to be 0
    BRA     .in                  ; And then restart the pattern

    ; Got a key-up, so return to the caller
.rt MOVEM.L (SP)+,D2-D6/A2       ; Restore registers we use
    RTS
