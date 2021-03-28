* Cameo/Aphid disk image selector: certain final actions of the Selector
* ======================================================================
*
* Forfeited into the public domain with NO WARRANTY. Read LICENSE for details.
*
* Routines for powering down the Lisa and for ejecting floppy disks, which are
* among the last things that happen in any given Selector session (hence
* "outro").
*
* These routines make use of TODO
*
* Public procedures:
*    - EjectFloppies -- Cause all floppy drives to eject their disks
*    - PowerOff -- Eject floppy disks and shut down the Lisa


* drive Defines ---------------------------------

kFloppyIOB  EQU  $FCC001           ; Address of floppy IOB (control block)
kPVia_xRB   EQU  $FCD901           ; Address of parallel VIA xRB register
kKVia_xRB   EQU  $FCDD81           ; Address of keyboard VIA xRB register


* drive Code ------------------------------------


    SECTION kSecCode


    ; EjectFloppies -- Cause all floppy drives to eject their disks
    ; Args:
    ;   (none)
    ; Notes:
    ;   Will only try to eject the lower floppy drive on a Lisa 2
    ;   Z will be set if the script completes successfully
    ;   Fine to run this if drives contain no disks
    ;   If unsuccessful:
    ;       - D0.b is $F8 on timeout
    ;       - Otherwise the LSByte of D0 is the floppy error code **minus 7**
    ;       - D2 is $00 if we were trying to work with the upper drive,
    ;         $80 if we were trying to work with the lower drive
    ;   Trashes D0-D2/A0-A1
EjectFloppies:
    ; D1 will say which drive we're working with ($00: upper, $80: lower)
    TST.B   $2AF                   ; Is this a Lisa 1?
    SNE.B   D2                     ; If so, D1.b = $00; if not, $FF
    LSL.B   #$7,D2                 ; Turn $FF into $80 and $00 into $00

    ; Execute the "eject" script for this drive
.ej MOVE.B  D2,(kFloppyIOB+$4)     ; Set our drive selection in the IOB
    LEA.L   _kFloppyScriptEject(PC),A0  ; Point A0 at the "eject" script
    BSR.S   _FloppyScriptInterpreter  ; Execute the script
    BEQ.S   .nx                    ; No error? Skip ahead
    SUBQ.B  #$07,D0                ; Subtract the "no disk" error (ignore it)
    BNE.S   .rt                    ; If any other error, jump ahead to return

    ; Switch to the next drive
.nx ADD.B   #$80,D2                ; $00 becomes $80 becomes $00
    BNE.S   .ej                    ; If $80, loop to handle the lower drive
    ; Note Z will be set on fall-through

.rt RTS


    ; PowerOff -- Eject floppy disks and shut down the Lisa
    ; Args:
    ;   (none)
    ; Notes:
    ;   Also darkens the screen (brings the contrast right down)
    ;   Never returns
PowerOff:
    BSR     ClearLisaConsoleScreen   ; Blank the screen
    mUiPrint  r1c1,<'Turning off...'>  ; Tell the user we're turning off

    ; Eject and shut down floppies; who cares if it works
    BSR.S   EjectFloppies          ; First, eject any floppy disks
    LEA.L   _kFloppyScriptGoaway(PC),A0   ; Point A0 at the "go away" script
    BSR.S   _FloppyScriptInterpreter  ; Execute the script
    ; Turn down the contrast
    MOVEQ.L #$FF,D0                ; $FF means "contrast off"
    LEA.L   .dl(PC),A4             ; Unusually, we need a return address in A4
    JMP     $FE00B4                ; Call the contrast-set boot ROM routine
    ; Delay for a spell
.dl MOVEQ.L #$7,D0                 ; This value ($70000) will cause us a...
    SWAP.W  D0                     ; ...delay of about two seconds
.cd SUBQ.L  #$1,D0                 ; Countdown the delay
    BPL.S   .cd                    ; Loop until countdown is done
    ; Send the value $21 to the COPS (call) $FE00A8
.of MOVEQ.L #$21,D0                ; This is a power-off command
    JSR     $FE00A8                ; A boot ROM routine sends it to the COPS

    ; Wait forever to turn off
.lp BRA.S   .lp                    ; Tight infinite loop...


    ; _FloppyScriptInterpreter -- Execute a "floppy script"
    ; Args:
    ;   A0: "Floppy script" to execute; need not be word-aligned
    ;   FCC005: b. Use the upper drive if $00, use the lower if $80
    ; Notes:
    ;   A "floppy script" is a sequence of four-byte statements that modify the
    ;       contents of the floppy controller shared memory region (IOB) and
    ;       wait for something to happen
    ;   The first two bytes in a statement specify waiting conditions:
    ;       - Byte 0: If nonzero, poll the floppy controller's "gobyte" and
    ;         DSKDIAG bits up to 2^<this many> times, waiting for the controller
    ;         to stop being busy; then, after that:
    ;       - Byte 1: If nonzero, poll the floppy controller's FDIR flag up to
    ;         2^<bits 6..0> times, waiting for the controller to set its value
    ;         to the OPPOSITE of bit 7
    ;   The next two bytes in a statement specify modifications to the IOB that
    ;       are executed after the waiting conditions are met:
    ;       - Byte 2: Placed at shared memory region location $FCC003, this byte
    ;         is usually a parameter for:
    ;       - Byte 3: The "gobyte", a value which triggers the floppy controller
    ;         to take some kind of action when placed at shared memory region
    ;         location $FCC001
    ;   This interpreter executes bytes 0, 1, 2, and 3 of each statement of a
    ;       floppy script in order until an error condition is encountered (see
    ;       below) or until a Byte 3 with value $00 is encountered -- this marks
    ;       the end of a floppy script
    ;   If the interpreter reaches the end of a floppy script, the script will
    ;       be considered to have executed successfully, and this routine will
    ;       return with Z set and with $00 in the LSByte of D0
    ;   A floppy script will terminate abnormally if a waiting condition times
    ;       out or if the floppy controller is found to be in an error condition
    ;       after the normal (non-timeout) conclusion of both waiting conditions
    ;   On abnormal terminations due to timeout, the LSByte of D0 will be $FF,
    ;       Z will be clear, and A0 will point just past the waiting condition
    ;       that timed out
    ;   On abnormal terminations due to controller error conditions, the LSByte
    ;       of D0 will contain the error code (refer to the Lisa hardware manual
    ;       to interpret the code) and A0 will point at the instruction that
    ;       follows the instruction that failed
    ;   Trashes D0-D1/A0-A1
_FloppyScriptInterpreter:
    MOVEM.L A2-A4,-(SP)            ; Save A2, A3, A4 on the stack
    MOVE.W  SR,-(SP)               ; Save status register on the stack
    ORI.W   #$700,SR               ; Disable interrupts
    LEA.L   kFloppyIOB,A2          ; Floppy IOB (control block) address into A2
    LEA.L   kKVia_xRB,A3           ; Keyboard VIA xRB address into A3
    LEA.L   kPVia_xRB,A4           ; Parallel VIA xRB address into A4
    ANDI.B  #$EF,$4(A3)            ; Set keyboard VIA pin 4 to input
    ANDI.B  #$BF,$10(A4)           ; Set parallel VIA pin 6 to input
    CLR.B   $10(A2)                ; Manually clear error byte (for I/O ROM 40)
    BRA.S   .wb                    ; Scripts start by waiting on the controller

    ; Issue command to the floppy controller
.lp MOVE.B  (A0)+,$2(A2)           ; Load "function" byte into the IOB
    MOVE.B  (A0)+,D0               ; Load "gobyte" into D0
    BEQ.S   .rt                    ; It was 0; script done; return with Z set
    MOVE.B  D0,(A2)                ; Place into IOB, kicking off the command

    ; Wait for the floppy controller to stop being busy
.wb MOVE.B  (A0)+,D0               ; Load timeout exponent into D0
    BEQ.S   .wi                    ; No timeout listed; go wait on interrupts
    LEA.L   .hb(PC),A1             ; Point A1 at the "deassert busy" helper
    BSR.S   _FsiWaiter             ; Go wait on the busy bit
    BNE.S   .rt                    ; Quit on timeout

    ; Wait for the floppy controller interrupt bit to do something
.wi MOVE.B  (A0)+,D0               ; Load timeout exponent into D0
    BEQ.S   .er                    ; No timeout listed; jump to check for errors
    LEA.L   .ha(PC),A1             ; Point A1 at the "assert interrupt" helper
    BCLR.L  #$7,D0                 ; Or do we want to wait on a deassert?
    BEQ.S   .w_                    ; No, jump ahead to start waiting
    LEA.L   .hd(PC),A1             ; Point A1 at the "deassert interrupt" helper
.w_ BSR.S   _FsiWaiter             ; Go wait on the interrupt bit
    BNE.S   .rt                    ; Quit on timeout

    ; See if the controller is reporting an error condition; if not, loop
.er MOVE.B  $10(A2),D0             ; Load error byte into D0
    BEQ.S   .lp                    ; No error, so loop to the next instruction

    ; Cleanup and return
.rt MOVE.W  (SP)+,SR               ; Restore interrupts, but this changes the...
    TST.B   D0                     ; ...flags, so restore the flags based on D0
    MOVEM.L (SP)+,A2-A4            ; Recover A2-A4 (leaves flags alone)
    RTS


    ; Helper: clear Z iff a floppy controller interrupt is asserted
.ha BTST.B  #$4,(A3)               ; Is the interrupt bit high or low?
    RTS

    ; Helper: clear Z iff a floppy controller interrupt is deasserted
.hd BTST.B  #$4,(A3)               ; Is the interrupt bit high or low?
    EORI.B  #$04,CCR               ; This requires us to invert Z
    RTS

    ; Helper: clear Z iff the floppy controller is idle (not busy)
.hb TST.B   (A2)                   ; See if the gobyte has been set to 0
    EORI.B  #$04,CCR               ; Invert Z so success means Z is clear
    BEQ.S   .rb                    ; If failure, return straightaway
    BTST.B  #$6,(A4)               ; Is the busy bit high or low?
.rb RTS


    ; _FsiWaiter -- _FloppyScriptInterpreter helper: wait for helper to clear Z
    ; Args:
    ;   D0: Loop exponent: give the helper 2^D0 chances to return with Z=0
    ;   A1: Helper subroutine: if it returns with Z unset, then some necessary
    ;       condition has been achieved; must not alter D1/A0-A1
    ;   A2: Address of the floppy shared memory region (IOB)
    ;   A3: Address of xRB for the keyboard VIA
    ;   A4: Address of xRB for the parallel VIA
    ; Notes:
    ;   D0.b will be $FF if the helper never returns with Z=0; otherwise it will
    ;       be $00; Z will be set to match (i.o.w. Z is set on "success")
    ;   Trashes D0-D1
_FsiWaiter:
    MOVEQ.L #$1,D1                 ; Our countdown will be 2 raised to the...
    LSL.L   D0,D1                  ; ...exponent found in D0

    ; Loop waiting for the helper subroutine to deassert Z
.lp JSR     (A1)                   ; Call the helper subroutine
    BNE.S   .rt                    ; If Z is low on its return, jump to return
    SUBQ.L  #$1,D1                 ; Decrement the countdown
    BNE.S   .lp                    ; If countdown is nonzero, loop

    ; Cleanup and return
.rt SEQ.B   D0                     ; D0 gets $FF if Z set, $00 otherwise
    TST.B   D0                     ; Now we invert Z by testing D0
    RTS


* drive Code ------------------------------------


    SECTION kSecData


    DS.W    0                      ; Word alignment

    ; _FloppyScriptInterpreter script for ejecting ("unclamping") a floppy disk
    ; This script is fairly self-contained: it places the drive controller
    ; into a known state before attempting to eject a disk
    ; Assumes that you've selected which floppy drive to eject
_kFloppyScriptEject:
    DC.B    $13                    ; Wait 2^19 rounds for controller not busy
    DC.B    $00                    ; Don't wait on any interrupt right now
    DC.B    $88,$86                ; Enable interrupts from both drives

    DC.B    $07                    ; Wait 2^7 rounds for controller not busy
    DC.B    $00                    ; Don't wait on any interrupt right now
    DC.B    $FF,$85                ; Clear any controller interrupt

    DC.B    $07                    ; Wait 2^7 rounds on controller not busy
    DC.B    $87                    ; Wait 2^7 rounds on interrupt cleared
    DC.B    $02,$81                ; Eject the disk from the current drive

    DC.B    $00                    ; Don't wait on controller not busy
    DC.B    $15                    ; Wait 2^21 rounds for interrupt set
    DC.B    $FF,$85                ; Clear any controller interrupt

    DC.B    $07                    ; Wait 2^7 rounds on controller not busy
    DC.B    $87                    ; Wait 2^7 rounds on interrupt cleared
    DC.B    $00,$00                ; Script terminator


    ; _FloppyScriptInterpreter script for disabling the floppy controller
    ; forever (or at least until the next reset? power-cycle? unsure)
    ; This script is fairly self-contained: it places the drive controller
    ; into a known state before issuing the "goaway" command
_kFloppyScriptGoaway:
    DC.B    $13                    ; Wait 2^19 rounds for controller not busy
    DC.B    $00                    ; Don't wait on any interrupt right now
    DC.B    $88,$86                ; Enable interrupts from both drives

    DC.B    $07                    ; Wait 2^7 rounds for controller not busy
    DC.B    $00                    ; Don't wait on any interrupt right now
    DC.B    $FF,$85                ; Clear any controller interrupt

    DC.B    $07                    ; Wait 2^7 rounds on controller not busy
    DC.B    $87                    ; Wait 2^7 rounds on interrupt cleared
    DC.B    $00,$89                ; Shut down disk controller

    DC.B    $00                    ; Don't wait on the controller not being busy
    DC.B    $00                    ; Don't wait on any interrupt state
    DC.B    $00,$00                ; Program terminator
