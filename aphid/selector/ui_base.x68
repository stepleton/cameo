* Cameo/Aphid disk image selector: Fundamental text display routines
* ==================================================================
*
* Forfeited into the public domain with NO WARRANTY. Read LICENSE for details.
*
* Routines for preparing the screen for text display, displaying text, and
* moving text around on the screen. Uses the `lisa_console_screen.x68`
* component of the `lisa_io` library, along with its 8x9 pixel (with one
* additional pixel of line spacing) "Lisa_Console" font.
*
* Code that INCLUDEs this file must have defined `kSecCode` and `kSecData` as
* section symbols, ideally for a section containing the rest of the application
* code and a section containing immutable application data respectively.
*
* These procedures make use of the zLisaConsoleScreenBase value defined in
* `lisa_console_screen.x68`. This value is set by the `InitLisaConsoleScreen`
* procedure, which must have run before using any code defined here.
*
* Public procedures:
*    - UiInvertBox -- Invert a rectangle of characters
*    - UiClearBox -- Clear a rectangle of characters
*    - UiScrollBox -- Vertical scroll within a rectangle of characters
*    - UiShiftLine -- Horizontal shift part of a character line
*    - UiPrintStr -- Print a null-terminated string
*    - UiPrintStrN -- Print up to N characters of a null-terminated string
*    - UiPutc -- Print a single character and advance the cursor horizontally
*    - FlushCops -- Clear any bytes that the COPS might be waiting to send us
*
* All public procedures that take arguments have corresponding convenience
* macros defined in `ui_macros.x68`. In addition to those, there are additional
* macros to help build our application:
*
*    - mUiPrintLit -- Print a literal string
*    - mUiPrint -- Print multiple items
*    - mUiGotoRC -- Designate the screen position for the next print operation
*    - mUiGotoR -- Designate the screen row for the next print operation
*    - mUiGotoC -- Designate the screen column for the next print operation


* ui_base Includes ------------------------------


    SECTION kSecData
    INCLUDE lisa_io/font_Lisa_Console.x68

    SECTION kSecScratch            ; Force word alignment for kSecScratch values
    DS.W    0                      ; in lisa_console_screen (TODO: fix there!)
    SECTION kSecCode
    INCLUDE lisa_io/lisa_console_screen.x68
    defineLisaConsole              ; Build display code for the LisaConsole font


* ui_base Code ----------------------------------


    SECTION kSecCode


    ; UiInvertBox -- Invert a rectangle of characters
    ; Args:
    ;   SP+$A: w. Width of the rectangle, in columns
    ;   SP+$8: w. Height of the rectangle, in rows
    ;   SP+$6: w. Top-left corner of the rectangle, in columns
    ;   SP+$4: w. Top-left corner of the rectangle, in rows
    ; Notes:
    ;   Boxes that overlap screen boundaries cause undefined behaviour
    ;   Trashes D0-D1/A0-A1
UiInvertBox:
    BSR.S   _UiSetupClrInvBoxRegs  ; Set D0-D1/A0-A1 for the following

    ; Outer loop: over pixel rows
.lo SWAP.W  D0                     ;   Unstash row bytes loop iterator
    MOVE.W  D0,D1                  ;   Copy into D1
    SWAP.W  D0                     ;   Restash row bytes loop iterator

    ; Inner loop: over character columns
.li NOT.B   (A0)+                  ;     Invert the byte in this column
    DBRA    D1,.li                 ;     Loop to invert in the next column

    ADDA.W  A1,A0                  ;   Advance A0 to the next row start byte
    DBRA    D0,.lo                 ;   Loop to invert bytes in the next row

    RTS


    ; UiClearBox -- Clear a rectangle of characters
    ; Args:
    ;   SP+$A: w. Width of the rectangle, in columns
    ;   SP+$8: w. Height of the rectangle, in rows
    ;   SP+$6: w. Top-left corner of the rectangle, in columns
    ;   SP+$4: w. Top-left corner of the rectangle, in rows
    ; Notes:
    ;   Boxes that overlap screen boundaries cause undefined behaviour
    ;   Trashes D0-D1/A0-A1
UiClearBox:
    BSR.S   _UiSetupClrInvBoxRegs  ; Set D0-D1/A0-A1 for the following

    ; Outer loop: over pixel rows
.lo SWAP.W  D0                     ;   Unstash row bytes loop iterator
    MOVE.W  D0,D1                  ;   Copy into D1
    SWAP.W  D0                     ;   Restash row bytes loop iterator

    ; Inner loop: over character columns
.li CLR.B   (A0)+                  ;     Clear the byte in this column
    DBRA    D1,.li                 ;     Loop to clear in the next column

    ADDA.W  A1,A0                  ;   Advance A0 to the next row start byte
    DBRA    D0,.lo                 ;   Loop to clear bytes in the next row

    RTS


    ; _UiSetupClrInvBoxRegs -- Set D0/A0-A1 for Ui(Clear|Invert)Box
    ; Args:
    ;   SP+$E: w. Width of the rectangle, in columns
    ;   SP+$C: w. Height of the rectangle, in rows
    ;   SP+$A: w. Top-left corner of the rectangle, in columns
    ;   SP+$8: w. Top-left corner of the rectangle, in rows
    ; Notes:
    ;   Sets D0 MSW to be a loop iterator for looping over columns
    ;   Sets D0 LSW to be a loop iterator for looping over pixel rows
    ;   Sets A0 to point to the very first byte to change
    ;   Sets A1 to an increment for A0 from one row to the next
    ;   Trashes D0-D1/A0-A1
_UiSetupClrInvBoxRegs:
    ; Compute the address of initial byte to clear: first, the screenbase offset
    MOVE.W  $8(SP),D0              ; Copy starter text row from the stack
    MULU.W  #$384,D0               ; Multiply by 900 (10 rows * 90 bytes/row)
    ADD.W   $A(SP),D0              ; Finally, add starter column as an offset
    ; Next, add it to the screenbase
    MOVE.L  zLisaConsoleScreenBase,A0  ; Load the screenbase to A0
    ADDA.W  D0,A0                  ; Add the offset

    ; Compute how many bytes to skip after blanking out a pixel row
    MOVEA.W #$5A,A1                ; A pixel row is 90 bytes wide
    SUBA.W  $E(SP),A1              ; Subtract the width of the rectangle

    ; Compute loop iterator for number of bytes to clear per pixel row
    MOVE.W  $E(SP),D0              ; Copy rectangle width from the stack
    SUBQ.W  #$1,D0                 ; Subtract 1 for the loop iterator
    SWAP.W  D0                     ; Stash in high word of D0
    ; Compute loop iterator for number of pixel rows to clear
    MOVE.W  $C(SP),D0              ; Copy rectangle height from the stack
    MOVE.W  D0,D1                  ; Copy again to D1
    LSL.W   #$3,D0                 ; Multiply by eight in D0
    LSL.W   #$1,D1                 ; Multiply by two in D1
    ADD.W   D1,D0                  ; Add into D0 for times 10, the final value
    SUBQ.W  #$1,D0                 ; Subtract 1 for the loop iterator

    RTS


    ; UiScrollBox -- Scroll vertically within a rectangle of characters
    ; Args:
    ;   SP+$C: w. Number of rows to scroll; can be negative
    ;   SP+$A: w. Width of the rectangle, in columns
    ;   SP+$8: w. Height of the rectangle, in rows
    ;   SP+$6: w. Top-left corner of the rectangle, in columns
    ;   SP+$4: w. Top-left corner of the rectangle, in rows
    ; Notes:
    ;   Region that new text would scroll into is left blank
    ;   Boxes that overlap screen boundaries cause undefined behaviour
    ;   Scrolling more rows than the box contains causes undefined behaviour
    ;   Trashes D0-D1/A0-A1
UiScrollBox:
    TST.W   $C(SP)                 ; Inspect the number of rows to scroll
    BMI.S   _UiScrollBoxUp         ; If negative, jump to scroll up
    BNE.S   _UiScrollBoxDown       ; If positive, jump to scroll down
    RTS                            ; Otherwise, quit straightaway

    ; Downward scrolling for UiScrollBox -- that is, the text moves upward
_UiScrollBoxDown:
    ; 1. Prepare D0-D1/A0-A1 for _UiMovePixelsBackward

    ; Compute address of the initial dest. byte; first, the screenbase offset
    MOVE.W  $4(SP),D0              ; Copy starter row from the stack
    MULU.W  #$384,D0               ; Multiply by 900 (10 rows * 90 bytes/row)
    ADD.W   $6(SP),D0              ; Finally, add starter column as an offset
    ; Next, add it to the screenbase
    MOVE.L  zLisaConsoleScreenBase,A0  ; Load the screenbase to A0
    ADDA.W  D0,A0                  ; Add the offset

    ; Compute address of the initial source byte; first, the destination offset
    MOVE.W  $C(SP),D0              ; Copy number of rows to scroll from stack
    MULU.W  #$384,D0               ; Multiply by 900 (10 rows * 90 bytes/row)
    ; Next, add it to the destination and store in A1
    LEA.L   $0(A0,D0.W),A1         ; Can happen all at once

    ; Compute loop iterator for number of bytes to copy per pixel row
    MOVE.W  $A(SP),D0              ; Copy rectangle width from the stack
    SUBQ.W  #$1,D0                 ; Subtract 1 for the loop iterator
    SWAP.W  D0                     ; Stash in the high word of D0
    ; Compute loop iterator for number of pixel rows to copy
    MOVE.W  $8(SP),D0              ; Copy rectangle height from the stack
    SUB.W   $C(SP),D0              ; Subtract the number of rows to scroll
    MOVE.W  D0,D1                  ; Copy again to D1
    LSL.W   #$3,D0                 ; Multiply by eight in D0
    LSL.W   #$1,D1                 ; Multiply by two in D1
    ADD.W   D1,D0                  ; Add into D0 for times 10,
    SUBQ.W  #$1,D0                 ; Subtract 1 for the loop iterator

    ; Compute how many bytes to skip after copying a pixel row
    MOVEQ.L #$5A,D1                ; A pixel row is 90 bytes wide
    SUB.W   $A(SP),D1              ; Subtract the width of the rectangle

    ; 2. Move bytes and clear the places they came from
    BSR.S   _UiMovePixelsBackward

    ; 3. Clear any pixels that haven't been cleared yet
    BRA.S   _UiScrollBoxClearLeftovers

    ; Upward scrolling for UiScrollBox -- that is, the text moves downward
_UiScrollBoxUp:
    ; 1. Prepare D0-D1/A0-A1 for _UiMovePixelsForward

    ; Compute address just past final dest. byte; first, the screenbase offset
    MOVE.W  $4(SP),D0              ; Copy starter row from the stack
    ADD.W   $8(SP),D0              ; Add number of rows that the box has
    MULU.W  #$384,D0               ; Multiply by 900 (10 rows * 90 bytes/row)
    SUB.W   #$5A,D0                ; Subtract one row of pixels
    ADD.W   $6(SP),D0              ; Add starter column as an offset
    ADD.W   $A(SP),D0              ; Add rectangle width as an offset
    ; Next, add it to the screenbase
    MOVE.L  zLisaConsoleScreenBase,A0  ; Load the screenbase to A0
    ADDA.W  D0,A0                  ; Add the offset

    ; Compute addr. just past initial source byte; first, the destination offset
    MOVE.W  $C(SP),D0              ; Copy (negative) number of rows to scroll
    MULU.W  #$384,D0               ; Multiply by 900 (10 rows * 90 bytes/row)
    ; Next, add it to the destination and store in A1
    LEA.L   $0(A0,D0.W),A1         ; Can happen all at once

    ; Compute loop iterator for number of bytes to copy per pixel row
    MOVE.W  $A(SP),D0              ; Copy rectangle width from the stack
    SUBQ.W  #$1,D0                 ; Subtract 1 for the loop iterator
    SWAP.W  D0                     ; Stash in the high word of D0
    ; Compute loop iterator for number of pixel rows to copy
    MOVE.W  $8(SP),D0              ; Copy rectangle height from the stack
    ADD.W   $C(SP),D0              ; Add (negative) number of rows to scroll
    MOVE.W  D0,D1                  ; Copy again to D1
    LSL.W   #$3,D0                 ; Multiply by eight in D0
    LSL.W   #$1,D1                 ; Multiply by two in D1
    ADD.W   D1,D0                  ; Add into D0 for times 10
    SUBQ.W  #$1,D0                 ; Subtract 1 for the loop iterator

    ; Compute how many bytes to retreat after copying a pixel row
    MOVEQ.L #$5A,D1                ; A pixel row is 90 bytes wide
    SUB.W   $A(SP),D1              ; Subtract the width of the rectangle

    ; 2. Move bytes and clear the places they came from
    BSR.S   _UiMovePixelsForward

    ; 3. Clear any pixels that haven't been cleared yet
    ; If we scroll over half the height of the box, then there will be text in
    ; the middle of the box that _UiMovePixels* "flew over", and that therefore
    ; still need to be cleared. We check whether this condition holds; if it
    ; does, we alter our own arguments to suit UiClearBox, jump there, and let
    ; that subroutine return to our caller for us.
    NEG.W   $C(SP)                 ; Make number of rows to scroll positive
_UiScrollBoxClearLeftovers:
    MOVE.W  $8(SP),D0              ; Copy box height to D0
    MOVE.W  $C(SP),D1              ; Copy number of rows to scroll to D1
    SUB.W   D1,D0                  ; D0: offset of top of area to clear, if any
    SUB.W   D0,D1                  ; D1: now height of that area, if any
    BLE.S   .rt                    ; There wasn't that area? Return to caller

    ADD.W   D0,$4(SP)              ; There was; shift the clear box start row
    MOVE.W  D1,$8(SP)              ; And update the clear box height
    BRA     UiClearBox             ; Jump to the box clearer; have it return

.rt RTS                            ; This line's only used if we cleared nothing


    ; _UiMovePixelsBackward -- Move pixel data backward in memory; clear source
    ; Args:
    ;   D0 MSW: w. a loop iterator for looping over columns
    ;   D0 LSW: w. a loop iterator for looping over pixel rows
    ;   D1 LSW: w. an increment for A0 and A1 from one row to the next
    ;   A0: Destination for bytes being copied whilst scrolling
    ;   A1: Source of bytes being copied whilst scrolling
    ; Notes:
    ;   Helper for various scrollers and shifters
    ;   Use when A1 > A0; otherwise use _UiMovePixelsForward
    ;   Source bytes are all cleared immediately after they are copied
    ;   Number of pixel columns to move must be a multiple of 8
    ;   D0 MSW is (pixel cols / 8) - 1
    ;   D0 LSW is (pixel rows) - 1
    ;   A1 should point at the top left byte of pixels to move
    ;   A0 should point at where that byte of pixels should be moved to
_UiMovePixelsBackward:
    ; Outer loop: over pixel rows
.lo SWAP.W  D1                     ;   Stash the inter-row bytes-to-skip count
    SWAP.W  D0                     ;   Unstash row bytes (column) loop iterator
    MOVE.W  D0,D1                  ;   Copy into D1
    SWAP.W  D0                     ;   Restash column iterator, get row iterator

    ; Inner loop: over character columns
.li MOVE.B  (A1),(A0)+             ;     Copy the byte in this column
    CLR.B   (A1)+                  ;     Clear the source byte
    DBRA    D1,.li                 ;     Loop to copy in the next column

    SWAP.W  D1                     ;   Unstash the inter-row bytes-to-skip count
    ADDA.W  D1,A0                  ;   Advance the destination to the next row
    ADDA.W  D1,A1                  ;   Advance the source to the next row
    DBRA    D0,.lo                 ;   Loop to copy bytes in the next row

    RTS


    ; _UiMovePixelsForward -- Move pixel data forward in memory; clear source
    ; Args:
    ;   D0 MSW: w. a loop iterator for looping over columns
    ;   D0 LSW: w. a loop iterator for looping over pixel rows
    ;   D1 LSW: w. a decrement for A0 and A1 from one row to the next
    ;   A0: Destination for bytes being copied whilst scrolling
    ;   A1: Source of bytes being copied whilst scrolling
    ; Notes:
    ;   Helper for various scrollers and shifters
    ;   Use when A1 < A0; otherwise use _UiMovePixelsBackward
    ;   Source bytes are all cleared immediately after they are copied
    ;   Number of pixel columns to move must be a multiple of 8
    ;   D0 MSW is (pixel cols / 8) - 1
    ;   D0 LSW is (pixel rows) - 1
    ;   A1 should point just past the bottom right byte of pixels to move
    ;   A0 should point just past where that byte of pixels should be moved to
_UiMovePixelsForward:
    ; Outer loop: over pixel rows
.lo SWAP.W  D1                     ;   Stash the inter-row bytes-to-skip count
    SWAP.W  D0                     ;   Unstash row bytes (column) loop iterator
    MOVE.W  D0,D1                  ;   Copy into D1
    SWAP.W  D0                     ;   Restash column iterator, get row iterator

    ; Inner loop: over character columns
.li MOVE.B  -(A1),-(A0)            ;     Copy the byte in this column
    CLR.B   (A1)                   ;     Clear the source byte
    DBRA    D1,.li                 ;     Loop to copy in the preceeding column

    SWAP.W  D1                     ;   Unstash the inter-row bytes-to-skip count
    SUBA.W  D1,A0                  ;   Retreat the destination to the next row
    SUBA.W  D1,A1                  ;   Retreat the source to the next row
    DBRA    D0,.lo                 ;   Loop to copy bytes in the preceeding row

    RTS


    ; UiShiftLine -- Horizontal shift part of a character line
    ; Args:
    ;   SP+$A: w. Width of the shift region
    ;   SP+$8: w. Number of columns to shift
    ;   SP+$6: w. Leftmost column of the shift region
    ;   SP+$4: w. Which row to apply the shift to
    ; Notes:
    ;   Region that new text would scroll into is left blank
    ;   Lines that extend beyond screen boundaries cause undefined behaviour
    ;   Shifting more columns than the region holds causes undefined behaviour
    ;   Trashes D0-D1/A0-A1
UiShiftLine:
    TST.W   $8(SP)                 ; Inspect the number of columns to shift
    BMI.S   _UiShiftLineLeft       ; If negative, jump to shift left
    BNE.S   _UiShiftLineRight      ; If positive, jump to shift right
.rt RTS                            ; Otherwise quit straightaway

    ; Leftward shifting for UiShiftLine
_UiShiftLineLeft:
    ; 1. Prepare D0-D1/A0-A1 for _UiMovePixelsBackward

    ; Compute address of the initial dest. byte; first, the screenbase offset
    MOVE.W  $4(SP),D0              ; Copy row from the stack
    MULU.W  #$384,D0               ; Multiply by 900 (10 rows * 90 bytes/row)
    ADD.W   $6(SP),D0              ; Finally, add leftmost column as an offset
    ; Next, add it to the screenbase
    MOVE.L  zLisaConsoleScreenBase,A0  ; Load the screenbase to A0
    ADDA.W  D0,A0                  ; Add the offset

    ; Compute address of the initial source byte
    MOVEA.L A0,A1                  ; Copy initial destination byte
    SUBA.W  $8(SP),A1              ; Subtract (negative) number of cols to shift

    ; Compute loop iterator for number of bytes to copy per pixel row, as well
    ; as the inter-row pointer increment
    MOVE.W  $A(SP),D0              ; Copy rectangle width from the stack
    ADD.W   $8(SP),D0              ; Add (negative) number of columns to shift
    MOVEQ.L #$5A,D1                ; (For the inter-row increment, load 90...
    SUB.W   D0,D1                  ; ...then subtract number of bytes to copy)
    SUBQ.W  #$1,D0                 ; Subtract 1 for the loop iterator
    SWAP.W  D0                     ; Stash in the high word of D0
    ; And the number of rows to copy is fixed
    MOVE.W  #$9,D0                 ; It's always 9, height of one row minus 1

    ; 2. Move bytes and clear the places they came from
    BSR.S   _UiMovePixelsBackward

    ; 3. Clear any pixels that haven't been cleared yet
    NEG.W   $8(SP)                 ; Make number of columns to shift positive
    BRA.S   _UiShiftLineClearLeftovers

    ; Rightward shifting for UiShiftLine
_UiShiftLineRight:
    ; 1. Prepare D0-D1/A0-A1 for _UiMovePixelsForward

    ; Compute address just past final dest. byte; first, the screenbase offset
    MOVE.W  $4(SP),D0              ; Copy row from the stack
    MULU.W  #$384,D0               ; Multiply by 900 (10 rows * 90 bytes/row)
    ADD.W   #$32A,D0               ; Add 9 * 90 to get to the bottom pixel row
    ADD.W   $6(SP),D0              ; Add leftmost column as an offset
    ADD.W   $A(SP),D0              ; Add region width as an offset
    ; Next, add it to the screenbase
    MOVE.L  zLisaConsoleScreenBase,A0  ; Load the screenbase to A0
    ADDA.W  D0,A0                  ; Add the offset

    ; Compute address just past final source byte
    MOVEA.L A0,A1                  ; Copy initial destination byte
    SUBA.W  $8(SP),A1              ; Subtract number of columns to shift

    ; Compute loop iterator for number of bytes to copy per pixel row, as well
    ; as the inter-row pointer decrement
    MOVE.W  $A(SP),D0              ; Copy rectangle width from the stack
    SUB.W   $8(SP),D0              ; Subtract number of columns to shift
    MOVEQ.L #$5A,D1                ; (For the inter-row increment, load 90...
    SUB.W   D0,D1                  ; ...then subtract number of bytes to copy)
    SUBQ.W  #$1,D0                 ; Subtract 1 for the loop iterator
    SWAP.W  D0                     ; Stash in the high word of D0
    ; And the number of rows to copy is fixed
    MOVE.W  #$9,D0                 ; It's always 9, height of one row minus 1

    ; 2. Move bytes and clear the places they came from
    BSR     _UiMovePixelsForward

    ; 3. Clear any pixels that haven't been cleared yet
    ; If we shift over half the width of the box, then there will be text in
    ; the middle of the box that _UiMovePixels* "flew over", and that therefore
    ; still need to be cleared. We check whether this condition holds; if it
    ; does, we alter our own arguments to suit UiClearBox, jump there, and let
    ; that subroutine return to our caller for us.
_UiShiftLineClearLeftovers:
    MOVE.W  $A(SP),D0              ; Copy box width to D0
    MOVE.W  $8(SP),D1              ; Copy number of columns to shift to D1
    SUB.W   D1,D0                  ; D0: offset of left of area to clear, if any
    SUB.W   D0,D1                  ; D1: now width of that area, if any
    BLE.S   .rt                    ; There wasn't that area? Return to caller

    ADD.W   D0,$6(SP)              ; There was; shift the clear box start column
    MOVE.W  D1,$A(SP)              ; And update the clear box width
    MOVE.W  #$1,$8(SP)             ; The clear box height is always 1
    BRA     UiClearBox             ; Jump to the box clearer; have it return

.rt RTS


    ; UiPrintStr -- Print a null-terminated string
    ; Args:
    ;   SP+$4: l. Address of a null-terminated string to print
    ; Notes:
    ;   Notes for Print\1 of lisa_console_screen.x68 apply here as well
    ;   Trashes D0-D1/A0-A1
UiPrintStr:
    MOVEA.L $4(SP),A0              ; Set up address argument to PrintLisaConsole
    MOVEM.L D2/A2-A3,-(SP)         ; Save registers it uses that we should save
    BSR     PrintLisaConsole       ; Print the string
    MOVEM.L (SP)+,D2/A2-A3         ; Restore saved registers
    RTS


    ; UiPrintStrN -- Print up to N characters of a null-terminated string
    ; Args:
    ;   SP+$6: l. Address of a null-terminated string to print
    ;   SP+$4: w. Maximum number of characters to print
    ; Notes:
    ;   Notes for Print\1 of lisa_console_screen.x68 apply here as well
    ;   Modifies the string to print (temporarily) --- not thread safe!
    ;   Trashes D0-D1/A0-A1
UiPrintStrN:
    MOVEA.L $6(SP),A0              ; Set up address argument to PrintLisaConsole
    MOVE.W  $4(SP),D0              ; Copy max string length to D0

    MOVE.B  $0(A0,D0.W),-(SP)      ; Push the byte at position N on the stack
    CLR.B   $0(A0,D0.W)            ; And turn that byte into a null terminator
    MOVEM.L D2/A2-A3,-(SP)         ; Save the registers we should save

    BSR     PrintLisaConsole       ; Print the string

    MOVEM.L (SP)+,D2/A2-A3         ; Restore saved registers
    MOVE.L  $8(SP),A0              ; Restore address argument again
    MOVE.W  $6(SP),D0              ; Copy max string length to D2, again

    MOVE.B  (SP)+,$0(A0,D0.W)      ; Restore the byte at position N
    RTS


    ; UiPutc -- Print a single character and advance the cursor horizontally
    ; Args:
    ;   SP+$4: b. Character to print
    ; Notes:
    ;   Notes for Putc\1 of lisa_console_screen.x68 apply here as well
    ;   DOES NOT ADVANCE TO THE NEXT LINE IF A NEWLINE CHARACTER IS ENCOUNTERED
    ;   DOES NOT ADVANCE TO THE NEXT LINE IF THE CURSOR IS AT THE LAST COLUMN
    ;   Trashes A0-A1/D0-D1
UiPutc:
    MOVE.L  D2,-(SP)               ; Save D2 on the stack
    CLR.W   D0                     ; We need D0's MSByte to be clear
    MOVE.B  $8(SP),D0              ; Copy byte for character to print to D0
    LEA.L   zColLisaConsole(PC),A0   ; Point A0 at the column to print to
    MOVE.W  (A0),D1                ; Copy that column to D1
    ADDQ.W  #$1,(A0)               ; Increment the column in RAM for next time
    MOVE.W  zRowLisaConsole(PC),D2   ; Copy row for character to print to D2
    BSR     PutcLisaConsole        ; Go print the character
    MOVE.L  (SP)+,D2               ; Restore D2 from the stack
    RTS


    ; FlushCops -- Clear any bytes that the COPS might be waiting to send us
    ; Args:
    ;   (none)
    ; Notes:
    ;   Trashes D0-D1/A0-A1
FlushCops:
    BSR     LisaConsolePollKbMouse   ; Poll the COPS for any input
    BCS.S   FlushCops              ; Keep flushing input if we got any
    RTS
