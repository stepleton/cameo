* Cameo/Aphid disk image selector: UI library macros
* ==================================================
*
* Forfeited into the public domain with NO WARRANTY. Read LICENSE for details.
*
* Macros for invoking various procedures in our UI library. We have:
*
* For `ui_base.x68`, macros for directly invoking the procedures:
*
*    - mUiInvertBox -- Invert a rectangle of characters
*    - mUiClearBox -- Clear a rectangle of characters
*    - mUiScrollBox -- Vertical scroll within a rectangle of characters
*    - mUiShiftLine -- Horizontal shift part of a character line
*    - mUiPrintStr -- Print a null-terminated string
*    - mUiPrintStrN -- Print up to N characters of a null-terminated string
*    - mUiPutc -- Print a single character and advance the cursor horizontally
*
* and additional convenience macros:
*
*    - mUiPrintLit -- Print a literal string
*    - mUiPrint -- Print multiple items
*    - mUiGotoRC -- Designate the screen position for the next print operation
*    - mUiGotoR -- Designate the screen row for the next print operation
*    - mUiGotoC -- Designate the screen column for the next print operation


* ui_base Macros --------------------------------


    ; mUiInvertBox -- Invert a rectangle of characters
    ; Args:
    ;   \1: w. Top-left corner of the rectangle, in rows
    ;   \2: w. Top-left corner of the rectangle, in columns
    ;   \3: w. Height of the rectangle, in rows
    ;   \4: w. Width of the rectangle, in columns
    ; Notes:
    ;   Boxes that overlap screen boundaries cause undefined behaviour
    ;   Pushes items onto the stack while processing arguments
    ;   Trashes D0-D1/A0-A1
mUiInvertBox  MACRO
      MOVE.W  \4,-(SP)
      MOVE.W  \3,-(SP)
      MOVE.W  \2,-(SP)
      MOVE.W  \1,-(SP)
      BSR     UiInvertBox
      ADDQ.L  #$8,SP               ; Pop arguments off of the stack
            ENDM


    ; mUiClearBox -- Clear a rectangle of characters
    ; Args:
    ;   \1: w. Top-left corner of the rectangle, in rows
    ;   \2: w. Top-left corner of the rectangle, in columns
    ;   \3: w. Height of the rectangle, in rows
    ;   \4: w. Width of the rectangle, in columns
    ; Notes:
    ;   Boxes that overlap screen boundaries cause undefined behaviour
    ;   Pushes items onto the stack while processing arguments
    ;   Trashes D0-D1/A0-A1
mUiClearBox   MACRO
      MOVE.W  \4,-(SP)
      MOVE.W  \3,-(SP)
      MOVE.W  \2,-(SP)
      MOVE.W  \1,-(SP)
      BSR     UiClearBox
      ADDQ.L  #$8,SP               ; Pop arguments off of the stack
            ENDM


    ; mUiScrollBox -- Scroll vertically within a rectangle of characters
    ; Args:
    ;   \1: w. Top-left corner of the rectangle, in rows
    ;   \2: w. Top-left corner of the rectangle, in columns
    ;   \3: w. Height of the rectangle, in rows
    ;   \4: w. Width of the rectangle, in columns
    ;   \5: w. Number of rows to scroll; can be negative
    ; Notes:
    ;   Region that new text would scroll into is left blank
    ;   Boxes that overlap screen boundaries cause undefined behaviour
    ;   Scrolling more rows than the box contains causes undefined behaviour
    ;   Pushes items onto the stack while processing arguments
    ;   Trashes D0-D1/A0-A1
mUiScrollBox  MACRO
      MOVE.W  \5,-(SP)
      MOVE.W  \4,-(SP)
      MOVE.W  \3,-(SP)
      MOVE.W  \2,-(SP)
      MOVE.W  \1,-(SP)
      BSR     UiScrollBox
      ADDA.W  #$A,SP               ; Pop arguments off of the stack
            ENDM


    ; mUiShiftLine -- Horizontal shift part of a character line
    ; Args:
    ;   \1: w. Which row to apply the shift to
    ;   \2: w. Leftmost column of the shift region
    ;   \3: w. Number of columns to shift
    ;   \4: w. Width of the shift region
    ; Notes:
    ;   Region that new text would scroll into is left blank
    ;   Lines that extend beyond screen boundaries cause undefined behaviour
    ;   Shifting more columns than the region holds causes undefined behaviour
    ;   Pushes items onto the stack while processing arguments
    ;   Trashes D0-D1/A0-A1
mUiShiftLine  MACRO
      MOVE.W  \4,-(SP)
      MOVE.W  \3,-(SP)
      MOVE.W  \2,-(SP)
      MOVE.W  \1,-(SP)
      BSR     UiShiftLine
      ADDQ.L  #$8,SP               ; Pop arguments off of the stack
            ENDM


    ; mUiPrintStr -- Print a null-terminated string
    ; Args:
    ;   \1: l. Address of a null-terminated string to print
    ; Notes:
    ;   Notes for Print\1 of lisa_console_screen.x68 apply here as well
    ;   Trashes D0-D1/A0-A1
mUiPrintStr   MACRO
      MOVE.L  \1,-(SP)
      BSR     UiPrintStr
      ADDQ.L  #$4,SP               ; Pop argument off of the stack
            ENDM


    ; mUiPrintStrN -- Print up to N characters of a null-terminated string
    ; Args:
    ;   \1: w. Maximum number of characters to print
    ;   \2: l. Address of a null-terminated string to print
    ; Notes:
    ;   Notes for Print\1 of lisa_console_screen.x68 apply here as well
    ;   Modifies the string to print (temporarily) --- not thread safe!
    ;   Trashes D0-D1/A0-A1
mUiPrintStrN  MACRO
      MOVE.L  \2,-(SP)
      MOVE.W  \1,-(SP)
      BSR     UiPrintStrN
      ADDQ.L  #$6,SP               ; Pop arguments off of the stack
            ENDM


    ; mUiPutc -- Print a single character and advance the cursor horizontally
    ; Args:
    ;   \1: b. Character to print
    ; Notes:
    ;   Notes for Putc\1 of lisa_console_screen.x68 apply here as well
    ;   DOES NOT ADVANCE TO THE NEXT LINE IF A NEWLINE CHARACTER IS ENCOUNTERED
    ;   DOES NOT ADVANCE TO THE NEXT LINE IF THE CURSOR IS AT THE LAST COLUMN
    ;   Trashes A0-A1/D0-D1
mUiPutc     MACRO
      MOVE.B  \1,-(SP)
      BSR     UiPutc
      ADDQ.L  #$2,SP               ; Pop arguments off of the stack
            ENDM


    ; mUiPrintLit -- Print a literal string
    ; Args:
    ;   \1: Literal string to print
    ; Notes:
    ;   Notes for Print\1 of lisa_console_screen.x68 apply here as well
    ;   The literal is embedded in the code at the site of macro invocation
    ;   Trashes D0-D1/A0-A1
mUiPrintLit   MACRO
      BRA.S   .p\@                 ; Jump past string constant
.s\@  DC.B    \1,$00               ; Null-terminated string literal
      DS.W    0                    ; Force even word alignment
.p\@  PEA.L   .s\@(PC)             ; Push string literal address onto the stack
      BSR     UiPrintStr           ; Print the string literal
      ADDQ.L  #$4,SP               ; Pop argument off of the stack
            ENDM


    ; mUiGotoRC -- Designate the screen position for the next print operation
    ; Args:
    ;   \1: w. Row for the next print operation
    ;   \2: w. Column for the next print operation (cannot be D1)
    ; Notes:
    ;   Out-of-bounds screen positions cause undefined behaviour
    ;   Trashes D0-D1
mUiGotoRC   MACRO
              IFC '\2','D1'
              FAIL Second argument to mUiGotoRC cannot be D1
              ENDC
              IFNC '\1','D1'
      MOVE.W  \1,D1
              ENDC
              IFNC '\2','D0'
      MOVE.W  \2,D0
              ENDC
      BSR     GotoXYLisaConsole
            ENDM


    ; mUiGotoR -- Designate the screen row for the next print operation
    ; Args:
    ;   \1: w. Row for the next print operation
    ; Notes:
    ;   Out-of-bounds screen rows cause undefined behaviour
    ;   Trashes D0
mUiGotoR    MACRO
              IFNC '\1','D0'
      MOVE.W  \1,D0
              ENDC
      BSR     GotoYLisaConsole
            ENDM


    ; mUiGotoC -- Designate the screen column for the next print operation
    ; Args:
    ;   \1: w. Column for the next print operation
    ; Notes:
    ;   Out-of-bounds screen columns cause undefined behaviour
    ;   Trashes D0
mUiGotoC    MACRO
              IFNC '\1','D0'
      MOVE.W  \1,D0
              ENDC
      BSR     GotoXLisaConsole
            ENDM


    ; mUiPrintX -- Perform a variety of print operations
    ; Args:
    ;   \1: What to print (see notes)
    ; Notes:
    ;   Notes for Print\1 of lisa_console_screen.x68 apply here as well
    ;   \1 can be any of the following:
    ;      - <'A literal string'> - print this string
    ;      - s - pop an address and print the null-terminated string there
    ;      - r1c0 - the next print operation will start at row 1, column 0
    ;      - r1c1 - the next print operation will start at row 1, column 1
    ;      - r1c2 - the next print operation will start at row 1, column 2
    ;      - c3 - the next print operation will start at column 3
    ;   Some arguments, but not all, can trash D0-D1/A0-A1
mUiPrintX   MACRO
              IFC <'\1'>,<'s'>
      BSR     UiPrintStr           ; Print a string at an address on the stack
      ADDQ.L  #$4,SP               ; Pop address off of the stack
              ENDC
              IFC <'\1'>,<'r1c0'>
      mUiGotoRC #$1,#$0            ; Next print operation at row 1, column 0
              ENDC
              IFC <'\1'>,<'r1c1'>
      mUiGotoRC #$1,#$1            ; Next print operation at row 1, column 1
              ENDC
              IFC <'\1'>,<'r1c2'>
      mUiGotoRC #$1,#$2            ; Next print operation at row 1, column 2
              ENDC
              IFC <'\1'>,<'c3'>
      mUiGotoC  #$3                ; Next print operation at column 3
              ENDC

              IFNC <'\1'>,<'s'>    ; A proper else clause would be nice...
              IFNC <'\1'>,<'r1c0'>
              IFNC <'\1'>,<'r1c1'>
              IFNC <'\1'>,<'r1c2'>
              IFNC <'\1'>,<'c3'>
      mUiPrintLit <\1>             ; Print a literal string
              ENDC
              ENDC
              ENDC
              ENDC
              ENDC
            ENDM


    ; mUiPrint -- Print multiple items
    ; Args:
    ;   \1 and optionally up to \9: What to print (see notes)
    ; Notes:
    ;   Notes for Print\1 of lisa_console_screen.x68 apply here as well
    ;   See argument notes for mUiPrintX for what \1 can be
    ;   Some arguments, but not all, can trash D0-D1/A0-A1
mUiPrint    MACRO
              IFARG 1
      mUiPrintX   <\1>
              ENDC
              IFARG 2
      mUiPrintX   <\2>
              ENDC
              IFARG 3
      mUiPrintX   <\3>
              ENDC
              IFARG 4
      mUiPrintX   <\4>
              ENDC
              IFARG 5
      mUiPrintX   <\5>
              ENDC
              IFARG 6
      mUiPrintX   <\6>
              ENDC
              IFARG 7
      mUiPrintX   <\7>
              ENDC
              IFARG 8
      mUiPrintX   <\8>
              ENDC
              IFARG 9
      mUiPrintX   <\9>
              ENDC
            ENDM
