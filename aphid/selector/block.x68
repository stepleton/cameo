* Cameo/Aphid disk image selector: memory block utilities
* =======================================================
*
* Forfeited into the public domain with NO WARRANTY. Read LICENSE for details.
*
* Generic utilities for working with blocks of memory.
*
* Public procedures:
*    - Copy -- Copy a block of memory
*    - Zero -- Fill a block of memory with $00 bytes
*    - BlockZero -- Zero a 512-byte block
*    - BlockCsumCheck -- Check the trailing checksum of a 512-byte block
*    - BlockCsumSet -- Set the trailing checksum of a 512-byte block
*    - StrNCmp -- Compare null-terminated strings
*    - StrCpy255 -- Copy strings of up to 255 characters (plus terminator)



* block Code ------------------------------------


    SECTION kSecCode


    ; Copy -- Copy a block of memory
    ; Args:
    ;   SP+$A: l. Start address for the source of the copied data
    ;   SP+$6: l. Start address for the destination of the copied data
    ;   SP+$4: w. Size of the block to copy, in bytes
    ; Notes:
    ;   Will behave correctly if the source and destination overlap
    ;   Copies data byte-by-byte; could be faster if it copied words when able
    ;   Word-alignment not required
    ;   Use 32-bit clean addresses
    ;   Trashes D0-D1/A0-A1
Copy:
    CLR.L   D0                     ; Clear all of D0 so that it can take...
    MOVE.W  $4(SP),D0              ; ...the copy count, extended to a longword
    BEQ.S   .rt                    ; If block size is 0, quit early
    MOVEA.L $A(SP),A0              ; Copy source address to A0
    MOVEA.L $6(SP),A1              ; Copy destination address to A1
    MOVE.L  A1,D1                  ; Subtract source from...
    SUB.L   A0,D1                  ; ...destination address...
    BEQ.S   .rt                    ; ...(quit early if they were the same)...
    BPL.S   .ck                    ; ...and take its...
    NEG.L   D1                     ; ...absolute value
.ck CMP.L   D0,D1                  ; Difference >= the count?
    BGE.S   .cf                    ; No interference; do a forward copy
    CMPA.L  A0,A1                  ; Destination precedes the source?
    BLT.S   .cf                    ; If so, we need a forward copy

    ; Backward copy from source to destination
    ADDA.L  D0,A0                  ; Point A0 just beyond end of source
    ADDA.L  D0,A1                  ; Point A1 just beyond end of source
    SUBQ.W  #$1,D0                 ; Turn D0 into a loop counter
.lb MOVE.B  -(A0),-(A1)            ; Copy a byte
    DBRA    D0,.lb                 ; Decrement counter and loop
    BRA.S   .rt                    ; Skip ahead to quit

    ; Ordinary forward copy from source to destination
.cf SUBQ.W  #$1,D0                 ; Turn D0 into a loop counter
.lf MOVE.B  (A0)+,(A1)+            ; Copy a byte
    DBRA    D0,.lf                 ; Decrement counter and loop

.rt RTS


    ; Zero -- Fill a block of memory with $00 bytes
    ; Args:
    ;   SP+$6: l. Start address of block to zero
    ;   SP+$4: w. Size of the block to zero, in bytes
    ; Notes:
    ;   Zeros data byte-by-byte; could be faster if it zeroed words when able
    ;   Word-alignment not required
    ;   Trashes D0/A0
Zero:
    MOVE.W  $4(SP),D0              ; Copy block size to D0
    BEQ.S   .rt                    ; If block size is 0, quit early
    MOVEA.L $6(SP),A0              ; Copy block start address to A0
    SUBQ.W  #$1,D0                 ; Turn D0 into a loop counter
.lp CLR.B   (A0)+                  ; Clear a byte
    DBRA.W  D0,.lp                 ; Loop to clear the next byte
.rt RTS


    ; BlockZero -- Zero a 512-byte block
    ; Args:
    ;   SP+$4: l. Start address of block to zero
    ; Notes:
    ;   Zeros data byte-by-byte; could be faster if it zeroed words when able
    ;   Trashes D0/A0
BlockZero:
    MOVE.L  $4(SP),-(SP)           ; Duplicate address argument on stack
    MOVE.W  #$100,-(SP)            ; We need to copy 512 bytes
    BSR.S   Zero                   ; Jump to copy
    ADDQ.L  #$6,SP                 ; Pop arguments to Zero off the stack
    RTS


    ; BlockCsumCheck -- Check the trailing checksum of a 512-byte block
    ; Args:
    ;   SP+$4: l. Address of a 512-byte block to check
    ; Notes:
    ;   Address must be word-aligned
    ;   Final word in the block should be the checksum
    ;   Sets Z if the checksum is a match
    ;   Uses the checksum algorithm from the Lisa Boot ROM (reimplemented)
    ;   Trashes D0-D1/A0
BlockCsumCheck:
    MOVEA.L $4(SP),A0              ; Copy block address to A0
    MOVE.W  #$00FF,D0              ; Check 256 words
    CLR.W   D1                     ; Clear the accumulator
.lp ADD.W   (A0)+,D1               ; Add the next word to the accumulator
    ROL.W   #$1,D1                 ; Rotate the accumulator left one bit
    DBRA    D0,.lp                 ; Loop if there are more words to go
    RTS


    ; BlockCsumSet -- Set the trailing checksum of a 512-byte block
    ; Args:
    ;   SP+$4: l. Address of a 512-byte block receiving a new checksum
    ; Notes:
    ;   Final word in block will be overwritten with the checksum
    ;   Uses the checksum algorithm from the Lisa Boot ROM (reimplemented)
    ;   Trashes D0-D1/A0
BlockCsumSet:
    MOVEA.L $4(SP),A0              ; Copy block address to A0
    MOVE.W  #$00FE,D0              ; Sum 255 words
    CLR.W   D1                     ; Clear the accumulator
.lp ADD.W   (A0)+,D1               ; Add the next word to the accumulator
    ROL.W   #$1,D1                 ; Rotate the accumulator left one bit
    DBRA    D0,.lp                 ; Loop if there are more words to go
    NEG.W   D1                     ; Compute checksum's additive inverse
    MOVE.W  D1,(A0)                ; And store it at the end of the block
    RTS


    ; StrNCmp -- Compare null-terminated strings
    ; Args:
    ;   SP+$C: w. Maximum number of bytes to compare
    ;   SP+$8: l. Address of the first of the null-terminated strings
    ;   SP+$4: l. Address of the second null-terminated string
    ; Notes:
    ;   Could be faster; lots of memory accesses
    ;   Sets flags in the manner of strncmp(3) from C; if Z is set, then the
    ;       strings are equal up to the terminator or (SP+$C) characters
    ;       (whichever comes first)
    ;   Flags are not dependable if the number of bytes to compare is 0
    ;   Trashes D0-D1/A0-A1
StrNCmp:
    MOVE.W  $C(SP),D0              ; Copy character count to D0
    BEQ.S   .rt                    ; No characters? Return with Z set
    MOVEA.L $8(SP),A0              ; Point A0 at the first string
    MOVEA.L $4(SP),A1              ; Point A1 at the second string
    SUBQ.W  #$1,D0                 ; Convert D0 to a loop iterator
    MOVE.W  D2,-(SP)               ; Save D2 on the stack

.lp MOVE.B  (A0)+,D1               ; Next A0 byte into D1
    MOVE.B  (A1)+,D2               ; Next A1 byte into D2
    BEQ.S   .fc                    ; Skip ahead if A1 byte was the terminator
    TST.B   D1                     ; Was A0 byte the terminator?
    BEQ.S   .fc                    ; Skip ahead if so
    CMP.B   D2,D1                  ; Are the two bytes the same, though?
    DBNE    D0,.lp                 ; Loop again if they are

.fc CMP.B   D2,D1                  ; Set flags from comparing final bytes
    MOVEM.W (SP)+,D2               ; Recover D2 without changing flags
.rt RTS


    ; StrCpy255 -- Copy strings of up to 255 characters (plus terminator)
    ; Args:
    ;   SP+$8: l. Address of the string to copy from
    ;   SP+$4: l. Address of the string to copy to
    ; Notes:
    ;   Copies byte-wise---could be faster I guess
    ;   String source and destination must not overlap in a way where the
    ;       destination address comes after the source address, but it's okay if
    ;       the destination address precedes the source address or if they're
    ;       both the same
    ;   Sets Z iff the string to copy was 255 or fewer characters long (not
    ;       counting the null terminator), or if the two addresses were the same
    ;   Longer strings are truncated at the destination
    ;   On return, A0 points just past the copied string's terminator
    ;   Trashes D0/A0-A1
StrCpy255:
    MOVE.L  $8(SP),A1              ; A1 gets the source address
    MOVE.L  $4(SP),A0              ; A0 gets the destination address
    CMP.L   A0,A1                  ; Are they the same?
    BEQ.S   .si                    ; Simulate a copy if so by advancing A0
    CLR.W   D0                     ; We've copied 0 characters so far

.lp ADDQ.L  #$1,D0                 ; Increment number of bytes copied
    MOVE.B  (A1)+,(A0)+            ; Copy a byte
    BEQ.S   .rt                    ; Hit the terminator? Done.
    CMPI.W  #$100,D0               ; Have we copied 256 bytes
    BLO.S   .lp                    ; No, copy another byte

    ; If we fall out of the loop, we haven't finished copying and need to
    ; cut bait, null-terminate, and clear Z
    CLR.B   -1(A0)                 ; Null-terminate 
    ANDI.B  #$FB,CCR               ; Clear Z marking a copy failure
    BRA.S   .rt                    ; Jump ahead to return

    ; If here, the source and destination pointers were the same, but we still
    ; have to advance A0 to point just past the string's terminator
.si TST.B   (A0)+                  ; Test here for the terminator and advance
    BNE.S   .si                    ; Keep going if not NULL; otherwise, set Z

.rt RTS
