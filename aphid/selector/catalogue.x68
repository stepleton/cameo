* Cameo/Aphid disk image selector: load and use the drive image catalogue
* =======================================================================
*
* Forfeited into the public domain with NO WARRANTY. Read LICENSE for details.
*
* Utilities for reading and modifying the Cameo/Aphid's collection of hard drive
* images.
*
* A Cameo/Aphid Python module plugin (in stock Cameo/Aphid software
* distributions, this is `cameo/aphid/profile_plugin_FFFEFE_filesystem_ops.py`)
* allows manipulation of the drive image catalogue via reads and writes to a
* "magic block". The routines in this file hard-code this block as $FFFEFE. For
* details of the protocol, refer to documentation within the Python module.
*
* Routines starting with `Catalogue` are for loading and querying the catalogue
* of drive images on the Cameo/Aphid. The data structure for this catalogue
* begins at zCatalog, and it must be initialised prior to any other use of the
* catalogue (including reading the catalogue) via `CatalogueInit`.
*
* These routines make use of data definitions set forth in selector.x68 and
* routines defined in block.x68. They also require that the lisa_profile_io
* library from the lisa_io collection be memory-resident.
*
* Public procedures:
*    - CatalogueInit -- Initialise the drive image catalogue
*    - CatalogueUpdate -- Refresh the drive image catalogue if needed
*    - CatalogueItemName -- Point A0 at the filename of the Nth catalogue entry
*    - CatalogueExists -- Check whether an image file exists in the catalogue
*    - ImageChange -- Direct Cameo/Aphid to change the current drive image
*    - ImageNew -- Direct Cameo/Aphid to create a new ProFile drive image
*    - ImageDelete -- Direct Cameo/Aphid to delete a ProFile drive image
*    - ImageCopy -- Direct Cameo/Aphid to make a copy of a ProFile drive image
*    - ImageRename -- Direct Cameo/Aphid to rename a ProFile drive image


* catalogue Defines -----------------------------


kCatBlockRd EQU  $FFFEFE00       ; ProFileIo command: catalogue magic block read
kCatBlockWr EQU  $FFFEFE01       ; ProFileIo command: catalogue magic blk write
kCmdBlockWr EQU  $FFFFFD01       ; ProFileIo command: control magic block write


    ; Catalogue header record definition
    ;
    ; The drive image catalogue begins with this header that says how many drive
    ; image files there are. It also contains a nonce value that the
    ; Cameo/Aphid filesystem operations plugin uses as a "watermark" of the
    ; current state of the filesystem; if the plugin reports a different nonce
    ; to the one we have stored, it's time to reload the catalogue.

kCatH_Nonce EQU  $0              ; l. Nonce value (see above)
kCatH_Count EQU  $4              ; w. Number of drive images in the catalogue
kCatH_Force EQU  $6              ; w. If nonzero, force catalogue reload

kCatE_FIRST EQU  $8              ; Size of header/First catalog entry


    ; Catalogue entry record definition
    ;
    ; The drive image catalogue contains entries with the following data. The
    ; filesystem modification times are unlikely to be very helpful given that
    ; the PocketBeagle computer lacks any way of synchronising its clock with
    ; the true time of day.
    ;
    ; Note that the record format makes room for null terminators at the ends of
    ; the MTime and Size strings.

kCatE_MTime EQU  $0              ; YYYYMMDDHHMMSS ASCII last-modified time
_kCatE_T1   EQU  $E              ; (First null terminator)
kCatE_Size  EQU  $F              ; ASCII right-justified file size (10 chars)
_kCatE_T2   EQU  $19             ; (Second null terminator)
kCatE_Name  EQU  $1A             ; Filename: up to 255 chars, null-terminated
                                 ; Shorter strings must null-pad!

kCatE_NEXT  EQU  $11A            ; Size of a catalog entry record


    ; Filesystem operations block record definition
    ;
    ; Reads to the "magic block" $FFFEFE with retry count and sparing threshold
    ; parameters that together form the big-endian 16-bit number "N" yield a
    ; block of data that describes the N-th drive image stored on the
    ; Cameo/Aphid. The structure of the data is as follows and includes fields
    ; that we also use in the catalogue header---besides simplifying the
    ; protocol, this also ensures that you'd detect midway through loading a
    ; catalogue that something else has been changing the filesystem (maybe
    ; someone's logged into the PocketBeagle and is making changes?).

kCatB_Nonce EQU  $0
kCatB_Count EQU  $4
kCatB_MTime EQU  $6
kCatB_Size  EQU  $14
kCatB_Name  EQU  $114


* catalogue Code --------------------------------


    SECTION kSecCode


    ; CatalogueInit -- Clear out the drive image catalogue
    ; Args:
    ;   (none)
    ; Notes:
    ;   Unlike the drive catalogue zDrives, we don't load a pre-initialised
    ;       drive image catalogue into RAM; we have to initialise the catalogue
    ;       header ourselves with this routine
    ;   Call this routine before calling CatalogueUpdate if you want to force a
    ;       reload of the drive image catalogue
    ;   Trashes D0/A0
CatalogueInit:
    LEA.L   zCatalogue(PC),A0    ; Point A0 at the catalogue
    CLR.L   kCatH_Nonce(A0)      ; Zero out the nonce
    CLR.W   kCatH_Count(A0)      ; The catalogue initialises as empty
    MOVE.W  #$1,kCatH_Force(A0)  ; Force CatalogueUpdate to do a full reload
    RTS


    ; CatalogueUpdate -- Refresh the drive image catalogue if needed
    ; Args:
    ;   (none)
    ; Notes:
    ;   Will exit early without updating the catalogue if the nonce value
    ;       reported by the Cameo/Aphid filesystem ops plugin equals the value
    ;       stored in the catalogue header; call CatalogueInit prior to this
    ;       function to force a refresh of the catalogue
    ;   Sets Z on success; clears if there's any failure
    ;   Trashes D0-D2/A0-A2 and the zBlock disk block buffer
CatalogueUpdate:
    ; We may not need to reload the catalogue---check first to see if the nonce
    ; has changed
    MOVEM.L D3/A3,-(SP)          ; Save various registers on the stack
    MOVE.L  #kCatBlockRd,D1      ; We wish to read from the "magic" block
    CLR.W   D2                   ; Any entry will do, but let's get the first
    LEA.L   zBlock(PC),A0        ; We will read data to zBlock
    MOVEA.L zProFileIoPtr(PC),A1   ; Copy ProFile I/O routine address to A1
    JSR     (A1)                 ; Call the ProFile I/O routine
    BNE     .rt                  ; Abort in case of failure, borrowing its flag

    LEA.L   zBlock(PC),A2        ; Point A2 at zBlock
    MOVE.L  kCatB_Nonce(A2),D3   ; Copy the last nonce we loaded to D3
.rl LEA.L   zCatalogue(PC),A3    ; Point A3 at the catalogue header
    TST.W   kCatH_Force(A3)      ; Is a catalogue reload forced?
    BNE.S   .fr                  ; Yes, skip the next check
    CMP.L   kCatH_Nonce(A3),D3   ; Is its nonce same as the one in the block?
    BEQ.S   .rt                  ; If so, exit with success; no update needed

    ; The nonce has changed, or we're forced to reload the catalogue regardless,
    ; so it's time to do just that
    ; Note that A1 (the ProFile I/O routine address) and D1 (the I/O routine
    ; read command have not changed, and remain unchanged throughout
.fr CLR.W   kCatH_Nonce(A3)      ; Clear force-reload flag
    MOVE.L  D3,kCatH_Nonce(A3)   ; Copy the loaded nonce to the catalogue
    MOVE.W  kCatB_Count(A2),kCatH_Count(A3)  ; Copy loaded entry count as well

    ADDQ.L  #kCatE_FIRST,A3      ; Advance A3 to the first catalogue entry
    CLR.W   D2                   ; Set number of catalogue entries loaded to 0
.lp CMP.W   (zCatalogue+kCatH_Count,PC),D2   ; Compare with total # of entries
    BHS.S   .rt                  ; If no more (should set Z) then return
    MOVE.L  A2,A0                ; We will read data to zBlock (again)
    JSR     (A1)                 ; Load this next image information block
    BNE.S   .rt                  ; Abort in case of failure, borrowing its flag

    CMP.L   kCatB_Nonce(A2),D3   ; Has the nonce changed as we've been reading?
    BNE.S   .rl                  ; If so, start over with reading the catalogue

    MOVEM.L D1/A1,-(SP)          ; Save D1 and A1 on stack while we copy stuff

    PEA.L   kCatB_MTime(A2)      ; Copy mtime from the loaded information block
    PEA.L   kCatE_MTime(A3)      ; Copy to the catalogue entry
    MOVE.W  #$E,-(SP)            ; The mtime string is 14 bytes long
    BSR     Copy                 ; Perform the copy
    ADDA.W  #$A,SP               ; Pop copy arguments off the stack
    CLR.B   _kCatE_T1(A3)        ; Null-terminate the mtime string

    PEA.L   kCatB_Size(A2)       ; Copy size from the loaded information block
    PEA.L   kCatE_Size(A3)       ; Copy to the catalogue entry
    MOVE.W  #$A,-(SP)            ; The size string is 10 bytes long
    BSR     Copy                 ; Perform the copy
    ADDA.W  #$A,SP               ; Pop copy arguments off the stack
    CLR.B   _kCatE_T2(A3)        ; Null-terminate the size string

    PEA.L   kCatB_Name(A2)       ; Copy mtime from the loaded information block
    PEA.L   kCatE_Name(A3)       ; Copy to the catalogue entry
    MOVE.W  #$100,-(SP)          ; The filename is 256 bytes long
    BSR     Zero                 ; For TST.B in _CataloguePItem: zero unused...
    ADDQ.L  #$2,SP               ; ...filename bytes, then pop off length
    BSR     StrCpy255            ; Perform the copy of bytes we actually use
    ADDQ.L  #$8,SP               ; Pop StrCpy255 arguments off the stack

    MOVEM.L (SP)+,D1/A1          ; Restore D1 and A1 from the stack

    LEA.L   kCatE_NEXT(A3),A3    ; Advance A3 to the next catalogue entry
    ADDQ.W  #$1,D2               ; Increment count of catalogue entries
    BRA.S   .lp                  ; And loop back to the next entry

.rt MOVEM.L (SP)+,D3/A3          ; Restore various registers from the stack
    RTS


    ; CatalogueItemName -- Point A0 at the filename of the Nth catalogue entry
    ; Args:
    ;   SP+$4: w. The number of the catalogue entry whose name we want
    ; Notes:
    ;   On return, A0 points at the catalogue name (a non-standard convention)
    ;   Does not check that the catalogue has SP+$4 entries
    ;   Trashes D0/A0
CatalogueItemName:
    LEA.L   zCatalogue(PC),A0    ; Point A0 to the drive image catalogue
    ADDA.W  #kCatE_FIRST,A0      ; Advance to the first catalogue entry
    MOVE.W  $4(SP),D0            ; We want the name for this catalogue entry
    MULU.W  #kCatE_NEXT,D0       ; ...which is offset this many bytes from A0
    LEA.L   kCatE_Name(A0,D0.W),A0   ; Point A0 at the string in that entry
    RTS


    ; CatalogueExists -- Check whether an image file exists in the catalogue
    ; Args:
    ;   SP+$4: l. Pointer to a filename to search for in the catalogue
    ; Notes:
    ;   Z will be set iff the image file exists in the catalogue
    ;   Also, D2 will have the index of the matching file entry
    ;   Searches the catalogue from back to front, linearly, if that matters
    ;   Trashes D0-D1/A0-A1
CatalogueExists:
    MOVE.L  D2,-(SP)             ; Save D2 on the stack

    MOVE.W  #$100,-(SP)          ; For StrNCmp: compare up to 256 characters
    MOVE.L  $A(SP),-(SP)         ; Also copy the filename pointer on the stack

    LEA.L   zCatalogue(PC),A0    ; Point A0 to the drive image catalogue
    MOVE.W  kCatH_Count(A0),D2   ; Copy number of entries to D2
.lp SUBQ.W  #1,D2                ; Back us up to the preceding entry
    BMI.S   .rt                  ; No entries left; return with Z clear
    MOVE.W  D2,-(SP)             ; For CatalogueItemName: which item?
    BSR     CatalogueItemName    ; Point A0 at the item's filename
    ADDQ.L  #$2,SP               ; Pop CatalogueItemName argument off the stack
    MOVE.L  A0,-(SP)             ; For StrNCmp: now push the actual name
    BSR     StrNCmp              ; Do the string comparison
    ADDQ.L  #$4,SP               ; Pop third StrNCmp argument off the stack
    BNE.S   .lp                  ; No match? Move to the next entry

.rt ADDQ.L  #$6,SP               ; Pop first two StrNCmp arguments off the stack
    MOVEM.L  (SP)+,D2            ; Restore D2 from stack without touching flags
    RTS


    ; ImageChange -- Direct Cameo/Aphid to change the current drive image
    ; Args:
    ;   SP+$4: l. Points to the name of the drive image to change to the
    ;       current drive image
    ; Notes:
    ;   Does NOT check that a file by that name is present in the catalogue
    ;   Sets Z if the command was issued successfully
    ;   Cannot verify that the image has actually been changed
    ;   Trashes D0-D2/A0-A1 and the zBlock disk buffer
ImageChange:
    ; Construct the image change command in the disk block buffer
    LEA.L   zBlock(PC),A0        ; Point A0 at zBlock
    MOVE.L  #'IMAG',(A0)+        ; Start zBlock with "IMAGE:", part 1
    MOVE.W  #'E:',(A0)+          ; Start zBlock with "IMAGE:", part 2
    MOVE.L  $4(SP),-(SP)         ; We want to copy from the argument filename...
    MOVE.L  A0,-(SP)             ; ...to the spot just after "IMAGE:"
    BSR     StrCpy255            ; And here we go
    ADDQ.L  #$8,SP               ; Pop arguments off the stack

    ; Issue the command to the Cameo/Aphid
    MOVE.L  #kCmdBlockWr,D1      ; We wish to write to the "magic" block
    MOVE.W  #$FEAF,D2            ; This retry count/sparing thresh. is required
    LEA.L   zBlock(PC),A0        ; We just assembled the command in zBlock
    MOVEA.L zProFileIoPtr(PC),A1   ; Copy ProFile I/O routine address to A1
    JSR     (A1)                 ; Call the ProFile I/O routine
    BNE.S   .rt

    ; Wait one second for the Cameo/Aphid to reset itself
    MOVE.L  #$3D090,D0           ; Loop this many times to delay for one second
.lp SUBQ.L  #$1,D0               ; Decrement delay counter
    BNE.S   .lp                  ; Loop until it hits 0; sets Z for success too

.rt RTS


    ; ImageNew -- Direct Cameo/Aphid to create a new ProFile drive image
    ; Args:
    ;   SP+$4: l. Points to the name to give to the new drive image
    ; Notes:
    ;   Does not refresh the catalogue before or after the call
    ;   Sets Z if no file by that name was present in the catalogue and the
    ;       command was issued successfully
    ;   Trashes D0-D2/A0-A1 and the zBlock disk buffer
ImageNew:
    ; First, see if the filename is present in the catalogue
    MOVE.L  $4(SP),-(SP)         ; Copy the filename pointer on the stack
    BSR     CatalogueExists      ; Is there already a file with this name?
    ADDQ.L  #$4,SP               ; Pop the filename pointer off the stack
    EORI.B  #$04,CCR             ; Invert Z because existing is bad...
    BNE.S   .rt                  ; ...it means we need to give up

    ; The operation we want to do is create
    MOVE.W  #'mk',D2             ; To be used by ProFileIo much later
    BRA.S   _ImageCommonOneArg   ; Use code shared by ImageDelete to finish

.rt RTS


    ; ImageDelete -- Direct Cameo/Aphid to delete a ProFile drive image
    ; Args:
    ;   SP+$4: l. Points to the name of the drive image to delete
    ; Notes:
    ;   Does not refresh the catalogue before or after the call
    ;   Sets Z if a file by that name was present in the catalogue and the
    ;       command was issued successfully
    ;   Trashes D0-D2/A0-A1 and the zBlock disk buffer
ImageDelete:
    ; First, see if the filename is present in the catalogue
    MOVE.L  $4(SP),-(SP)         ; Copy the filename pointer on the stack
    BSR     CatalogueExists      ; Is there already a file with this name?
    ADDQ.L  #$4,SP               ; Pop the filename pointer off the stack
    BNE.S   _ImageDeleteReturn   ; If not, go give up

    ; The operation we want to do is delete
    MOVE.W  #'rm',D2             ; To be used by ProFileIo much later
    ; Fall through into _ImageCommonOneArg

    ; The rest of this routine is shared with ImageNew
_ImageCommonOneArg:
    ; Copy the filename to the disk block buffer
    MOVE.L  $4(SP),-(SP)         ; We want to copy from the argument filename...
    PEA.L   zBlock(PC)           ; ...to the disk block buffer
    BSR     StrCpy255            ; And here we go
    ADDQ.L  #$8,SP               ; Pop arguments off the stack

    ; Issue the command to the Cameo/Aphid (D2 was set much earlier)
    MOVE.L  #kCatBlockWr,D1      ; We wish to write to the "magic" block
    LEA.L   zBlock(PC),A0        ; The filename is in zBlock
    MOVEA.L zProFileIoPtr(PC),A1   ; Copy ProFile I/O routine address to A1
    JSR     (A1)                 ; Call the ProFile I/O routine

_ImageDeleteReturn:
    RTS


    ; ImageCopy -- Direct Cameo/Aphid to make a copy of a ProFile drive image
    ; Args:
    ;   SP+$8: l. Points to the name of the drive image to copy
    ;   SP+$4: l. Points to the name to give to the copied image
    ; Notes:
    ;   Does not refresh the catalogue before or after the call
    ;   Sets Z if a file with the source name is present in the catalogue, if no
    ;       file with the destination name is present in the catalogue, and if
    ;       the command was issued successfully
    ;   Trashes D0-D2/A0-A1 and the zBlock disk buffer
ImageCopy:
    ; The operation we want to do is copy
    MOVE.W  #'cp',D2             ; To be used by ProFileIo much later
    BRA.S   _ImageCommonTwoArg   ; Jump to the common code for both operations


    ; ImageRename -- Direct Cameo/Aphid to rename a ProFile drive image
    ; Args:
    ;   SP+$8: l. Points to the name of the drive image to rename
    ;   SP+$4: l. Points to the name to give to the renamed image
    ; Notes:
    ;   Does not refresh the catalogue before or after the call
    ;   Sets Z if a file with the source name is present in the catalogue, if no
    ;       file with the destination name is present in the catalogue, and if
    ;       the command was issued successfully
    ;   Trashes D0-D2/A0-A1 and the zBlock disk buffer
ImageRename:
    ; The operation we want to do is rename
    MOVE.W  #'mv',D2             ; To be used by ProFileIo much later
    ; Fall through to _ImageCommonTwoArg

    ; Common code for ImageCopy and ImageRename
_ImageCommonTwoArg:
    ; See if the source file is present in the catalogue
    MOVE.L  $8(SP),-(SP)         ; Copy the filename pointer on the stack
    BSR     CatalogueExists      ; Is there already a file with this name?
    ADDQ.L  #$4,SP               ; Pop the filename pointer off the stack
    BNE.S   .rt                  ; If not, go give up

    ; Check that the destination file is absent from the catalogue
    MOVE.L  $4(SP),-(SP)         ; Copy the filename pointer on the stack
    BSR     CatalogueExists      ; Is there already a file with this name?
    ADDQ.L  #$4,SP               ; Pop the filename pointer off the stack
    EORI.B  #$04,CCR             ; Invert Z because existing is bad...
    BNE.S   .rt                  ; ...it means we need to give up

    ; Copy the source filename to the disk block buffer
    MOVE.L  $8(SP),-(SP)         ; We want to copy from the argument filename...
    PEA.L   zBlock(PC)           ; ...to the disk block buffer
    BSR     StrCpy255            ; And here we go
    ADDQ.L  #$8,SP               ; Pop arguments off the stack

    ; Copy the destination filename to the disk block buffer
    MOVE.L  $4(SP),-(SP)         ; We want to copy from the argument filename...
    MOVE.L  A0,-(SP)             ; ...to just after the source filename
    BSR     StrCpy255            ; And here we go
    ADDQ.L  #$8,SP               ; Pop arguments off the stack

    ; Issue the command to the Cameo/Aphid (D2 was set much earlier)
    MOVE.L  #kCatBlockWr,D1      ; We wish to write to the "magic" block
    LEA.L   zBlock(PC),A0        ; The filenames are in zBlock
    MOVEA.L zProFileIoPtr(PC),A1   ; Copy ProFile I/O routine address to A1
    JSR     (A1)                 ; Call the ProFile I/O routine

.rt RTS
