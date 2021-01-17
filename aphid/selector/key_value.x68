* Cameo/Aphid disk image selector: key/value utilities
* ====================================================
*
* Forfeited into the public domain with NO WARRANTY. Read LICENSE for details.
*
* Utilities for reading values from, and writing values to, the Cameo/Aphid
* key/value store "magic block" plugin.
*
* The best way to understand the key/value store plugin is to refer to the
* documentation inside the Python module that implements it. For "stock"
* Cameo/Aphid software distributions, this is the file
* `cameo/aphid/profile_plugin_FFFEFF_key_value_store.py`.
*
* Barring that: The Cameo/Aphid key/value store associates 20-byte keys with
* 512-byte values. These entries cannot be read directly but instead must first
* be loaded into an on-device write-through cache that associates the values
* with two-byte cache keys.
*
* - Reads from the "magic block" retrieve the cached key/value pair associated
*   with the "cache key": the two-byte concatenation of the retry count and
*   sparing threshold parameters specified in the read. The first 20 bytes of
*   returned data are the key; the remaining 512 bytes are the value.
*
* - Writes to the "magic block" with retry count and sparing threshold both set
*   to $FF direct the plugin to read key/value entries into the cache. This
*   direction comes in the form of a "load request" record; see below at
*   kKV_LoadRequest for an example.
*
* - Writes to the "magic block" with any other retry count and sparing threshold
*   parameters modifies the key/value store under the specified 20-byte key and
*   overwrites the value cached under the two-byte "cache key". Note that older
*   copies of the key/value pair data under other "cache keys" are not updated.
*
* Routines starting with "KeyValueLoad" are for preparing and issuing requests
* to read values from the key/value store into the cache. "KeyValueRead" reads
* in a key/value pair from the write-through cache, and "KeyValuePut" writes a
* key/value pair into both the cache and the key/value store.
*
* All routines hard-code block $FFFEFF as the "magic block". Note that reads by
* "KeyValueRead" retrieve the result into the zBlock buffer, overwriting any
* prior contents. "KeyValuePut" can also overwrite the zBlock buffer under
* certain documented circumstances.
*
* These routines make use of data definitions set forth in selector.x68. They
* also require that the lisa_profile_io library from the lisa_io collection be
* memory-resident.
*
* Public procedures:
*    - KeyValueLoad -- Request values be loaded into the key/value store's cache
*    - KeyValueLoadReqClear -- Initialise an empty load request record
*    - KeyValueLoadReqPush -- Add entry to a load request record
*    - KeyValueLoadReqPop -- Remove last load request record entry
*    - KeyValueRead -- Read a value from the key/value store's cache
*    - KeyValuePut -- Place a value in the key/value store via write-thru cache


* key_value Defines -----------------------------


kKvBlockRd  EQU  $FFFEFF00         ; ProFileIo command: read from magic block
kKvBlockWr  EQU  $FFFEFF01         ; ProFileIo command: write to magic block


* key_value Code --------------------------------


    SECTION kSecCode


    ; KeyValueLoad -- Request values be loaded into the key/value store's cache
    ; Args:
    ;   SP+$4: l. Address of a key/value store load request record
    ; Notes:
    ;   Z will be set iff the request was successful
    ;   Trashes D1/A0-A1
KeyValueLoad:
    MOVE.L  D2,-(SP)               ; Save D2 on the stack
    MOVE.L  #kKvBlockWr,D1         ; We wish to write to the "magic" block
    MOVE.W  #$FFFF,D2              ; Cache key $FFFF means a load request
    MOVEA.L $8(SP),A0              ; Point A0 to data to write: the record
    MOVEA.L zProFileIoPtr(PC),A1   ; Copy ProFile I/O routine address to A1
    JSR     (A1)                   ; Call it
    MOVEM.L (SP)+,D2               ; Restore D2 without touching flags
    RTS


    ; KeyValueLoadReqClear -- Initialise an empty load request record
    ; Args:
    ;   SP+$4: l. Address of a key/value store load request record
    ; Notes:
    ;   Trashes A0
KeyValueLoadReqClear:
    MOVEA.L $4(SP),A0              ; Point A0 at the load request record
    CLR.B   (A0)                   ; Mark it as having zero entries
    RTS


    ; KeyValueLoadReqPush -- Add entry to a load request record
    ; Args:
    ;   SP+$A: l. Address of a key/value store load request record
    ;   SP+$6: l. Address of a 20-byte key
    ;   SP+$4: w. 16-bit key for the write-through cache
    ; Notes:
    ;   Does not check whether the load request is already full (24 entries)
    ;   Trashes D0-D1/A0-A1
KeyValueLoadReqPush:
    MOVEA.L $A(SP),A0              ; Point A0 at the request record
    MOVE.B  (A0)+,D0               ; Copy key count byte to D0; advance A0 past
    EXT.W   D0                     ; Extend D0 to word (sign should be 0)
    MULU.W  #$16,D0                ; Multiply by the request entry size (22)
    LEA     $0(A0,D0.W),A0         ; Point A0 at the new entry
    MOVE.B  $4(SP),(A0)+           ; Copy first byte of cache key
    MOVE.B  $5(SP),(A0)+           ; Copy second byte of cache key
    MOVEA.L $6(SP),A1              ; Point A1 at the 20-byte key
    MOVEQ.L #$13,D0                ; Get ready to copy 20 bytes
.lp MOVE.B  (A1)+,(A0)+            ; Copy a byte
    DBRA    D0,.lp                 ; Loop until we're done copying
    MOVEA.L $A(SP),A0              ; Point A0 at the record again
    ADDI.B  #$1,(A0)               ; Increment the load request entry count
    RTS


    ; KeyValueLoadReqPop -- Remove last load request record entry
    ; Args:
    ;   SP+$4: l. Address of a key/value store load request record
    ; Notes:
    ;   Does not check whether the load request is already empty
    ;   On return, A0 will point to the cache-key/key pair for the removed entry
    ;   Trashes D0/A0
KeyValueLoadReqPop:
    MOVEA.L $4(SP),A0              ; Point A0 at the request record
    MOVE.B  (A0),D0                ; Copy key count byte to D0
    SUBQ.B  #$1,D0                 ; Decrement key count by 1
    MOVE.B  D0,(A0)                ; Copy it back out to the record
    EXT.W   D0                     ; Extend to word (sign should be 0)
    MULU.W  #$16,D0                ; Multiply by the request entry size (22)
    LEA     $1(A0,D0),A0           ; Point A0 at the removed entry
    RTS


    ; KeyValueRead -- Read a value from the key/value store's cache
    ; Args:
    ;   SP+$4: w. 16-bit key indicating an entry in the key/value store's cache
    ; Notes:
    ;   Data read from the cache is loaded into the zBlock disk block buffer
    ;   Z will be set iff the retrieval operation was successful
    ;   A0 will point to zBlockTag and A1 to zBlockData on completion
    ;   Trashes D1/A0-A1 and the zBlock disk block buffer
KeyValueRead:
    MOVE.L  D2,-(SP)               ; Save D2 on the stack
    MOVE.L  #kKvBlockRd,D1         ; We wish to read our "magic" block
    MOVE.W  $8(SP),D2              ; The cache key is retry count+sparing thresh
    LEA.L   zBlock(PC),A0          ; We want to read into the block buffer
    MOVEA.L zProFileIoPtr(PC),A1   ; Copy ProFile I/O routine address to A1
    JSR     (A1)                   ; Call it
    MOVEM.L (SP)+,D2               ; Restore D2 without touching flags
    LEA.L   zBlockTag(PC),A0       ; Point A0 to the retrieved key
    LEA.L   zBlockData(PC),A1      ; Point A1 to the retrieved value
    RTS


    ; KeyValuePut -- Place a value in the key/value store via write-thru cache
    ; Args: 
    ;   SP+$A: l. Address of a 20-byte key
    ;   SP+$6: l. Address of a 512-byte value to store under the key
    ;   SP+$4: w. 16-bit key for the write-through cache
    ; Notes:
    ;   Addresses must be word-aligned
    ;   Avoid copies by placing the value 20 bytes after the key
    ;   If a copy is required, do not store any data in the zBlock buffer unless
    ;       the data requires no movement at all
    ;   Z will be set iff the storage operation was successful
    ;   Trashes D0-D1/A0-A1, also zBlock buffer if key+value aren't contiguous
KeyValuePut:
    ; See if key+value are contiguous in that order; if so, no copy is needed
    MOVEA.L $A(SP),A0              ; Copy key address to A0
    LEA.L   $14(A0),A1             ; Compute a 20-byte offset to that address
    CMPA.L  $6(SP),A1              ; Is it the same as the data address?
    BEQ.S   .wr                    ; If so, skip ahead to write

    ; Copy key to the zBlockTag buffer area, if necessary
    MOVE.L  $A(SP),-(SP)           ; Copy the key source address on the stack
    PEA.L   zBlockTag(PC)          ; We will copy the key to zBlockTag
    MOVE.W  #$14,-(SP)             ; The key is 20 bytes long
    BSR     Copy                   ; Perform the copy
    ADDQ.L  #$8,SP                 ; Pop Copy arguments, part 1
    ADDQ.L  #$2,SP                 ; Pop Copy arguments, part 2

    ; Copy value to the zBlockData buffer area, if necessary
    MOVE.L  $6(SP),-(SP)           ; Copy the value source address on the stack
    PEA.L   zBlockData(PC)         ; We will copy the data to zBlockData
    MOVE.W  #$200,-(SP)            ; The key is 512 bytes long
    BSR     Copy                   ; Perform the copy
    ADDQ.L  #$8,SP                 ; Pop Copy arguments, part 1
    ADDQ.L  #$2,SP                 ; Pop Copy arguments, part 2

    ; Point A0 at the data to write
    LEA     zBlockTag(PC),A0       ; Point A0 at the block buffer

    ; With A0 pointing to the data, write to the key/value store's "magic block"
.wr MOVE.L  D2,-(SP)               ; Save D2 on the stack
    MOVE.L  #kKvBlockWr,D1         ; We wish to write to "magic" block
    MOVE.W  $8(SP),D2              ; The cache key is retry count+sparing thresh
    MOVEA.L zProFileIoPtr(PC),A1   ; Copy ProFile I/O routine address to A1
    JSR     (A1)                   ; Call it
    MOVEM.L (SP)+,D2               ; Restore D2 without touching flags
    RTS


* key_value Data --------------------------------


    SECTION kSecData


    ; This baked-in read request is issued when the Selector boots, after it has
    ; confirmed that it is talking to a Cameo/Aphid device (and not e.g. a real
    ; ProFile). The requested key/value store items are configuration data for
    ; a particular Cameo/Aphid device.
kKV_LoadRequest:
    DC.B    $18                    ; Retrieve 24 items into the cache

    DC.B    'SC'                   ; First item is our global configuration
kKV_KeyConfig:
    DC.B    'Selector: config   ',$D7  ; Tamper-proofing --- see config.x68

    DC.B    'SB'                   ; Next item is the boot display bitmap
    DC.B    'Selector: bitmap    '

    DC.B    'Sa'                   ; Remaining items are the boot script data
kKV_KeyBootScript:
    DC.B    'Selector: script 00 '
    DC.B    'Sb'
    DC.B    'Selector: script 01 '
    DC.B    'Sc'
    DC.B    'Selector: script 02 '
    DC.B    'Sd'
    DC.B    'Selector: script 03 '
    DC.B    'Se'
    DC.B    'Selector: script 04 '
    DC.B    'Sf'
    DC.B    'Selector: script 05 '
    DC.B    'Sg'
    DC.B    'Selector: script 06 '
    DC.B    'Sh'
    DC.B    'Selector: script 07 '
    DC.B    'Si'
    DC.B    'Selector: script 08 '
    DC.B    'Sj'
    DC.B    'Selector: script 09 '
    DC.B    'Sk'
    DC.B    'Selector: script 10 '
    DC.B    'Sl'
    DC.B    'Selector: script 11 '
    DC.B    'Sm'
    DC.B    'Selector: script 12 '
    DC.B    'Sn'
    DC.B    'Selector: script 13 '
    DC.B    'So'
    DC.B    'Selector: script 14 '
    DC.B    'Sp'
    DC.B    'Selector: script 15 '
    DC.B    'Sq'
    DC.B    'Selector: script 16 '
    DC.B    'Sr'
    DC.B    'Selector: script 17 '
    DC.B    'Ss'
    DC.B    'Selector: script 18 '
    DC.B    'St'
    DC.B    'Selector: script 19 '
    DC.B    'Su'
    DC.B    'Selector: script 20 '
    DC.B    'Sv'
    DC.B    'Selector: script 21 '
