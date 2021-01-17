* Cameo/Aphid disk image selector: boot routines
* ==============================================
*
* Forfeited into the public domain with NO WARRANTY. Read LICENSE for details.
*
* Routines (well, just one for now) that load the first block or sector from
* a drive and call it.
*
* The routines in this file attempt to set up conditions that mimic what
* happens when the boot ROM boots from a drive. For the internal parallel port,
* it's straightforward: the first hard drive block is loaded to $20000 and the
* boot ROM (or our own code) jumps there. A boot from a drive attached to a
* parallel port expansion card is more complex: the boot ROM loads the parallel
* port card ROM's boot program to $20000 and runs it, then that program loads
* the boot program to $20810 and jumps there. For this latter case, our code
* loads the card's boot program into ROM for verisimilitude, but it never calls
* it; we load the first drive block ourselves.
*
* Unlike the boot ROM, we don't worry about whether the tag data for boot blocks
* mark the drive as bootable --- we jump to the code no matter what.
*
* These routines make use of data definitions set forth in selector.x68 and
* routines defined in block.x68. They also require that the lisa_profile_io
* library from the lisa_io collection be memory-resident.
*
* Public procedures:
*    - BootHd -- Load and execute a hard drive's boot block (block $000000)


* boot Defines ----------------------------------


kBoot_Intnl EQU  $20000          ; Where to load boot code for the internal port
kBoot_Pcard EQU  $20810          ; Where to load boot code for parallel cards
kBoot_Slot1 EQU  $FC0001         ; Memory address for first I/O slot



* boot Code -------------------------------------


    SECTION kSecCode


    ; BootHd -- Load and execute a hard drive's boot block (block $000000)
    ; Args:
    ;   (none)
    ; Notes:
    ;   Jumps to offset $14 in the boot block when booting -- that is, past the
    ;       the 20 "tag" bytes and at the beginning of the 512 "data" bytes
    ;   Does not check whether the drive is marked as bootable (that is, it
    ;       doesn't bother looking for $AAAA at tag bytes $8 and $9)
    ;   Attempts to replicate some ordinary Lisa booting behaviour:
    ;       - When booting from the internal parallel port, the data block
    ;         is positioned at $20000
    ;       - When booting from a parallel port card, the contents of the
    ;         parallel port's boot ROM are loaded to $1FFFC, and the data block
    ;         is positioned at $20810
    ;   If booting fails for some reason, returns with Z clear; if the booted
    ;       program returns for some reason without destroying the memory
    ;       occupied by the selector program, returns with Z set
    ;   Trashes D0-D1/A0-A1, plus whatever the booted program destroys (which
    ;       could be everything, really)
BootHd:
    ; Load the first block from the current hard drive to the location where we
    ; we load boot blocks for internal drives (we'll move it later if we're
    ; loading from a parallel card)
    CLR.L   D1                   ; $00000000: we want to read block $000000
    MOVE.W  #$0A03,D2            ; Standard retry count/sparing threshold params
    MOVEA.L #(kBoot_Intnl-$14),A0  ; Here's where we want to load the block
    MOVEA.L zProFileIoPtr(PC),A1   ; Copy ProFile I/O routine address to A1
    JSR     (A1)                 ; Call it
    BNE     .rt                  ; Failure? Jump ahead to return
    MOVE.B  zCurrentDrive(PC),D1   ; Load current device ID into D1
    CMPI.B  #$02,D1              ; Is it the internal drive?
    BEQ.S   .bt                  ; Yes, go straight ahead and boot it

    ; If we're loading from a parallel port card, move the data we've loaded to
    ; the location where the parallel card's boot program would have put it,
    ; then load the parallel card's boot program to $20000
    MOVE.L  #(kBoot_Intnl-$14),-(SP)   ; Here's where we loaded block $000000
    MOVE.L  #(kBoot_Pcard-$14),-(SP)   ; Here's where it needs to move
    MOVE.W  #$214,-(SP)          ; We'll move the entire block, 532 bytes
    BSR     Copy                 ; Here we go
    ADDQ.L  #$8,SP               ; Pop Copy arguments off the stack, part 1
    ADDQ.L  #$2,SP               ; Pop Copy arguments off the stack, part 2

    ; Now replicate the behaviour of the boot ROM and copy the parallel port ROM
    ; to location $20000 --- it's not clear that the program we're loading needs
    ; to see it there, but we love verisimilitude...
    MOVE.B  zCurrentDrive(PC),D0   ; Copy current drive ID to D0
    MOVEA.L #kBoot_Slot1,A0      ; Point A0 at slot 1
    CMPI.B  #$05,D0              ; Are we booting from a card in that slot?
    BLO.S   .lr                  ; Yes, jump to load the ROM
    ADDA.W  #$4000,A0            ; No, point A0 at slot 2
    CMPI.B  #$08,D0              ; Are we booting from a card in that slot?
    BLO.S   .lr                  ; Yes, jump to load the ROM
    ADDA.W  #$4000,A0            ; No, point A0 at slot 3

.lr MOVEA.L #(kBoot_Intnl-$4),A1   ; Card ROM data loads to $1FFFC
    MOVEP.L $0(A0),D1            ; Load card ID and word count to D1
    MOVE.L  D1,(A1)+             ; Save it to memory as well
    ADDQ.L  #$8,A0               ; And move A0 ahead to ROM data that follows
    SUBQ.W  #$1,D1               ; Word count to loop iterator, but limit to...
    ANDI.W  #$3FF,D1             ; ...1024 words to avoid clobbering block data
.lp MOVEP.W $0(A0),D0            ; Read the next word from the ROM
    ADDQ.W  #$4,A0               ; Advance ROM data pointer
    MOVE.W  D0,(A1)+             ; Copy the ROM word to RAM
    DBRA.W  D1,.lp               ; And loop to get the next word

    ; At last, boot the boot block --- unlike the boot ROM, we use a JSR just
    ; in case someone feels like returning to us...
.bt BSR     LisaConsolePollKbMouse   ; Flush the COPS: poll it for any input
    BCS.S   .bt                  ; Keep looping if there was any
    MOVE.B  $1B3,-(SP)           ; Save the ROM's boot device ID on the stack
    MOVE.B  zCurrentDrive(PC),D0   ; Put current parallel port ID into D0
    MOVE.B  D0,$1B3              ; Substitute it atop the ROM's boot device ID

    MOVE.L  #kBoot_Intnl,A2      ; Boot address for internal port data into A2
    CMPI.B  #$02,D0              ; But are we booting from the internal port?
    BEQ.S   .go                  ; Yes, go do it
    ADDA.W  #(kBoot_Pcard-kBoot_Intnl),A2  ; No, boot addr for par. card data

.go JSR     (A2)                 ; And awaaaay we go!

    MOVE.B  (SP)+,$1B3           ; (We're back?!) Restore ROM boot device ID
    ORI.B   #$04,CCR             ; Then clear Z to mark success, I guess

.rt RTS
