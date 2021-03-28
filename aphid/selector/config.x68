* Cameo/Aphid disk image selector: Configuration management
* =========================================================
*
* Forfeited into the public domain with NO WARRANTY. Read LICENSE for details.
*
* Routines for accessing and updating Cameo/Aphid configuration information,
* stored durably in the key/value store.
*
* These routines make use of routines and data definitions set forth in
* block.x68 and key_value.x68. (Transitive dependencies are not listed.)
*
* Durable configuration information is kept in a 512-byte key/value store block
* under the key 'Selector: config   ×' and is usually associated with the
* key/value cache key 'SC'. (The '×' is ISO-8859-1 character $D7 and appears in
* the key to make it difficult for users to manipulate the config with the
* key/value store editor.) The contents of this block are described in the
* configuration record definition below.
*
* Where possible, these procedures are designed to be extensible to multiple
* versions of the configuration record's structure. The current and only version
* so far is version 1.
*
* Public procedures:
*    - Conf1New -- Make a new version 1 config record
*    - ConfLoad -- Load configuration information into the key/value cache
*    - ConfRead -- Read a config record from the key/value store cache
*    - ConfPut -- Write a config record to the key/value store
*    - ConfIsOk -- Basic checks for a config record
*    - ConfFeatureSet -- Set a bit in the feature bitmap
*    - ConfFeatureClear -- Clear a bit in the feature bitmap
*    - ConfFeatureTest -- Test a bit in the feature bitmap
*    - ConfMonikerGet -- Retrieve the address of the moniker
*    - ConfMonikerSet -- Change the moniker
*    - ConfPasswordGet -- Retrieve the address of the autoboot password
*    - ConfPasswordSet -- Change the autoboot password


* config Defines --------------------------------


    ; Configuration record definition (version 1)
    ;
    ; All public procedures defined here take the address of a configuration
    ; record as an argument. As blocks read from the Cameo/Aphid key/value store
    ; plugin, these records are always 512-bytes long, and are mostly empty for
    ; the time being.
    ;
    ; All configuration records start with the (high) nibble $4. The next three
    ; nibbles code the version of the record's structure, and for version 1,
    ; they are $001. We use a versioning scheme for these records because they
    ; are stored durably, and we want to be able to change the record structure
    ; someday without harming our ability to recognise and interpret records
    ; that use an older format.
    ;
    ; The features bitmap is a 32-bit bitmap for encoding binary configuration
    ; options (called "features" for no good reason). The features defined so
    ; far are:
    ;
    ;     $00000001 - A "boot image" bitmap is present in the key/value store
    ;                 under key 'Selector: bitmap    ' and should be shown
    ;                 when the selector program starts.
    ;     $00000002 - The "boot script" in the key/value store should be
    ;                 executed automatically by the selector program.
    ;     $00000004 through $80000000 - Unallocated
    ;
    ; The "moniker" is a unique name for a specific Cameo/Aphid, used to
    ; identify the device to users and to the boot selector program. It can be
    ; up to 15 characters long. If shorter than 15 characters, it must be
    ; terminated with an extra NUL character; if exactly 15 characters, a
    ; "safety" NUL that is permanently stored in the record serves as the
    ; terminator.
    ;
    ; The boot program version indicates the "dialect" (version) of the
    ; language used by the boot script stored in the key/value store, if any.
    ; For now there is only one dialect, so this byte should be set to 0.
    ;
    ; If the autoboot password is present and not the empty string, then
    ; anyone who wants to stop the Selector from executing the "boot script"
    ; will need to supply the password when prompted on startup.
    ;
    ; A configuration record probably ought to be word-aligned. See comments
    ; regarding word alignment at individual procedure definitions below.
    ;
    ; The final two bytes of a configuration record are a checksum of the
    ; record data. The routines BlockCsumSet and BlockCsumCheck in block.x68
    ; can set and check this checksum respectively.
    ;
    ; The following symbols give names to byte offsets within configuration
    ; records:

kC_Sentinel EQU  $0                ; b. Sentinel byte '@' (0x40)
kC_Version  EQU  $1                ; b. Config record structure version

kC_1Feature EQU  $2                ; l. Features bitmap

kC_1Moniker EQU  $6                ; b[15]. Moniker string
kC_1MSafNul EQU  $15               ; b. Moniker safety NUL location

kC_1BPrgVer EQU  $16               ; b. Boot script language version
                                   ;    (not yet used; leave set to 0)

kC_1Passwd  EQU  $17               ; b[8]. Autoboot password
kC_1PSafNul EQU  $1F               ; b. Autoboot password safety NUL location

    ; All unallocated space is reserved for future use (heh, sure)

kC_1Cksum   EQU  $1FE              ; w. Checksum

    ; These constants select specific bits in the feature bitmap
kC_FBitmap  EQU  $0                ; Feature bit 0: is there a boot bitmap?
kC_FBScript EQU  $1                ; Feature bit 1: execute a boot script?


* config Code -----------------------------------


    SECTION kSecCode


    ; Conf1New -- Make a new version 1 config record
    ; Args:
    ;   SP+$4: l. Address receiving a new version 1 config record
    ; Notes:
    ;   The record must be word-aligned
    ;   Trashes D0/A0
Conf1New:
    MOVE.L  $4(SP),-(SP)           ; Duplicate address argument on stack
    BSR     BlockZero              ; Zero out the record block
    MOVEA.L (SP),A0                ; Copy record address to A0

    MOVE.W  #$4001,kC_Sentinel(A0)   ; Set sentinel and record bytes

    PEA.L   _kC_DefaultMoniker(PC)   ; Prepare to copy default...
    PEA.L   kC_1Moniker(A0)        ; ...moniker into the record...
    MOVE.W  #(kC_1MSafNul-kC_1Moniker),-(SP)   ; ...all 15 bytes of it
    BSR     Copy                   ; Do the copy
    ADDQ.L  #$8,SP                 ; Pop off Copy arguments, part 1
    ADDQ.L  #$2,SP                 ; Pop off Copy arguments, part 2

    ; The rest of the config should remain $00
    ; This includes kC_1Passwd and kC_1PSafNul

    BSR     BlockCsumSet           ; Compute checksum for the record
    ADDQ.L  #$4,SP                 ; Pop data structure address copy
    RTS


    ; ConfLoad -- Load configuration information into the key/value cache
    ; Args:
    ;   (none)
    ; Notes:
    ;   Information is only loaded into the Cameo/Aphid's key/value cache, not
    ;       onward into our RAM
    ;   Z will be set iff the load operation was successful
    ;   Trashes D1/A0-A1
ConfLoad:
    PEA.L   kKV_LoadRequest(PC)    ; Use this pre-filled load request to fill...
    BSR     KeyValueLoad           ; ...the key/value cache with config data
    ADDQ.L  #$4,SP                 ; Pop the load request address off the stack
    RTS


    ; ConfRead -- Read a config record from the key/value store cache
    ; Args:
    ;   SP+$4: l. Address receiving the config record
    ; Notes:
    ;   The entry under the key 'Selector: config   ×' must have already been
    ;       loaded into the key/value store's cache under cache key 'SC';
    ;       see also ConfLoad
    ;   It's advisable for the loading address to be word-aligned
    ;   Z will be set iff the read operation was successful
    ;   Does not check that the configuration is initialised
    ;   Trashes D0/A0-A1 and the zBlock disk block buffer
ConfRead:
    MOVE.W  #'SC',-(SP)            ; Read the value cached under 'SC'...
    BSR     KeyValueRead           ; ...into the zBlock disk block buffer
    ADDQ.L  #$2,SP                 ; Pop cache key off the stack
    BNE.S   .rt                    ; Jump to return on failure
    MOVE.L  A1,-(SP)               ; Push address to loaded data onto the stack
    MOVE.L  $8(SP),-(SP)           ; Copy destination address onto the stack
    MOVE.W  #$0200,-(SP)           ; Copy 512 bytes
    BSR     Copy                   ; Do the copy
    ADDQ.L  #$8,SP                 ; Pop off Copy arguments, part 1
    ADDQ.L  #$2,SP                 ; Pop off Copy arguments, part 2
    ORI.B   #$04,CCR               ; Success; set Z
.rt RTS


    ; ConfPut -- Write a config record to the key/value store
    ; Args:
    ;   SP+$4: l. Address of the config record to write
    ; Notes:
    ;   The record is not checked for validity; see ConfIsOk
    ;   Also updates the cached value under cache key 'SC'
    ;   Z will be set iff the storage operation was successful
    ;   Trashes D0-D1/A0-A1 and the zBlock disk block buffer
ConfPut:
    PEA.L   kKV_KeyConfig(PC)      ; Push config key/value key address
    MOVE.L  $8(SP),-(SP)           ; Copy/push config record address
    MOVE.W  #'SC',-(SP)            ; Push cache key onto the stack
    BSR     KeyValuePut            ; Stash the config record
    ADDQ.L  #$8,SP                 ; Pop off KeyValuePut arguments, part 1
    ADDQ.L  #$2,SP                 ; Pop off KeyValuePut arguments, part 2
    RTS


    ; ConfIsOk -- Basic checks for a config record
    ; Args:
    ;   SP+$4: l. Address of a config record
    ; Notes:
    ;   Works only for a v1 config record for now
    ;   The record must be word-aligned
    ;   Sets the Z flag iff the record is in good shape.
    ;   Trashes D0-D1/A0
ConfIsOk:
    MOVEA.L $4(SP),A0              ; Copy record address to A0
    CMP.W   #$4001,(A0)            ; Check sentinel and record bytes
    BNE.S   .rt                    ; Fail if they aren't $4001.
    TST.B   kC_1MSafNul(A0)        ; Is moniker "safety NUL" present?
    BNE.S   .rt                    ; Fail if not
    TST.B   kC_1PSafNul(A0)        ; Is autoboot password "safety NUL" present?
    BNE.S   .rt                    ; Fail if not
    MOVE.L  A0,-(SP)               ; Copy record address on the stack
    BSR     BlockCsumCheck         ; Check the record's checksum
    ADDQ.L  #$4,SP                 ; Pop record address off the stack
.rt RTS


    ; ConfFeatureSet -- Set a bit in the feature bitmap
    ; Args:
    ;   SP+$6: l. Address of a config record
    ;   SP+$4: w. Feature bit to set (valid values are 0 to 31)
    ; Notes:
    ;   Value of Z reflects the prior value of the feature bit
    ;   Works only for a v1 config record for now
    ;   The record must be word-aligned
    ;   Trashes D0-D1/A0
ConfFeatureSet:
    MOVEA.L $6(SP),A0              ; Copy record address to A0
    MOVE.L  kC_1Feature(A0),D0     ; Copy feature bitmap to D0
    MOVE.W  $4(SP),D1              ; Copy bit index to D1
    BSET.L  D1,D0                  ; Set the bit
    SNE.B   -(SP)                  ; If Z push $00, otherwise push $FF
    MOVE.L  D0,kC_1Feature(A0)     ; Copy feature bitmap to record
    MOVE.L  $8(SP),-(SP)           ; Duplicate address argument on stack
    BSR     BlockCsumSet           ; Compute checksum for the record
    ADDQ.L  #$4,SP                 ; Pop data structre address copy
    TST.B   (SP)+                  ; Recover original Z from stack
    RTS


    ; ConfFeatureClear -- Clear a bit in the feature bitmap
    ; Args:
    ;   SP+$6: l. Address of a version 1 config record
    ;   SP+$4: w. Feature bit to clear (valid values are 0 to 31)
    ; Notes:
    ;   Value of Z reflects the prior value of the feature bit
    ;   Works only for a v1 config record for now
    ;   Record must be word-aligned
    ;   Trashes D0-D1/A0
ConfFeatureClear:
    MOVEA.L $6(SP),A0              ; Copy record address to A0
    MOVE.L  kC_1Feature(A0),D0     ; Copy feature bitmap to D0
    MOVE.W  $4(SP),D1              ; Copy bit index to D1
    BCLR.L  D1,D0                  ; Clear the bit
    SNE.B   -(SP)                  ; If Z push $00, otherwise push $FF
    MOVE.L  D0,kC_1Feature(A0)     ; Copy feature bitmap to record
    MOVE.L  $8(SP),-(SP)           ; Duplicate address argument on stack
    BSR     BlockCsumSet           ; Compute checksum for the record
    ADDQ.L  #$4,SP                 ; Pop data structre address copy
    TST.B   (SP)+                  ; Recover original Z from stack
    RTS


    ; ConfFeatureTest -- Test a bit in the feature bitmap
    ; Args:
    ;   SP+$6: l. Address of a config record
    ;   SP+$4: w. Feature bit to test (valid values are 0 to 31)
    ; Notes:
    ;   Value of Z reflects the value of the feature bit
    ;   Works only for a v1 config record for now
    ;   The record must be word-aligned
    ;   Trashes D0-D1/A0
ConfFeatureTest:
    MOVEA.L $6(SP),A0              ; Copy record address to A0
    MOVE.L  kC_1Feature(A0),D0     ; Copy feature bitmap to D0
    MOVE.W  $4(SP),D1              ; Copy bit index to D1
    BTST.L  D1,D0                  ; Test the bit
    RTS


    ; ConfMonikerGet -- Retrieve the address of the moniker
    ; Args:
    ;   SP+$4: l. Address of a config record
    ; Notes:
    ;   Works only for a v1 config record for now
    ;   Places the address of the config record's moniker string into A0
    ;   Trashes A0
ConfMonikerGet:
    MOVEA.L $4(SP),A0              ; Copy record address to A0
    LEA.L   kC_1Moniker(A0),A0     ; Point A0 at the moniker contained within
    RTS


    ; ConfMonikerSet -- Change the moniker
    ; Args:
    ;   SP+$8: l. Address of a config record
    ;   SP+$4: l. Address of a new moniker string
    ; Notes:
    ;   Works only for a v1 config record for now
    ;   Moniker may be up to 15 bytes long, not counting the NUL terminator
    ;   Trashes D0-D1/A0-A1
ConfMonikerSet:
    MOVE.L  $8(SP),-(SP)           ; Duplicate record address on stack
    MOVE.L  $8(SP),-(SP)           ; Duplicate moniker address on stack
    MOVE.W  #kC_1Moniker,-(SP)     ; Push moniker field offset on stack
    MOVE.W  #(kC_1MSafNul-kC_1Moniker),-(SP)   ; We'll copy fifteen bytes
    BSR.S   _ConfStringSet         ; Perform the copy
    ADDQ.L  #$8,SP                 ; Pop off _ConfStringSet arguments, part 1
    ADDQ.L  #$4,SP                 ; Pop off _ConfStringSet arguments, part 2
    RTS


    ; ConfPasswordGet -- Retrieve the address of the autoboot password
    ; Args:
    ;   SP+$4: l. Address of a config record
    ; Notes:
    ;   Works only for a v1 config record for now
    ;   Places the address of the record's autoboot password string into A0
    ;   Trashes A0
ConfPasswordGet:
    MOVEA.L $4(SP),A0              ; Copy record address to A0
    LEA.L   kC_1Passwd(A0),A0      ; Point A0 at the moniker contained within
    RTS


    ; ConfPasswordSet -- Change the autoboot password
    ; Args:
    ;   SP+$8: l. Address of a config record
    ;   SP+$4: l. Address of a new autoboot password
    ; Notes:
    ;   Works only for a v1 config record for now
    ;   Moniker may be up to 8 bytes long, not counting the NUL terminator
    ;   Trashes D0-D1/A0-A1
ConfPasswordSet:
    MOVE.L  $8(SP),-(SP)           ; Duplicate record address on stack
    MOVE.L  $8(SP),-(SP)           ; Duplicate password address on stack
    MOVE.W  #kC_1Passwd,-(SP)      ; Push password field offset on stack
    MOVE.W  #(kC_1PSafNul-kC_1Passwd),-(SP)  ; We'll copy eight bytes
    BSR.S   _ConfStringSet         ; Perform the copy
    ADDQ.L  #$8,SP                 ; Pop off _ConfStringSet arguments, part 1
    ADDQ.L  #$4,SP                 ; Pop off _ConfStringSet arguments, part 2
    RTS


    ; _ConfStringSet -- Copy a fixed-length string into the config
    ; Args:
    ;   SP+$C: l. Address of a config record
    ;   SP+$8: l. Address of the string to copy
    ;   SP+$6: w. Offset of the config field receiving the copy
    ;   SP+$4: w. Length of the string to copy
    ; Notes:
    ;   Not strictly limited to strings: just copies (SP+$4) bytes
    ;   Doesn't pay any attention to null terminators
    ;   Trashes D0-D1/A0-A1
_ConfStringSet:
    MOVEA.L $C(SP),A0              ; Copy record address to A0
    ADDA.W  $6(SP),A0              ; Add in the field offset
    MOVE.L  $8(SP),-(SP)           ; Duplicate source address on the stack
    MOVE.L  A0,-(SP)               ; Push destination address onto the stack
    MOVE.W  $C(SP),-(SP)           ; Duplicate field size on the stack
    BSR     Copy                   ; Do the copy
    ADDQ.L  #$8,SP                 ; Pop off Copy arguments, part 1
    ADDQ.L  #$2,SP                 ; Pop off Copy arguments, part 2
    MOVE.L  $C(SP),-(SP)           ; Duplicate record address on stack
    BSR     BlockCsumSet           ; Compute checksum for the record
    ADDQ.L  #$4,SP                 ; Pop data structre address copy
    RTS


* config Data -----------------------------------


    SECTION kSecData


_kC_DefaultMoniker:
    DC.B    'No Name'              ; Default moniker for a new configuration
    DS.B    8                      ; (Padding out to 15 chars)
