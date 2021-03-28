* Cameo/Aphid disk image selector: scripting
* ==========================================
*
* Forfeited into the public domain with NO WARRANTY. Read LICENSE for details.
*
* Rudimentary scripting functionality. For now, the primary application is
* automatic booting from a disk image on the boot device.
*
* A script is a sequence of commands executed in order. It will continue
* executing until there are no more commands or until one of the commands
* encounters an error. There is no flow control. Commands are meant to be
* "keyboard-editable" with a bit of effort and have the following structure:
*
*    - Bytes 0-3 are the command name: see the Defines section below
*    - If the command takes N arguments, then the next N words are the lengths
*      of those arguments *less 1* as two-digit hex values expressed in ASCII
*      characters 0-9,a-f. ("Less 1" implies that there can be no length-0
*      arguments: valid lengths are 1 through 256, coded as 00 through ff.)
*      Lengths for null-terminated strings must count the null terminator.
*    - Next are the argument values themselves, concatenated in order. *If an
*      argument has an odd length, then one byte of padding should be appended
*      to the argument before the next argument begins.*
*
* Here is a demonstration of this structure for the fictional "Blah" command:
*
*    Blah1a0504Here Is The First Argument!_Arg #2Arg 3_
*
* This made-up command takes three arguments. After the `Blah` command name, we
* find the lengths of the three arguments, less one:
*
*    - '1a' = 26, so the first argument is 27 bytes long
*    - '05', so the second is 6 bytes long
*    - '04', so the third is 5 bytes
*
* Next come the arguments, which in this case appear to be text strings without
* null terminators. The first argument is `Here Is The First Argument!`, the
* second is `Arg #2`, and the third is `Arg 3`. Because the first and third
* arguments are an odd number of bytes long, they are each trailed by a
* meaningless padding byte, `_` in both cases.
*
* See the Defines section below for documentation on real commands.
*
* After executing a command successfully, the script interpreter begins
* interpreting the bytes immediately after the command as the next command. Put
* differently, commands in a script should be arranged contiguously in memory.
*
* Most commands print some kind of information about their progress to the
* screen; exceptions to this are noted below.
*
* Scripts usually reside in the zScriptPad buffer. If a script is run, the rest
* of the program should not make too many assumptions about the durability of
* data that was placed in any of the program's buffers (zBlock, zConfig,
* zScriptPad, etc.) ahead of time.
*
* Public procedures:
*    - Interpret -- Interpret a script
*    - MakeBasicBootScript -- Install a basic boot script to the Cameo/Aphid


* script Defines --------------------------------


    ; Exit the script without error. In general, it's a good idea to place a
    ; Halt statement at the end of all scripts. No arguments; not a command.
kScrHalt    EQU  'Halt'

    ; Scan all parallel ports on the computer for attached Cameo/Aphids and
    ; update the drive catalogue. No arguments.
kScrScan    EQU  'Scan'

    ; Make the parallel port hosting the Cameo/Aphid that was used for booting
    ; the Lisa the current parallel port. Will fail if the boot device was not
    ; a Cameo/Aphid. No arguments.
kScrHome    EQU  'Home'

    ; Eject all floppy disks. No arguments.
kScrEject   EQU  'Ejct'

    ; Boot from the device on the current parallel port. No arguments.
kScrBootHd  EQU  'Boot'

    ; Force an update of the drive image catalogue. No arguments.
kScrCatUp   EQU  'Clog'

    ; Read a script from the key/value store's cache, and run it. Note that the
    ; script must already be in the cache. Prints nothing; consider using
    ; kScrPrint if needed. Scripts are 510 bytes long (you don't have to use
    ; all that space) followed by a two-byte checksum (as computed by e.g.
    ; BlockCsumCheck); if there is a checksum mismatch, this command fails.
    ; One argument: a two-byte cache key.
kScrRead    EQU  'Read'
 
    ; Search the drive catalogue for a Cameo/Aphid device with the specified
    ; moniker, and make the parallel port associated with that device the
    ; current parallel port. One argument: a moniker string to search for, null
    ; termination optional.
kScrSelect  EQU  'Name'

    ; Tell the Cameo/Aphid device on the current parallel port to switch the
    ; active ProFile drive image to the specified file. One argument: a drive
    ; image file name, null termination optional. Fails if the specified image
    ; doesn't exist in the catalogue, which means the catalogue must be present
    ; and loaded (see the 'Clog' command above). Use the 'Ima!' command below
    ; if you'd like to skip the catalogue check.
kScrImage   EQU  'Imag'

    ; Tell the Cameo/Aphid device on the current parallel port to switch the
    ; active ProFile drive image to the specified file. One argument: a drive
    ; image file name, null termination optional. Omits the catalogue check that
    ; the 'Imag' command performs.
kScrImageX  EQU  'Ima!'

    ; Print a string. One argument: a string to print, null termination
    ; optional. Does not supply newlines or any other characters besides what
    ; you specify.
kScrPrint   EQU  'Prnt'

    ; Not a command, but noted here to reserve it from ever becoming a command.
    ; Compare to the ILLEGAL instruction for the 68k --- but not too closely.
kScrZilch   EQU  $00000000
 

* script Code -----------------------------------


    SECTION kSecCode


    ; Interpret -- Interpret a script
    ; Args:
    ;   SP+$6: l. Address of the script to interpret; must be word-aligned
    ;   SP+$4: b. $00: return immediately after interpreting the script
    ;             $01: pause for keypress on success
    ;             $02: pause for keypress on failure
    ;             $03: pause for keypress on success or failure
    ; Notes:
    ;   Mainly a dispatch table for script commands, which must return with
    ;       the address of the next command in A0
    ;   Z will be set if the script completes successfully, although scripts
    ;       that boot from a disk image may never return
    ;   Consider no register or memory area unchanged after calling
Interpret:
    MOVE.L  $6(SP),A0              ; Copy script address to A0

.lp MOVE.L  (A0),D0                ; Copy command name to D0
    CMPI.L  #kScrHalt,D0           ; Is it the halt command?
    BEQ.S   .rt                    ; Yes, jump ahead to finish (Z is set)
    MOVE.L  A0,-(SP)               ; Push command address for command helpers
    LEA.L   _CommandTable(PC),A0   ; Point A0 at the command table
    SUBA.L  A1,A1                  ; Our command table offset starts at 0

.sc MOVE.L  $0(A0,A1.W),D1         ; Copy table entry to D1; out of commands?
    BEQ.S   .uc                    ; Go complain about an unrecognised command
    CMP.L   D1,D0                  ; Is this the command we're looking for?
    BEQ.S   .go                    ; Yes, go execute the command
    ADDQ.L  #$4,A1                 ; No, bump the offset to the next command
    BRA.S   .sc                    ; And go check it out

.go MOVE.W  A1,D0                  ; _CommandTable offset into D0
    LSR.W   #1,D0                  ; Now it's a _CommandOffsets offset
    LEA.L   _CommandOffsets(PC),A0   ; Point A0 at the command offsets table
    ADDA.W  $0(A0,D0.W),A0         ; Add the offset of the matched command
    JSR     (A0)                   ; Run the command; arg is already on stack
    ADDQ.L  #$4,SP                 ; We're back, pop command addr off the stack
    BEQ.S   .lp                    ; Command succeded, loop to next command
    BRA.S   .rt                    ; Command failed, jump ahead to abort

; .uc ADDQ.L  #$4,SP                 ; Pop command address off the stack
;     MOVE.L  D0,-(SP)               ; Stash unrecognised command on the stack
.uc MOVE.L  D0,(SP)                ; Do both of the above
    mUiPrint  <$0A,' Oops, unrecognised script command: '>
    MOVE.L  (SP)+,D0               ; Recover the command from the stack
.up ROL.L   #$8,D0                 ; Print bad command: obtain next byte
    BEQ.S   .ux                    ; Out of bytes? Jump ahead
    mUiPutc D0                     ; Print the next byte
    CLR.B   D0                     ; Clear it so we don't print again
    BRA.S   .up                    ; Loop to print the next byte
.ux ANDI.B  #$FB,CCR               ; Clear the Z flag to indicate failure

.rt SNE.B   -(SP)                  ; If Z push $00, otherwise push $FF
    mUiPrint  <$0A,' The script '>
    TST.B   (SP)                   ; Test the saved ~Z byte
    BNE.S   .er                    ; If it's "on", jump to say "with errors"
    mUiPrint  <'finished successfully.'>
    BTST.B  #$0,$6(SP)             ; Do we need to get a keypress from the user?
    BEQ.S   .rq                    ; Nope, skip ahead to exit
    BRA.S   .rs                    ; Yes, skip ahead to get a keypress

.er mUiPrint  <'aborted due to an error.'>
    BTST.B  #$1,$6(SP)             ; Do we need to get a keypress from the user?
    BEQ.S   .rq                    ; Nope, skip ahead to exit

.rs TST.B   (SP)                   ; Yes, get original Z from stack
    BSR     AskVerdictByZ          ; Show verdict, get a keypress
.rq
    TST.B   (SP)+                  ; Recover original Z from stack
    RTS

    DS.W    0                      ; Word alignment
_CommandTable:
    DC.L    kScrScan
    DC.L    kScrHome
    DC.L    kScrEject
    DC.L    kScrBootHd
    DC.L    kScrCatUp
    DC.L    kScrRead
    DC.L    kScrSelect
    DC.L    kScrImage
    DC.L    kScrImageX
    DC.L    kScrPrint
    DC.L    $00000000
_CommandOffsets:
    DC.W    (_InterpScan-_CommandOffsets)
    DC.W    (_InterpHome-_CommandOffsets)
    DC.W    (_InterpEject-_CommandOffsets)
    DC.W    (_InterpBootHd-_CommandOffsets)
    DC.W    (_InterpCatUp-_CommandOffsets)
    DC.W    (_InterpRead-_CommandOffsets)
    DC.W    (_InterpSelect-_CommandOffsets)
    DC.W    (_InterpImage-_CommandOffsets)
    DC.W    (_InterpImageX-_CommandOffsets)
    DC.W    (_InterpPrint-_CommandOffsets)


_InterpScan:
    BSR     NUpdateDriveCatalogue  ; Go update the drive catalogue
    MOVEA.L $4(SP),A0              ; Advance the script address four bytes...
    ADDQ.L  #$4,A0                 ; ...to point at the next command
    ; NUpdateDriveCatalogue sets Z if it can switch back to the original device
    ; successfully, which requires that the device be (at least) a ProFile;
    ; while we might not care about that in many settings where we might call
    ; NUpdateDriveCatalogue, for here it seems like a reasonable check
    RTS


_InterpHome:
    BSR     NHelloBootDrive        ; Return to the boot Cameo/Aphid
    MOVEA.L $4(SP),A0              ; Advance the script address four bytes...
    ADDQ.L  #$4,A0                 ; ...to point at the next command
    RTS


_InterpEject:
    BSR     NEjectFloppies         ; Eject floppy disks
    MOVEA.L $4(SP),A0              ; Advance the script address four bytes...
    ADDQ.L  #$4,A0                 ; ...to point at the next command
    RTS


_InterpBootHd:
    BSR     NBootHd                ; Go boot; probably won't return
    MOVEA.L $4(SP),A0              ; Advance the script address four bytes...
    ADDQ.L  #$4,A0                 ; ...to point at the next command
    RTS


_InterpCatUp:
    BSR     CatalogueInit          ; Clear out the drive image catalogue
    BSR     NCatalogueUpdate       ; Update the drive image catalogue
    MOVEA.L $4(SP),A0              ; Advance the script address four bytes...
    ADDQ.L  #$4,A0                 ; ...to point at the next command
    RTS


_InterpRead:
    MOVEA.L $4(SP),A0              ; Copy command address to A0
    CMPI.W  #'01',$4(A0)           ; The argument length must be '01'
    BNE.S   .rt                    ; If it isn't, fail

    MOVE.W  $6(A0),-(SP)           ; Copy script's cache key to the stack
    BSR     KeyValueRead           ; Read the script into zBlock
    ADDQ.L  #$2,SP                 ; Pop the cache key off the stack
    BNE.S   .rt                    ; Jump to return on failure

    MOVE.L  A1,-(SP)               ; Put zBlockData address on the stack
    PEA.L   zScriptPad(PC)         ; Copy it to the script area
    MOVE.W  #$200,-(SP)            ; Copy 512 bytes in total
    BSR     Copy                   ; Do the copy
    ADDQ.L  #$2,SP                 ; Pop copy size off the stack
    BSR     BlockCsumCheck         ; Check block checksum (reuse zScriptPad arg)
    ADDQ.L  #$8,SP                 ; Pop args to BlockCsumCheck and Copy
    BNE.S   .rt                    ; Checksum failed? Jump ahead to fail

    LEA.L   zScriptPad(PC),A0      ; Point A0 at the newly-read script
    ORI.B   #$04,CCR               ; Success; set Z prior to return
.rt RTS


_InterpSelect:
    LEA.L   NSelectByMoniker(PC),A1  ; Point A1 at NSelectByMoniker
    BRA.S   _InterpCommonOneArg    ; Jump ahead to invoke it on our argument


_InterpImage:
    LEA.L   NCatalogueExists(PC),A1  ; Point A1 at NCatalogueExists
    MOVE.L  $4(SP),-(SP)           ; Duplicate command address on the stack
    BSR.S   _InterpCommonOneArg    ; Does the specified image file exist?
    ADDQ.L  #$4,SP                 ; Pop the command address off the stack
    BEQ.S   _InterpImageX          ; File exists? Switch to that image
    RTS                            ; Otherwise, quit with Z clear


_InterpImageX:
    LEA.L   NImageChange(PC),A1    ; Point A1 at NImageChange
    ; Fall through to _InterpCommonOneArg


_InterpCommonOneArg:
    MOVEA.L $4(SP),A0              ; Copy command address to A0
    MOVE.W  $4(A0),D0              ; Copy string length hex digits to D0
    BSR.S   _HexWordToByte         ; Convert them to a number
    ADDQ.W  #$1,D0                 ; Make D0 the string length sans terminator
    ADDQ.W  #$6,A0                 ; Point A0 at the beginning of the string

    MOVE.B  $0(A0,D0.W),-(SP)      ; Save byte past string end on stack
    CLR.B   $0(A0,D0.W)            ; Null-terminate the string
    MOVE.L  D0,-(SP)               ; Save D0 on the stack, plus the string...
    MOVE.L  A0,-(SP)               ; ...addr, which is also an arg to the...
    JSR     (A1)                   ; ...routine specified to us, which we call
    SNE.B   D1                     ; If Z set D1 to $00, otherwise set it to $FF
    MOVEA.L (SP)+,A0               ; Restore string addr from the stack
    MOVE.L  (SP)+,D0               ; Restore string length from the stack
    MOVE.B  (SP)+,$0(A0,D0.W)      ; Restore byte at the null terminator

    ADDA.W  D0,A0                  ; Advance A0 to the next command
    BTST.L  #$0,D0                 ; Was the string an odd length?
    BEQ.S   .rt                    ; No, jump ahead to return
    ADDQ.L  #$1,A0                 ; Advance A0 to the next word boundary
.rt TST.B   D1                     ; Recover original Z from D1
    RTS


_InterpPrint:
    MOVEA.L $4(SP),A0              ; Copy command address to A0
    MOVE.W  $4(A0),D0              ; Copy string length hex digits to D0
    BSR.S   _HexWordToByte         ; Convert them to a number
    ADDQ.W  #$1,D0                 ; Make D0 the string length sans terminator
    ADDQ.W  #$6,A0                 ; Point A0 at the beginning of the string

    MOVE.B  $0(A0,D0.W),-(SP)      ; Save byte past string end on stack
    CLR.B   $0(A0,D0.W)            ; Null-terminate the string
    MOVEM.L D0/A0,-(SP)            ; Save D0/A0 on the stack
    MOVE.L  A0,-(SP)               ; String address on the stack again
    mUiPrint  s                    ; Print the string
    MOVEM.L (SP)+,D0/A0            ; Restore D0/A0 from the stack
    MOVE.B  (SP)+,$0(A0,D0.W)      ; Restore byte at the null terminator

    ADDA.W  D0,A0                  ; Advance A0 to the next command
    BTST.L  #$0,D0                 ; Was the string an odd length?
    BEQ.S   .rt                    ; No, jump ahead to return
    ADDQ.L  #$1,A0                 ; Advance A0 to the next word boundary
    ORI.B   #$04,CCR               ; Success; set Z prior to return
.rt RTS


    ; _HexWordToByte -- Convert 2-digit ASCII hex number to a byte
    ; Args:
    ;   D0: w. 2-digit ASCII hex number with digits in [0-9a-zA-Z], e.g. 'f0'
    ; Notes:
    ;   Converted number is in the LSByte of D0; all other bytes in D0 will be 0
    ;   In comments below, Aa is the first hex digit byte, Bb is the second hex
    ;       digit byte, x and y are the two nibbles of the result byte,
    ;       and _ is 0
    ;   Result is undefined if the hex digits are not in [0-9a-zA-Z]
    ;   Trashes D0
_HexWordToByte:
    ANDI.L  #$00001F1F,D0          ; Make D0 ____AaBb; make Aa,Bb table indices
    ROR.L   #$8,D0                 ; Rotate to Bb____Aa
    MOVE.B  .tb(PC,D0.W),D0        ; Replace Aa with table value: Bb_____x
    SWAP.W  D0                     ; Now ___xBb__
    LSR.W   #$8,D0                 ; Now ___x__Bb
    MOVE.B  .tb(PC,D0.W),D0        ; Replace Bb with table value: ___x___y
    ROR.W   #$4,D0                 ; Getting close: ___xy___
    LSL.L   #$4,D0                 ; Even closer: __xy____
    SWAP.W  D0                     ; All done! ______xy
    RTS

    DS.W    0                      ; Word alignment
    ; Table used by _HexWordToByte to convert the lower five bits of hex digits
    ; to nibbles
.tb DC.B    $21,$0A,$0B,$0C,$0D,$0E,$0F,$53
    DC.B    $74,$65,$70,$6C,$65,$74,$6F,$6E
    DC.B    $00,$01,$02,$03,$04,$05,$06,$07
    DC.B    $08,$09


    ; MakeBasicBootScript -- Install a basic boot script to the Cameo/Aphid
    ; Args:
    ;   SP+$4: l. Address of a null-terminated string that names the drive
    ;       image that should be booted; must be non-empty
    ; Notes:
    ;   The boot script amounts to "switch to this drive image, boot, and then
    ;       (if control ever returns) halt".
    ;   Z will be set iff the script storage operation was successful
    ;   Trashes D0-D1/A0-A1 and the zBlock disk block buffer
MakeBasicBootScript:
    ; The boot image argument must not be the empty string
    MOVE.L  $4(SP),A1              ; Copy string pointer to A1
    TST.B   (A1)                   ; Is it zero?
    EORI.B  #$04,CCR               ; We want ~Z on error, so flip the flag
    BNE     .rt                    ; And return to caller if ~Z

    ; First, construct the script
    LEA.L   zBlockData(PC),A1      ; Point A1 at our workspace, zBlockData
    MOVE.L  A1,-(SP)               ; Put that address on the stack
    BSR     BlockZero              ; Zero out that block
    ADDQ.L  #$4,SP                 ; Pop the address off the stack
    MOVE.L  #kScrCatUp,(A1)+       ; 'Clog' updates the drive image catalogue
    MOVE.L  #kScrImage,(A1)+       ; 'Imag' selects the disk image

    ADDQ.L  #$2,A1                 ; Point A1 to where the image name goes
    MOVE.L  $4(SP),-(SP)           ; Copy drive image name address on stack
    MOVE.L  A1,-(SP)               ; Put "where the image name goes" on stack
    BSR     StrCpy255              ; Copy the string
    MOVE.L  (SP)+,A1               ; Restore A1 to contents from before the call
    ADDQ.L  #$4,SP                 ; Pop the other StrCpy255 arg from the stack

    SUBQ.L  #$1,A0                 ; Point A0 at the copied null terminator
    MOVE.L  A0,D0                  ; Copy it to D0
    SUB.L   A1,D0                  ; Now D0 is the string length sans terminator
    SUBQ.L  #$1,D0                 ; Less 1 to make it a script length value

    MOVE.W  D0,D1                  ; Copy D0 to D1
    LSR.W   #$4,D0                 ; D0 has only the high nibble value now
    MOVE.B  .tb(PC,D0.W),D0        ; Convert that high nibble value to a digit
    LSL.W   #$8,D0                 ; And shift that digit into the D0 high byte
    ANDI.W  #$000F,D1              ; Mask D1 to have only the low nibble value
    MOVE.B  .tb(PC,D1.W),D1        ; Convert that low nibble value to a digit
    MOVE.B  D1,D0                  ; And move the digit to the D0 low byte
    MOVE.W  D0,-2(A1)              ; Copy the length into the command

    MOVE.L  A0,D0                  ; Copy A0 (end of string) to D0, and check:
    BTST.L  #$0,D0                 ; Is the address word-aligned?
    BEQ.S   .bt                    ; Yes, proceed to the next command
    MOVE.B  #'_',(A0)+             ; No, pad and advance to next word boundary

.bt MOVE.L  #kScrEject,(A0)+       ; The next command is: eject floppies!
    MOVE.L  #kScrBootHd,(A0)+      ; Nothing left to do then but boot
    MOVE.L  #kScrHalt,(A0)         ; And then, for appearances, a halt command

    ; Place a checksum at the end of the script
    PEA.L   zBlockData(PC)         ; Push an address to our new command
    BSR     BlockCsumSet           ; Compute the checksum
    ADDQ.L  #$4,SP                 ; Pop the BlockCsumSet argument

    ; Now write the finished boot script to the key/value store
    LEA.L   kKV_KeyBootScript(PC),A0   ; Point A0 at the boot script key
    MOVE.L  A0,-(SP)               ; Push the pointer onto the stack
    PEA.L   zBlockData(PC)         ; Push an address to our new command
    MOVE.W  -2(A0),-(SP)           ; Push the boot script cache key
    BSR     KeyValuePut            ; Write to the key/value store
    ADDQ.L  #$8,SP                 ; Pop the KeyValuePut arguments, part 1
    ADDQ.L  #$2,SP                 ; Pop the KeyValuePut arguments, part 2
.rt RTS

.tb DC.B    '0123456789ABCDEF'     ; Hex digit table
