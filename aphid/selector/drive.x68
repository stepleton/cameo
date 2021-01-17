* Cameo/Aphid disk image selector: find and understand attached hard drives
* =========================================================================
*
* Forfeited into the public domain with NO WARRANTY. Read LICENSE for details.
*
* Routines for detecting, selecting, and inspecting hard drives connected to
* the Lisa. In anticipation that this program will be used to load and boot
* from Cameo/Aphid devices, most of the routines exhibit some distinctive
* behaviour if a Cameo/Aphid is detected.
*
* The library can also maintain an internal catalogue of attached Cameo/Aphid
* devices at zDrives. 
*
* These routines make use of routines and data definitions set forth in
* selector.x68, block.x68, config.x68, and key_value.x68. (Transitive
* dependencies are not listed.) They also require that the lisa_profile_io
* library from the lisa_io collection be memory-resident.
*
* Public procedures:
*    - SelectParallelPort -- Select and initialise a particular parallel port
*    - CameoAphidCheck -- Is a Cameo/Aphid attached to the current
*                         parallel port?
*    - UpdateDriveCatalogue -- Scan all possible parallel ports for Cameo/Aphids
*    - UpdateDrive -- Investigate a parallel port and update its drive record
*    - HelloBootDrive -- Switch port to the boot drive; update its drive record
*    - SelectByMoniker -- Switch port to a drive identified by a given moniker


* drive Defines ---------------------------------


    ; Handy for testing validity of device IDs using BTST
kDrive_Prts EQU  $06DC           ; Bitmap of valid ports: 110 1101 1100


    ; Drive record definition
    ;
    ; Drive records are the entries in the drive catalogue zDrive (defined
    ; below). For now, they store only a few items that mainly pertain to
    ; Cameo/Aphid devices.

kDrive_ID   EQU  $0              ; b. Device ID
kDrive_Aphd EQU  $1              ; b. Nonzero iff a Cameo/Aphid is attached
kDrive_Mnkr EQU  $2              ; b. Null-terminated name; at most 15 chars+$00

kDrive_NEXT EQU  $12             ; Size of a drive record


* drive Code ------------------------------------


    SECTION kSecCode


    ; SelectParallelPort -- Select and initialise a particular parallel port
    ; Args:
    ;   SP+$4: b. Device ID, any of $02,$03,$04,$06,$07,$09,$0A, which have the
    ;          same meanings that the boot ROM uses to report the boot device:
    ;            $02 - Built-in ("internal") parallel port / Widget
    ;            $03 - Lower port, expansion slot 1
    ;            $04 - Upper port, expansion slot 1
    ;            $06 - Lower port, expansion slot 2
    ;            $07 - Upper port, expansion slot 2
    ;            $09 - Lower port, expansion slot 3
    ;            $0A - Upper port, expansion slot 3
    ; Notes:
    ;   Z will be set if the initialisation was successful
    ;   Failures can mean:
    ;       - the device ID is not a parallel port
    ;       - the selected parallel port is not installed
    ;       - nothing is attached to the parallel port
    ;       - there is a hardware problem
    ;   On success, the selected port is target of all subsequent ProFile I/O
    ;   On success, zCurrentDrive will contain the device ID argument; otherwise
    ;       it will contain $FF
    ;   Device IDs of $00 are interpreted as $02 on Lisa 2/10 systems (where the
    ;       boot ROM appears to use these IDs interchangeably, but prefers $00)
    ;   Trashes D0-D2,A0-A2
SelectParallelPort:
    MOVE.B  $4(SP),D0              ; Copy the device ID from the stack
    BNE.S   .cd                    ; If it wasn't $00, jump to save it in RAM
    CMPI.B  #$03,$2AF              ; Does the ROM say that we're on a Lisa 2/10?
    BNE.S   .rt                    ; No, jump ahead to fail
    MOVEQ.L #$02,D0                ; Yes, but let's use device ID $02 instead
.cd LEA.L   zCurrentDrive(PC),A0   ; Point A0 at zCurrentDrive
    MOVE.B  D0,(A0)                ; Copy the device ID there

    ; If the built-in port is selected, jump straight to setup+initialisation
    CMPI.B  #$02,D0                ; Is the selected port the built-in port?
    BEQ.S   .se                    ; Yes, jump to initialise it

    ; Is the selected port in expansion slot 1?
    CMPI.B  #$03,D0                ; Low port, slot 1?
    BEQ.S   .s1                    ; See if we have a parallel card in slot 1
    CMPI.B  #$04,D0                ; High port, slot 1?
    BNE.S   .p6                    ; No, skip to check for slot 2
.s1 CMPI.W  #$E002,$298            ; Check if ROM saw a parallel card in slot 1
    BEQ.S   .se                    ; Found it! Go initialise the port

    ; Is the selected port in expansion slot 2?
.p6 CMPI.B  #$06,D0                ; Low port, slot 2?
    BEQ.S   .s2                    ; See if we have a parallel card in slot 2
    CMPI.B  #$07,D0                ; High port, slot 2?
    BNE.S   .p9                    ; No, skip to check for slot 3
.s2 CMPI.W  #$E002,$29A            ; Check if ROM saw a parallel card in slot 2
    BEQ.S   .se                    ; Found it! Go initialise the port

    ; Is the selected port in expansion slot 3?
.p9 CMPI.B  #$09,D0                ; Low port, slot 3?
    BEQ.S   .s3                    ; See if we have a parallel card in slot 3
    CMPI.B  #$0A,D0                ; High port, slot 3?
    BNE.S   .rt                    ; Invalid device ID, give up
.s3 CMPI.W  #$E002,$29C            ; Check if ROM saw a parallel card in slot 3
    BNE.S   .rt                    ; No parallel card, give up

    ; Now set up and initialise the selected port
.se MOVEA.L zProFileIoSetupPtr(PC),A0  ; Copy setup routine address to A0
    JSR     (A0)                   ; Invoke setup routine
    MOVEA.L zProFileIoInitPtr(PC),A0   ; Copy init routine address to A0
    JSR     (A0)                   ; Invoke init routine, which sets Z

.rt BEQ.S   ._r                    ; If all's well keep moving along to return
    LEA.L   zCurrentDrive(PC),A0   ; Otherwise, point A0 at zCurrentDrive
    ST.B    (A0)                   ; And fill it with $FF
._r RTS


    ; CurrentDriveParallel -- does zCurrentDrive refer to a parallel port?
    ; Args:
    ;   (none)
    ; Notes:
    ;   Z will be set iff the current drive refers to a parallel port
    ;   Trashes D0-D1
CurrentDriveParallel:
    MOVE.B  zCurrentDrive(PC),D0   ; Copy current device ID to D0
    CMPI.B  #$10,D0                ; Is the port ID too high for bitmap lookups?
    BHS.S   .no                    ; It is, jump ahead to fail
    MOVE.W  #kDrive_Prts,D1        ; Copy valid ports bitmap to D1
    NOT.W   D1                     ; Invert it
    BTST.L  D0,D1                  ; Set Z via a lookup into the inverted bitmap
    BRA.S   .rt

.no ANDI.B  #$FB,CCR               ; Not a parallel port, clear Z
.rt RTS


    ; CameoAphidCheck -- Is a Cameo/Aphid attached to the current parallel port?
    ; Args:
    ;   (none)
    ; Notes:
    ;   Checks for secret Cameo/Aphid identifier in block $FFFFFF
    ;   Z will be set if there is a Cameo/Aphid on the port
    ;   Trashes D0-D1/A0-A1 and the global block buffer (zBlock)
CameoAphidCheck:
    MOVE.W  SR,-(SP)               ; Save status register on the stack
    ORI.W   #$0700,SR              ; Disable all three interrupt levels
    BSR.S   CurrentDriveParallel   ; Is the current device ID a parallel port?
    BNE.S   .rt                    ; No, jump ahead to return in error

    ; Check that BSY/ is high on the parallel port (i.e. the drive is ready)
    ; TODO: The I/O library and the bootloader should export _ProFileWait
    ; Instead we're just going to cheat, and risk breakage!
    MOVEA.L zProFileErrCodePtr(PC),A0  ; Here's where the error code is, but...
    SUBA.L  #$10,A0                ; 16 bytes prior is the main VIA address
    MOVEA.L (A0),A0                ; Load it into A0
    MOVE.W  #$0001,D0              ; Await high BSY/ for this many iterations
.lo MOVE.W  #$F000,D1              ; Await high BSY/ for this many iterations
.li BTST.B  #$1,(A0)               ; Is BSY/ high yet?
    DBNE    D1,.li                 ; Not yet, keep waiting
    DBNE    D0,.lo                 ; Not yet, keep waiting
    BEQ.S   .no                    ; It never got high; jump to return false

    ; Attempt to load block $FFFFFF into the buffer
    MOVE.W  D2,-(SP)               ; Save D2 on the stack
    MOVE.L  #$FFFFFF00,D1          ; We wish to read block $FFFFFF
    MOVE.W  #$0A03,D2              ; Retry count, sparing thresh: not critical
    LEA.L   zBlock(PC),A0          ; We want to read into the block buffer
    MOVEA.L zProFileIoPtr(PC),A1   ; Copy ProFile I/O routine address to A0
    JSR     (A1)                   ; Call it
    MOVEM.W (SP)+,D2               ; Restore D2 from stack leaving flags alone
    BNE.S   .rt                    ; Read failed? Jump to exit (Z is cleared)

    ; Check for the secret Cameo/Aphid identifier in the loaded data
    LEA.L   (zBlock+$20,PC),A0     ; Point A0 at the identifier in loaded data
    CMPI.L  #'Came',(A0)+          ; Does part 1 of the identifier match?
    BNE.S   .rt                    ; If not, skip ahead to return false
    CMPI.L  #'o/Ap',(A0)+          ; Does part 2 of the identifier match?
    BNE.S   .rt                    ; If not, skip ahead to return false
    CMPI.L  #'hid ',(A0)+          ; Does part 3 of the identifier match?
    BNE.S   .rt                    ; If not, skip ahead to return false

    CMPI.L  #'0001',(A0)+          ; Version "0001" or later is required
    BLO.S   .no                    ; Too low? Skip ahead to clear Z
    ORI.B   #$04,CCR               ; Equal or greater version; set Z
    BRA.S   .rt                    ; And skip ahead to return

.no ANDI.B  #$FB,CCR               ; Clearing Z for some failure cases
.rt MOVE.W  SR,D0                  ; Get current SR into D0 (for its flags)
    MOVE.W  (SP)+,D1               ; Get old SR into D1 (for its interrupt mask)
    MOVE.B  D0,D1                  ; Merge old mask and new flags in D1
    MOVE.W  D1,SR                  ; Restore SR from this hybrid
    RTS


    ; UpdateDriveCatalogue -- Scan all possible parallel ports for Cameo/Aphids
    ; Args:
    ;   (none)
    ; Notes:
    ;   Updates the drive catalogue at zDrives
    ;   Attempts to restore the ProFile setup state (as noted in zCurrentDrive)
    ;       from prior to the call; iff successful, sets Z; cannot succeed if
    ;       zCurrentDrive was not a valid ProFile to begin with
    ;   Trashes D0-D2,A0-A2 and the zBlock disk block buffer; changes zDrives
UpdateDriveCatalogue:
    MOVE.B  zCurrentDrive(PC),-(SP)  ; Save current drive ID on stack

    PEA.L   zDrives(PC)            ; Push first drive record addr. on the stack
.lp BSR.S   UpdateDrive            ; Update this drive record
    MOVE.L  (SP),A0                ; Copy drive record address from stack
    ADDA.W  #kDrive_NEXT,A0        ; Point A0 at the next drive address
    MOVE.L  A0,(SP)                ; Update drive address on the stack
    TST.B   (A0)                   ; Null terminator for record list?
    BNE.S   .lp                    ; No, loop to update the drive address

    ADDQ.L  #$4,SP                 ; Yes, pop drive record address off the stack
    ; Now return to talking to the drive we were using before all of this; note
    ; that the old zCurrentDrive has been saved on the stack much earlier
    BSR     SelectParallelPort     ; Switch current drives
    ADDQ.L  #$2,SP                 ; Pop old drive ID off the stack
    RTS


    ; UpdateDrive -- Investigate a parallel port and update its drive record
    ; Args:
    ;   SP+$4: l. Address of the drive record to update
    ; Notes:
    ;   The first byte of the drive record referred to by the address argument
    ;       should contain a valid device ID (see SelectParallelPort)
    ;   Upon returning, the parallel port corresponding to the specified device
    ;       ID will be the current parallel port
    ;   Z will be set if the drive is a Cameo/Aphid
    ;   Trashes D0-D2,A0-A2 and the zBlock disk block buffer; changes
    ;       zCurrentDrive; does NOT update the zConfig buffer
UpdateDrive:
    ; By default we assume there isn't a Cameo/Aphid attached and look for
    ; evidence to confirm that we are right
    MOVEA.L $4(SP),A0              ; Copy drive record address from the stack
    CLR.B   kDrive_Aphd(A0)        ; And assert at first there is no Cameo/Aphid
    ; Start talking to the parallel port described by the current record
    MOVE.B  kDrive_ID(A0),-(SP)    ; Push drive ID on the stack as an argument
    BSR     SelectParallelPort     ; Attempt to talk to that drive ID
    ADDQ.L  #$2,SP                 ; Pop drive ID argument off the stack
    BNE.S   .rt                    ; Attempt failed; jump to mark drive invalid
    ; See if there's a Cameo/Aphid attached
    BSR     CameoAphidCheck        ; Is the drive a Cameo/Aphid?
    BNE.S   .rt                    ; No; jump to mark drive invalid
    ; If so, load/refresh config data in its key/value store's cache
    BSR     ConfLoad               ; Perform the cache load request
    BNE.S   .rt                    ; That didn't work; go mark drive invalid
    ; Now try to read the configuration record into zBlockData --- not zConfig,
    ; since the caller may wish only to scan drives, not change them
    PEA.L   zBlockData(PC)         ; We wish to read config to zBlockData
    BSR     ConfRead               ; Go read it
    ADDQ.L  #$4,SP                 ; Pop the read address off the stack
    BNE.S   .rt                    ; Cache read failed; go mark drive invalid

    ; From here on, we're convinced that we're talking to a Cameo/Aphid
    MOVEA.L $4(SP),A0              ; Recover drive record address from the stack
    MOVE.B  #$FF,kDrive_Aphd(A0)   ; Mark that a Cameo/Aphid is attached
    ; Put a fallback moniker for this drive into the drive record
    MOVE.L  #'~Unc',kDrive_Mnkr(A0)  ; The fallback moniker is '~Unconfigured~'
    MOVE.L  #'onfi',(kDrive_Mnkr+$4,A0)
    MOVE.L  #'gure',(kDrive_Mnkr+$8,A0)
    MOVE.L  #$647E0000,(kDrive_Mnkr+$C,A0)   ; This is 'd~\0\0'
    ; See if its configuration record is sound
    PEA.L   zBlockData(PC)         ; Push the config address onto the stack
    BSR     ConfIsOk               ; Check configuration record integrity
    ADDQ.L  #$4,SP                 ; Pop the record address off of the stack
    BNE.S   .rt                    ; No good, jump to report unconf Cameo/Aphid
    ; Copy the moniker into the drive record
    PEA.L   zBlockData(PC)         ; Push the config address onto the stack
    BSR     ConfMonikerGet         ; Now A0 will point to the loaded moniker
    MOVE.L  A0,(SP)                ; Replace config address with moniker address
    MOVEA.L $8(SP),A0              ; Point A0 to the drive record
    PEA.L   kDrive_Mnkr(A0)        ; Want to copy the moniker into drive record
    MOVE.W  #$10,-(SP)             ; Copy 16 bytes
    BSR     Copy                   ; Do the copy
    ADDQ.L  #$8,SP                 ; Pop args to copy, part 1
    ADDQ.L  #$2,SP                 ; Pop args to copy, part 2

    ; Before returning, set the Z flag if there's a Cameo/Aphid attached
.rt MOVEA.L $4(SP),A0              ; Recover drive record address from the stack
    NOT.B   kDrive_Aphd(A0)        ; A trick: $FF sets Z, $00 clears Z...
    SEQ.B   kDrive_Aphd(A0)        ; ...now undo inversion, leaving flags alone!
    RTS


    ; HelloBootDrive -- Switch port to the boot drive; update its drive record
    ; Args:
    ;   (none)
    ; Notes:
    ;   Attempts to set the current parallel port to the one identified by the
    ;       boot drive ID that the Boot ROM stores at location $1B3
    ;   Of course this drive might not be a hard drive at all, which leads to
    ;       a rather boring failure and no current parallel port
    ;   Z will be set if and only if the boot drive is a Cameo/Aphid
    ;   (I wish I could think of a better name for this routine)
    ;   Trashes D0-D2,A0-A2 and the zBlock disk block buffer; changes zDrives;
    ;       changes zCurrentDrive
HelloBootDrive:
    MOVE.B  $1B3,D0                ; Copy the ROM's saved boot device ID to D0
    LEA.L   zCurrentDrive(PC),A0   ; Point A0 at zCurrentDrive
    MOVE.B  D0,(A0)                ; Stash the boot device there

    LEA.L   zDrives(PC),A0         ; Point A0 at the drive catalogue
.lp MOVE.B  kDrive_ID(A0),D1       ; Copy catalogue entry device ID to D1
    BEQ.S   .no                    ; It was the terminator; we're out of drives
    CMP.B   D0,D1                  ; Does this entry match the boot device?
    BEQ.S   .ur                    ; Yes, skip ahead to update its record
    ADDA.W  #kDrive_NEXT,A0        ; No, move ahead to the next record
    BRA.S   .lp                    ; And loop to investigate it

.ur MOVE.L  A0,-(SP)               ; Push current record address onto the stack
    BSR     UpdateDrive            ; Investigate it and update the record
    ADDQ.L  #$4,SP                 ; Pop record address off the stack
    BRA.S   .rt                    ; Back to caller with UpdateDrive's Z flag

.no ANDI.B  #$FB,CCR               ; No success; clear Z
.rt RTS


    ; SelectByMoniker -- Switch port to a drive identified by a given moniker
    ; Args:
    ;   SP+$4: l. Pointer to a null-terminated moniker
    ; Notes:
    ;   Does not refresh the drive catalogue zDrives; do that first yourself
    ;   Z will be set iff a Cameo/Aphid with the listed moniker appears in the
    ;       catalogue, and if switching to that drive's port was successful
    ;   Trashes D0-D2,A0-A2
SelectByMoniker:
    LEA.L   zDrives(PC),A2         ; Point A2 at the drive catalogue
    MOVE.W  #$F,-(SP)              ; For StrNCmp, eventually: put 15 on stack
    MOVE.L  $6(SP),-(SP)           ; Also, copy the moniker address on the stack

.lp MOVE.B  kDrive_ID(A2),D2       ; Copy catalogue entry device ID to D2
    BEQ.S   .no                    ; It was the terminator; we're out of drives
    PEA.L   kDrive_Mnkr(A2)        ; Push the moniker in the record to the stack
    BSR     StrNCmp                ; Compare monikers
    ADDQ.L  #$4,SP                 ; Pop moniker address off the stack
    BEQ.S   .se                    ; They're the same? Switch to that port
    ADDA.W  #kDrive_NEXT,A2        ; Nope, move to the next record
    BRA.S   .lp                    ; And loop to investigate it

.se MOVE.B  kDrive_ID(A2),-(SP)    ; Push the drive ID onto the stack
    BSR     SelectParallelPort     ; Try to select that port
    ADDQ.L  #$2,SP                 ; Pop the SelectParallelPort arg
    BRA.S   .rt                    ; Now jump ahead to clean up and return

.no ANDI.B  #$FB,CCR               ; No success; clear Z

.rt ADDQ.L  #$6,SP                 ; Pop the two remaining StrNCmp args
    RTS


* drive Scratch data ----------------------------


    SECTION kSecScratch


    DS.W    0                      ; Word alignment
    ; A catalogue of drive records describing hard disk drives that might be
    ; Cameo/Aphids. As pre-populated here, nothing is attached, but
    ; UpdateDriveCatalogue can fill in the records appropriately.
zDrives:
    DC.B    $02                    ; Built-in ("internal") parallel port / Widget
    DC.B    $00                    ; Not an attached Cameo/Aphid
    DS.B    16                     ; Null-terminated moniker

    DC.B    $03                    ; Low port, expansion slot 1
    DC.B    $00
    DS.B    16

    DC.B    $04                    ; High port, expansion slot 1
    DC.B    $00
    DS.B    16

    DC.B    $06                    ; Low port, expansion slot 2
    DC.B    $00
    DS.B    16

    DC.B    $07                    ; High port, expansion slot 2
    DC.B    $00
    DS.B    16

    DC.B    $09                    ; Low port, expansion slot 3
    DC.B    $00
    DS.B    16

    DC.B    $0A                    ; High port, expansion slot 3
    DC.B    $00
    DS.B    16

    DC.B    $00                    ; Null terminator for this catalogue


    ; ID of the drive we'll be speaking to if we use the routines from the
    ; lisa_profile_io library. $FF means we're not ready to speak to any drive.
    ; Should only be set by SelectParallelPort.
zCurrentDrive:
    DC.B    $FF
