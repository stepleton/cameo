* Cameo/Aphid disk image selector: "narrated" versions of various routines
* ========================================================================
*
* Forfeited into the public domain with NO WARRANTY. Read LICENSE for details.
*
* Routines that call routines from other files and print what is happening as
* they do, plus some other utilities for displaying information to the user.
*
* Public procedures:
*    - NSelectParallelPort -- Narrated version of drive.x68:SelectParallelPort
*    - NCameoAphidCheck -- Narrated version of drive.x68:CameoAphidCheck
*    - NUpdateDriveCatalogue -- drive.x68:UpdateDriveCatalogue, narrated
*    - NHelloBootDrive -- Narrated version of drive.x68:HelloBootDrive
*    - NSelectByMoniker -- Narrated version of drive.x68:SelectByMoniker
*    - NMakeBasicBootScript -- script.x68:MakeBasicBootScript, narrated
*    - NCatalogueUpdate -- Narrated version of catalogue.x68:CatalogueUpdate
*    - NCatalogueExists -- Narrated version of catalogue.x68:CatalogueExists
*    - NImageChange -- Narrated version of catalogue.x68:ImageChange
*    - NConfLoad -- Narrated version of config.x68:ConfLoad
*    - NConfRead -- Narrated version of config.x68:ConfRead
*    - NConfPut -- Narrated version of config.x68:ConfPut
*    - NKeyValueLoad -- Narrated version of key_value.x68:KeyValueLoad
*    - NKeyValueRead -- Narrated version of key_value.x68:KeyValueRead
*    - NKeyValuePut -- Narrated version of key_value.x68:KeyValuePut
*    - NBootHd -- Narrated version of boot.x68:BootHd
*    - PrintParallelPort -- Print a friendly string identifying a parallel port


* narrated Code ---------------------------------


    SECTION kSecCode


    ; NSelectParallelPort -- Narrated version of drive.x68:SelectParallelPort
    ; Args:
    ;   (See drive.x68:SelectParallelPort)
    ; Notes:
    ;   (See drive.x68:SelectParallelPort)
    ;   Trashes D0-D2/A0-A2
NSelectParallelPort:
    mUiPrint  <$0A,' Switching to '>
    MOVE.B  $4(SP),-(SP)           ; Copy the device ID on the stack
    BSET.B  #$7,(SP)               ; Set "the" bit for PrintParallelPort
    BSR     PrintParallelPort      ; Print the name of the parallel port
    PEA.L   _sN_Ellipsis(PC)       ; Push "... " address onto the stack
    mUiPrint  s                    ; Print it

    BCLR.B  #$7,(SP)               ; Clear "the" bit; we'll reuse this arg
    BSR     SelectParallelPort     ; Run SelectParallelPort
    ADDQ.L  #$2,SP                 ; Pop device ID off the stack
    BSR     _NVerdictByZ           ; Print whether that worked
    RTS


    ; NCameoAphidCheck -- Narrated version of drive.x68:CameoAphidCheck
    ; Args:
    ;   (See drive.x68:CameoAphidCheck)
    ; Notes:
    ;   (See drive.x68:CameoAphidCheck)
    ;   Trashes D0-D1/A0-A1 and the zBlock disk block buffer
NCameoAphidCheck:
    mUiPrint <$0A,' Verifying current drive is a Cameo/Aphid... '>
    BSR     CameoAphidCheck        ; Do the device check
    BSR     _NVerdictByZ           ; Print whether that worked
    RTS


    ; NUpdateDriveCatalogue -- drive.x68:UpdateDriveCatalogue, narrated
    ; Args:
    ;   (See drive.x68:UpdateDriveCatalogue)
    ; Notes:
    ;   (See drive.x68:UpdateDriveCatalogue)
    ;   Trashes D0-D2/A0-A2 and the zBlock disk block buffer; changes zDrives
NUpdateDriveCatalogue:
    mUiPrint <$0A,' Scanning for connected Cameo/Aphid devices... '>
    BSR     UpdateDriveCatalogue   ; Do the scan
    SNE.B   -(SP)                  ; If Z push $00, otherwise push $FF
    mUiPrint  <'done'>             ; The Z flag isn't indicative of much
    TST.B   (SP)+                  ; Recover original Z from stack
    RTS


    ; NHelloBootDrive -- Narrated version of drive.x68:HelloBootDrive
    ; Args:
    ;   (See drive.x68:HelloBootDrive)
    ; Notes:
    ;   (See drive.x68:HelloBootDrive)
    ;   Only returns successfully (i.e. sets Z) if the drive is a Cameo/Aphid
    ;   Trashes D0-D2,A0-A2 and the zBlock disk block buffer; changes zDrives;
    ;       changes zCurrentDrive
NHelloBootDrive:
    mUiPrint  <$0A,' Connecting to the boot drive: '>
    MOVE.B  $1B3,-(SP)             ; Push boot drive identifier to the stack
    BSET.B  #$7,(SP)               ; Set "the" bit for PrintParallelPort
    BSR     PrintParallelPort      ; Print the name of the parallel port
    ADDQ.L  #$2,SP                 ; Pop the boot drive identifier from stack
    PEA.L   _sN_Ellipsis(PC)       ; Push "... " address onto the stack
    mUiPrint  s                    ; Print it

    BSR     HelloBootDrive         ; Switch to the boot drive; update its record
    BSR     _NVerdictByZ           ; Print whether that worked
    RTS


    ; NSelectByMoniker -- Narrated version of drive.x68:SelectByMoniker
    ; Args:
    ;   (See drive.x68:SelectByMoniker)
    ; Notes:
    ;   (See drive.x68:SelectByMoniker)
    ;   Trashes D0-D2/A0-A2
NSelectByMoniker:
    PEA.L   _sN_Ellipsis(PC)       ; Push "... " address onto the stack
    MOVE.L  $8(SP),-(SP)           ; Copy the moniker address on the stack
    mUiPrint  <$0A,' Connecting to a Cameo/Aphid called '>,s,s

    MOVE.L  $4(SP),-(SP)           ; Copy the moniker address on the stack again
    BSR     SelectByMoniker        ; Try to select the drive
    ADDQ.L  #$4,SP                 ; Pop the moniker address off the stack
    SNE.B   -(SP)                  ; If Z push $00, otherwise push $FF
    BEQ.S   .ok                    ; If things worked out, print current port
    BSR     _NVerdictByZ           ; Didn't work out; print the negative verdict
    BRA.S   .rt                    ; And jump ahead to return

.ok MOVE.B  zCurrentDrive(PC),-(SP)  ; Push the current device ID onto the stack
    BSR     PrintParallelPort      ; Print the current port
    ADDQ.L  #$2,SP                 ; Pop the device ID off the stack

.rt TST.B   (SP)+                  ; Recover original Z from stack
    RTS
    

    ; NMakeBasicBootScript -- script.x68:MakeBasicBootScript, narrated
    ; Args:
    ;   (See script.x68:MakeBasicBootScript)
    ; Notes:
    ;   (See script.x68:MakeBasicBootScript)
    ;   Trashes D0-D1/A0-A1 and the zBlock disk block buffer
NMakeBasicBootScript:
    PEA.L   _sN_Ellipsis(PC)       ; Push "... " address onto the stack
    MOVE.L  $8(SP),-(SP)           ; Copy the disk image address on the stack
    mUiPrint <$0A,' Installing a script for booting '>,s,s

    MOVE.L  $4(SP),-(SP)           ; Re-copy the disk image address on the stack
    BSR     MakeBasicBootScript    ; Jump to install the boot script
    ADDQ.L  #$4,SP                 ; Pop the disk image address off the stack
    BSR     _NVerdictByZ           ; Print whether the command was successful
    RTS
    

    ; NCatalogueUpdate -- Narrated version of catalogue.x68:CatalogueUpdate
    ; Args:
    ;   (See catalogue.x68:CatalogueUpdate)
    ; Notes:
    ;   (See catalogue.x68:CatalogueUpdate)
    ;   Trashes D0-D2/A0-A2 and the zBlock disk block buffer
NCatalogueUpdate:
    mUiPrint <$0A,' Updating the drive image catalogue... '>
    BSR     CatalogueUpdate        ; Update the drive image catalogue
    BSR     _NVerdictByZ           ; Print whether that worked
    RTS


    ; NCatalogueExists -- Narrated version of catalogue.x68:CatalogueExists
    ; Args:
    ;   (See catalogue.x68:CatalogueExists)
    ; Notes:
    ;   (See catalogue.x68:CatalogueExists)
    ;   Trashes D0-D1/A0-A1
NCatalogueExists:
    PEA.L   _sN_Ellipsis(PC)       ; Push "... " address onto the stack
    MOVE.L  $8(SP),-(SP)           ; Copy the disk image address on the stack
    mUiPrint <$0A,' Checking that there is a drive image called '>,s,s

    MOVE.L  $4(SP),-(SP)           ; Re-copy the disk image address on the stack
    BSR     CatalogueExists        ; Jump to scan the catalogue
    ADDQ.L  #$4,SP                 ; Pop the disk image address off the stack
    BSR     _NVerdictByZ           ; Print whether the command was recevied
    RTS


    ; NImageChange -- Narrated version of catalogue.x68:ImageChange
    ; Args:
    ;   (See catalogue.x68:ImageChange)
    ; Notes:
    ;   (See catalogue.x68:ImageChange)
    ;   Trashes D0-D2/A0-A2 and the zBlock disk block buffer
NImageChange:
    PEA.L   _sN_Ellipsis(PC)       ; Push "... " address onto the stack
    MOVE.L  $8(SP),-(SP)           ; Copy the disk image address on the stack
    mUiPrint <$0A,' Changing the drive image to '>,s,s

    MOVE.L  $4(SP),-(SP)           ; Re-copy the disk image address on the stack
    BSR     ImageChange            ; Jump to change the disk image
    ADDQ.L  #$4,SP                 ; Pop the disk image address off the stack
    BSR     _NVerdictByZ           ; Print whether the command was recevied
    RTS


    ; NConfLoad -- Narrated version of config.x68:ConfLoad
    ; Args:
    ;   (See config.x68:ConfLoad)
    ; Notes:
    ;   (See config.x68:ConfLoad)
    ;   Trashes D0-D1/A0-A1
NConfLoad:
    mUiPrint <$0A,' Loading configuration into key/value cache... '>
    BSR    ConfLoad                ; Read the configuration
    BSR     _NVerdictByZ           ; Print whether that worked
    RTS


    ; NConfRead -- Narrated version of config.x68:ConfRead
    ; Args:
    ;   (See config.x68:ConfRead)
    ; Notes:
    ;   (See config.x68:ConfRead)
    ;   Trashes D0/A0-A1 and the zBlock disk block buffer
NConfRead:
    mUiPrint <$0A,' Reading configuration... '>
    MOVE.L  $4(SP),-(SP)           ; Re-copy the address to write to
    BSR    ConfRead                ; Read the configuration
    ADDQ.L  #$4,SP                 ; Pop the write-to address off the stack
    BSR     _NVerdictByZ           ; Print whether that worked
    RTS


    ; NConfPut -- Narrated version of config.x68:ConfPut
    ; Args:
    ;   (See config.x68:ConfPut)
    ; Notes:
    ;   (See config.x68:ConfPut)
    ;   Trashes D0-D1/A0-A1 and the zBlock disk block buffer
NConfPut:
    mUiPrint <$0A,' Writing configuration... '>
    MOVE.L  $4(SP),-(SP)           ; Re-copy the address to read from
    BSR    ConfPut                 ; Write the configuration
    ADDQ.L  #$4,SP                 ; Pop the read from address off the stack
    BSR     _NVerdictByZ           ; Print whether that worked
    RTS


    ; NKeyValueLoad -- Narrated version of key_value.x68:KeyValueLoad
    ; Args:
    ;   (See key_value.x68:KeyValueLoad)
    ; Notes:
    ;   (See key_value.x68:KeyValueLoad)
    ;   Trashes D0-D1/A0-A1
NKeyValueLoad:
    mUiPrint <$0A,' Updating key/value cache... '>
    MOVE.L  $4(SP),-(SP)           ; Re-copy the address of the load request
    BSR    KeyValueLoad            ; Execute the cache loading operation
    ADDQ.L  #$4,SP                 ; Pop the load request address off the stack
    BSR     _NVerdictByZ           ; Print whether that worked
    RTS


    ; NKeyValueRead -- Narrated version of key_value.x68:KeyValueRead
    ; Args:
    ;   (See key_value.x68:KeyValueRead)
    ; Notes:
    ;   (See key_value.x68:KeyValueRead)
    ;   Trashes D0/A0-A1 and the zBlock disk block buffer
NKeyValueRead:
    mUiPrint <$0A,' Reading key/value data from cache... '>
    MOVE.W  $4(SP),-(SP)           ; Re-copy the cache ley on the stack
    BSR    KeyValueRead            ; Read the configuration
    ADDQ.L  #$2,SP                 ; Pop the cache key off the stack
    MOVEM.L A0-A1,-(SP)            ; Save A0 and A1
    BSR     _NVerdictByZ           ; Print whether that worked
    MOVEM.L (SP)+,A0-A1            ; Recover A0 and A1
    RTS


    ; NKeyValuePut -- Narrated version of key_value.x68:KeyValuePut
    ; Args:
    ;   (See key_value.x68:KeyValuePut)
    ; Notes:
    ;   (See key_value.x68:KeyValuePut)
    ;   Trashes D0-D1/A0-A1, also zBlock buffer if key+value aren't contiguous
NKeyValuePut:
    mUiPrint <$0A,' Writing key/value data... '>
    MOVE.L $A(SP),-(SP)            ; Copy the key address on the stack
    MOVE.L $A(SP),-(SP)            ; Copy the value address on the stack
    MOVE.W $C(SP),-(SP)            ; Copy the cache key on the stack
    BSR    KeyValuePut             ; Write the key/value data
    ADDQ.W #$8,SP                  ; Pop KeyValuePut args, part 1
    ADDQ.W #$2,SP                  ; Pop KeyValuePut args, part 2
    BSR.S   _NVerdictByZ           ; Print whether that worked
    RTS


    ; NBootHd -- Narrated version of boot.x68:BootHd
    ; Args:
    ;   (See boot.x68:BootHd)
    ; Notes:
    ;   (See boot.x68:BootHd)
    ;   If control returns to this function, awaits a keypress
    ;   Trashes D0-D1/A0-A1, plus whatever the booted program destroys (which
    ;       could be everything, really)
NBootHd:
    mUiPrint <$0A,' Booting from '>
    MOVE.B  zCurrentDrive(PC),-(SP)  ; Push the current device ID onto the stack
    BSET.B  #$7,(SP)               ; Set "the" bit for PrintParallelPort
    BSR.S   PrintParallelPort      ; Print the name of the parallel port
    ADDQ.L  #$2,SP                 ; Pop device ID off the stack
    PEA.L   _sN_Ellipsis(PC)       ; Push "... " address onto the stack
    mUiPrint  s                    ; Print it
    ; Try to boot from the port
    BSR     BootHd                 ; Go boot; probably won't return
    ; But if it returns, let's print something for the user
    SNE.B   -(SP)                  ; If Z push $00, otherwise push $FF
    BSR     ClearLisaConsoleScreen   ; Blank the screen
    mUiPrint  r1c1,<'{ Booting a drive image }'>
    TST.B   (SP)+                  ; Recover original Z from stack
    BSR     AskVerdictByZ          ; Say whether the booting succeeded
    RTS


    ; _NVerdictByZ -- Present verdict depending on Z
    ; Args:
    ;   CCR: If Z=1, print "OK", if Z=0, print "FAILED"
    ; Notes:
    ;   Leaves Z unchanged
    ;   Unlike AskVerdictByZ, does not wait for a keypress
    ;   Trashes D0-D1/A0-A1
_NVerdictByZ:
    SNE.B   -(SP)                  ; If Z push $00, otherwise push $FF
    BNE.S   .fa                    ; If ~Z, announce failure
    PEA.L   sAskOpOk(PC)           ; We want to print "OK"
    BRA.S   .pr                    ; Jump ahead to print it
.fa PEA.L   sAskOpFailed(PC)       ; We want to print "FAILED"
.pr mUiPrint  s                    ; Print whichever one
    TST.B   (SP)+                  ; Recover original Z from stack
    RTS


    ; PrintParallelPort -- Print a friendly string identifying a parallel port
    ; Args:
    ;   SP+$4: b. Device ID whose name we should print -- any of
    ;          $02,$03,$04,$06,$07,$09,$0A, which have the same meanings that
    ;          the boot ROM uses to report the boot device, and which cause
    ;          these strings to be printed:
    ;            $02 - "built-in parallel port"
    ;            $03 - "lower port on expansion slot 1"
    ;            $04 - "upper port on expansion slot 1"
    ;            $06 - "lower port on expansion slot 2"
    ;            $07 - "upper port on expansion slot 2"
    ;            $09 - "lower port on expansion slot 3"
    ;            $0A - "upper port on expansion slot 3"
    ;          Set the high bit ($82,$83,$84,...) in the device ID, and the
    ;          string will be prepended with "the":
    ;            $82 - "the built-in parallel port"
    ;            ...
    ;          Set the second-highest bit ($42,$43,...,$C2,$C3,...) and the
    ;          first letter in the string will be capitalised:
    ;            $42 - "Built-in parallel port"
    ;            ...
    ;            $C9 - "The upper port on expansion slot 3"
    ;          An invalid device ID will yield the string "?invalid drive?"
    ; Notes:
    ;   This code modifies the _sPPP* strings to handle the casing and "the-ing"
    ;       flags in the argument
    ;   As such, this routine is not thread-safe :-)
    ;   Trashes D0-D1/A0-A1
PrintParallelPort:
    ; Check that the device ID is valid
    CLR.L   D0                     ; Zero D0 so bytes 1-3 are empty after we...
    MOVE.B  $4(SP),D0              ; ...copy the device ID from the stack
    ANDI.B  #$0F,D0                ; Clear the printing options flags

    MOVE.W  #kDrive_Prts,D1        ; Bitmap of valid ports: 110 1101 1100
    BTST.L  D0,D1                  ; Is the device ID a valid one?
    BNE.S   .sn                    ; Yes, go set the slot number
    mUiPrint  <'?invalid drive?'>  ; What even is this identifier?
    BRA.S   .rt                    ; Go give up

    ; Customise the slot number string for the device ID at _sPPP_SlotNum
.sn LEA.L   _sPPP_SlotNum(PC),A0   ; Point A0 at the slot number character
    MOVE.B  #'0',(A0)              ; Set the character to '0' for now
    DIVU.W  #$3,D0                 ; Divide device ID by 3
    ADD.B   D0,(A0)                ; Add it to the slot number character

    ; Print a "the" if the user wants it
.th CLR.L   D0                     ; Zero D0 so bytes 1-3 are empty after we...
    MOVE.B  $4(SP),D0              ; ...recopy the device ID from the stack
    BCLR.L  #$7,D0                 ; Test and clear the "the " bit
    BEQ.S   .at                    ; No "the " wanted; skip ahead
    BSR.S   .uc                    ; Set upper or lower case on "the "
    MOVE.W  D0,-(SP)               ; Save the modified device ID on the stack
    PEA.L   _sPPP_The(PC)          ; Get ready to print "the "
    mUiPrint  s                    ; Print it
    MOVE.W  (SP)+,D0               ; Restore the modified device ID

    ; Print the human-friendly name of the port
.at BSR.S   .uc                    ; Set upper or lower case on the first word

    CMPI.B  #$02,D0                ; Was this the built-in parallel port?
    BNE.S   .sl                    ; Wasn't the built-in port; skip ahead
    PEA.L   _sPPP_BuiltIn(PC)      ; Push the built-in port string
    mUiPrint  s                    ; Print it
    BRA.S   .rt                    ; Skip ahead to exit.

.sl LEA.L   _sPPP_Upper(PC),A0     ; Point A0 at the "upper" string
    MOVE.W  #$0248,D1              ; Bitmap of "lower" ports: 10 0100 1000
    BTST.L  D0,D1                  ; Is this a lower port?
    BEQ.S   .pr                    ; No, skip ahead to print "upper" as planned
    LEA.L   _sPPP_Lower(PC),A0     ; Point A0 at the "lower" string

.pr PEA.L   _sPPP_2Port(PC)        ; Push " port on expansion slot _" string
    MOVE.L  A0,-(SP)               ; Push "upper" or "lower" depending
    mUiPrint  s,s                  ; Print both strings

.rt RTS

    ; Apply user-directed first-letter casing to human-friendly port names 
    ; Args:
    ;   D0: Bit 6 indicates whether the user wants to capitalise the first
    ;       letter in the human-friendly port names
    ; Notes:
    ;   D0 bit 6 will be cleared after calling this routine; remaining bits are
    ;       left unchanged
    ;   Trashes D0-D1/A0
.uc LEA.L   _sPPP_The(PC),A0       ; Point A0 at "the "
    MOVEQ.L #$5,D1                 ; Bit 5 controls letter casing in ASCII
    BCLR.L  #$6,D0                 ; Do we want capitals? (Clear option bit)
    BEQ.S   .lc                    ; No, make the letters lower-case

    BCLR.B  D1,(A0)                ; "The "
    BCLR.B  D1,_sPPP_Off1(A0)      ; "Upper"
    BCLR.B  D1,_sPPP_Off2(A0)      ; "Lower"
    BCLR.B  D1,_sPPP_Off3(A0)      ; "Built-in parallel port"
    BRA.S   .rc                    ; Jump ahead to exit

.lc BSET.B  D1,(A0)                ; "the "
    BSET.B  D1,_sPPP_Off1(A0)      ; "upper"
    BSET.B  D1,_sPPP_Off2(A0)      ; "lower"
    BSET.B  D1,_sPPP_Off3(A0)      ; "built-in parallel port"

.rc RTS


* narrated Data ---------------------------------


    SECTION kSecData


_sN_Ellipsis:
    DC.B    '... ',$00


* narrated Scratch data -------------------------


    SECTION kSecScratch


    ; These strings are used to build human-friendly names for parallel ports;
    ; they are in kSecScratch because PrintParallelPort will modify them in
    ; various ways, including:
    ;     - Capitalising "the", "upper", "lower", and "built-in"
    ;     - Changing the expansion slot number at _sPPP_SlotNum
_sPPP_The:
    DC.B    'the ',$00
_sPPP_Upper:
    DC.B    'upper',$00
_sPPP_Lower:
    DC.B    'lower',$00
_sPPP_BuiltIn:
    DC.B    'built-in parallel port',$00
_sPPP_2Port:
    DC.B    ' port on expansion slot '
_sPPP_SlotNum:
    DC.B    '?',$00                ; Expansion slot number; will be modified


    ; PrintParallelPort is written in such a way that the arrangement and
    ; lengths of _sPPP_The, _sPPP_Upper, _sPPP_Lower, and _sPPP_BuiltIn matter
    ; for changing thee case of those strings; we place these equates here
    ; instead of the usual place for the sake of readability
_sPPP_Off1  EQU  _sPPP_Upper-_sPPP_The
_sPPP_Off2  EQU  _sPPP_Lower-_sPPP_The
_sPPP_Off3  EQU  _sPPP_BuiltIn-_sPPP_The
