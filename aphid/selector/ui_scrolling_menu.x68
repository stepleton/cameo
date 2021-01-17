* Cameo/Aphid disk image selector: Vertically-scrolling menu
* ==========================================================
*
* Forfeited into the public domain with NO WARRANTY. Read LICENSE for details.
*
* Routines for implementing vertically-scrolling menus of items; that is, user
* interface widgets akin to <select multiple> form fields in HTML, except only
* one selection is ever possible.
*
* Code that INCLUDEs this file must have defined `kSecCode` as a section symbol,
* ideally for the section containing the rest of the application code.
*
* These procedures make use of the `lisa_console_kbmouse.x68` and
* `lisa_console_screen.x68` components from the `lisa_io` library. Before using
* any routine defined below, both of those components must have been initialised
* via the `InitLisaConsoleKbMouse` and `InitLisaConsoleScreen` procedures.
*
* The UiScrollingMenu routines have a vaguely "obejct oriented" design, taking
* as their only caller-supplied argument a "UiScrollingMenu record" -- a 22-byte
* data structure. In typical applications, the caller will:
*
*    1. use `UiScrollingMenuInit` to initialise a memory region with a 22-byte
*       UiScrollingMenu record; various parameters in this header will be set
*       to "sensible" default settings,
*    2. customise the parameters in the record header to fit their application,
*       most notably by providing the address of a callback that prints lines
*       of the menu (more below),
*    3. call `UiScrollingMenuShow` to show the entire menu for the first time,
*    4. set up a loop that collects input from the user, then call
*       `UiScrollingMenuUp` or `UiScrollingMenuDown` when the user wishes to
*       move to the previous or next menu item.
*
* Public procedures:
*    - UiScrollingMenuInit -- Initialise a UiScrollingMenu record
*    - UiScrollingMenuShow -- Display a scrolling menu widget "from scratch"
*    - UiScrollingMenuUp -- Move the current selection up
*    - UiScrollingMenuDown -- Move the current selection down


* ui_scrolling_menu Defines ---------------------


    ; UiScrollingMenu record definition
    ;
    ; All public functions in this library take the address of a UiScrollingMenu
    ; record as an argument. These records are a 22-byte data structure that
    ; contains the parameters and state of a UiScrollingMenu field.
    ;
    ; At offset $10, code that calls `UiScrollingMenuShow`, `UiScrollingMenuUp`,
    ; or `UiScrollingMenuDown` must supply the address of a callback procedure
    ; that prints the complete text of a menu option using the `mUiPrint` macro
    ; from `ui_macros.x68`. When called, its lone stack argument will be the
    ; address of the menu's UiScrollingMenu record, where offset $14 contains
    ; the index of the menu item that the callback should print.
    ;
    ; The callback can assume that whatever it prints will start at the first
    ; column of the correct menu row---in other words, no positioning is
    ; necessary, and in fact will mess up the display. The callback should also
    ; not print any newlines. Finally, callbacks should preserve all registers
    ; except D0-D1/A0-A1.
    ;
    ; Code that customises the geometric parameters within a UiScrollingMenu
    ; record must take care not to extend the field past the edge of the
    ; screen, nor to introduce geometric nonsense that imposes impossible
    ; constraints on the field layout (prefixes that overlap suffixes,
    ; too-large margins, and so on).
    ;
    ; A UiScrollingMenu record must be word-aligned.
    ;
    ; The following symbols give names to byte offsets within UiScrollingMenu
    ; records:

kUISM_Top   EQU  $0              ; w. First row of the menu; always < 36
kUISM_Left  EQU  $2              ; w. Leftmost column of the menu; always < 90
kUISM_Rows  EQU  $4              ; w. Height of the menu; always < (36 - Top)
kUISM_Cols  EQU  $6              ; w. Width of the menu; always < (90 - Left)
kUISM_Marg  EQU  $8              ; w. Menu scroll margins; always >= 0

kUISM_Len   EQU  $A              ; w. Number of menu items

kUISM_CPos  EQU  $C              ; w. Cursor position; always in [0, Len)
kUISM_SPos  EQU  $E              ; w. Scroll position; always in [0, CPos)

kUISM_PItem EQU  $10             ; l. Address of item-printing callback
kUISM_PIArg EQU  $14             ; w. Argument for PItem


* ui_scrolling_menu Code ------------------------


    SECTION kSecCode


    ; UiScrollingMenuInit -- Initialise a UiScrollingMenu record
    ; Args:
    ;   SP+$4: Address of UiScrollingMenu record to init; must be word-aligned
    ; Notes:
    ;   "Trashes" A0 (by leaving the argument address there)
UiScrollingMenuInit:
    MOVEA.L $4(SP),A0            ; Copy record address to A0

    MOVE.W  #$5,kUISM_Top(A0)    ; The menu begins on row 5...
    MOVE.W  #$3,kUISM_Left(A0)   ; ...and extends from column 3
    MOVE.W  #$1C,kUISM_Rows(A0)  ; It has 28 rows...
    MOVE.W  #$54,kUISM_Cols(A0)  ; ...and 84 columns
    MOVE.W  #$5,kUISM_Marg(A0)   ; Our scroll margins are a generous five items

    CLR.W   kUISM_Len(A0)        ; Nothing in the menu by default
    CLR.W   kUISM_CPos(A0)       ; Cursor position starts at 0
    CLR.W   kUISM_SPos(A0)       ; Scroll position starts at 0

    CLR.L   kUISM_PItem(A0)      ; The callback holds a null pointer for now
    CLR.W   kUISM_PIArg(A0)      ; And the argument is likewise zero

    RTS


    ; UiScrollingMenuShow -- Display a scrolling menu widget "from scratch"
    ; Args:
    ;   SP+$4: Address of UiScrollingMenu record; must be word-aligned
    ; Notes:
    ;   Trashes D0-D1/A0-A1
UiScrollingMenuShow:
    MOVEA.L $4(SP),A0            ; Copy record address to A0
    MOVE.L  A0,-(SP)             ; Push it back onto the stack
    MOVE.W  kUISM_Rows(A0),-(SP)   ; Draw the entire height of the menu
    MOVE.W  #$0,-(SP)            ; Starting from its first row
    BSR     _UISM_DrawRows       ; Call our menu row drawing function
    ADDQ.L  #$4,SP               ; Pop some args, but leave record address

    BSR     _UISM_Hilite         ; Highlight the current selected row

    ADDQ.L  #$4,SP               ; Pop record address off the stack
    RTS


    ; UiScrollingMenuUp -- Move the current selection up
    ; Args:
    ;   SP+$4: Address of UiScrollingMenu record; must be word-aligned
    ; Notes:
    ;   Z will be clear if and only if the current selection moved up
    ;   Trashes D0-D1/A0-A1
UiScrollingMenuUp:
    MOVEA.L $4(SP),A0            ; Copy record address to A0
    BSR     _UISMM_UpOk          ; Is it safe to move the cursor up?
    BNE.S   .ok                  ; If so, skip ahead to do it
    RTS                          ; Otherwise, return to the caller

    ; Do preparatory things we have to do no matter how we move upward
.ok MOVE.L  A0,-(SP)             ; Push record address onto the stack
    BSR     _UISM_Hilite         ; Clear any highlighted menu item
    MOVEA.L (SP),A0              ; Copy record address to A0 again
    SUBQ.W  #$1,kUISM_CPos(A0)   ; Move the current selection up
    BSR     _UISMD_UShiftD       ; How should we update the display?
    BEQ.S   .mu                  ; Jump ahead if only the cursor should move

    ; If here, then the cursor stays put as the menu scrolls
    SUBQ.W  #$1,kUISM_SPos(A0)   ; Scroll the menu contents up one item
    MOVE.W  #-1,-(SP)            ; Push scroll direction onto the stack
    BSR     _UISM_Scroll         ; Jump to scroll the menu one line
    ADDQ.L  #$2,SP               ; Pop those arguments off the stack
    MOVEA.L (SP),A0              ; Restore the record address to A0

    ; Do finishing things we have to do no matter how we move upward
.mu BSR     _UISM_Hilite         ; Highlight the new current menu item
    ADDQ.L  #$4,SP               ; Pop record address off of the stack
    ANDI.B  #$FB,CCR             ; Moving up was successful; clear Z!
    RTS


    ; UiScrollingMenuDown -- Move the current selection down
    ; Args:
    ;   SP+$4: Address of UiScrollingMenu record; must be word-aligned
    ; Notes:
    ;   Z will be clear if and only if the current selection moved down
    ;   Trashes D0-D1/A0-A1
UiScrollingMenuDown:
    MOVEA.L $4(SP),A0            ; Copy record address to A0
    BSR     _UISMM_DownOk        ; Is it safe to move the cursor down?
    BNE.S   .ok                  ; If so, skip ahead to do it
    RTS                          ; Otherwise, return to the caller

    ; Do preparatory things we have to do no matter how we move downward
.ok MOVE.L  A0,-(SP)             ; Push record address onto the stack
    BSR     _UISM_Hilite         ; Clear any highlighted menu item
    MOVEA.L (SP),A0              ; Copy record address to A0 again
    ADDQ.W  #$1,kUISM_CPos(A0)   ; Move the current selection down
    BSR     _UISMD_DShiftU       ; How should we update the display?
    BEQ.S   .mu                  ; Jump ahead if only the cursor should move

    ; If here, then the cursor stays put as the menu scrolls
    ADDQ.W  #$1,kUISM_SPos(A0)   ; Scroll the menu contents down one item
    MOVE.W  #1,-(SP)             ; Push scroll direction onto the stack
    BSR     _UISM_Scroll         ; Jump to scroll the menu one line
    ADDQ.L  #$2,SP               ; Pop scroll direction off the stack
    MOVEA.L (SP),A0              ; Restore the record address to A0

    ; Do finishing things we have to do no matter how we move downward
.mu BSR     _UISM_Hilite         ; Highlight the new current menu item
    ADDQ.L  #$4,SP               ; Pop record address off of the stack
    ANDI.B  #$FB,CCR             ; Moving down was successful; clear Z!
    RTS


    ; _UISM_DrawRows -- Redraw some rows of the scrolling menu widget
    ; Args:
    ;   SP+$4: w. Which row of the widget is the first to be redrawn?
    ;   SP+$6: w. How many rows to redraw, starting from that row
    ;   SP+$8: Address of the UiScrollingMenu record; must be word-aligned
    ; Notes:
    ;   Rows must be valid rows of the widget to avoid undefined results
    ;   Trashes D0-D1/A0-A1
_UISM_DrawRows:
    MOVEA.L $8(SP),A0            ; Copy record address to A0

    ; First, blank the area occupied by the rows we'll redraw
    MOVE.W  kUISM_Top(A0),D0     ; Copy first row of the menu to D0
    ADD.W   $4(SP),D0            ; Add first row to redraw
    MOVE.W  $6(SP),D1            ; Copy number of rows to redraw to D1
    MOVE.W  D0,-(SP)             ; Save first row, since mUiClearBox clobbers it
    mUiClearBox   D0,kUISM_Left(A0),D1,kUISM_Cols(A0)  ; Clear the area
    MOVE.W  (SP)+,D0             ; Restore first row from stack

    ; Move the cursor to the first row we'll redraw
    MOVEA.L $8(SP),A0            ; Restore record address to A0
    mUiGotoRC   D0,kUISM_Left(A0)  ; Move the cursor

    ; Determine which menu item is the first menu item to redraw 
    MOVE.W  kUISM_SPos(A0),D0    ; Copy scroll pos (row at top of widget) to D0
    ADD.W   $4(SP),D0            ; Add first row to redraw

    ; Redraw the rows in the designated area
    MOVE.W  $6(SP),D1            ; Copy number of rows to redraw to D1
    SUBQ.W  #$1,D1               ; Subtract 1 for loop iteration
    MOVEM.L D2-D3/A2,-(SP)       ; Save registers we'll use for looping
    MOVE.L  D0,D2                ; Copy set-up working registers to new places
    MOVE.L  D1,D3
    MOVEA.L A0,A2

    MOVE.L  A2,-(SP)             ; Push record address onto the stack
.lp CMP.W   kUISM_Len(A2),D2     ; Are there no more items left in the menu?
    BGE.S   .rt                  ; If so, stop here
    MOVE.W  D2,kUISM_PIArg(A2)   ; Copy menu item index to PItem callback arg
    MOVE.L  kUISM_PItem(A2),A0   ; Point A0 to the menu item printing callback
    JSR     (A0)                 ; Call the callback
    ADDQ.W  #$1,zRowLisaConsole  ; Move cursor to the next row (TODO: macro?)
    mUiGotoC  kUISM_Left(A2)     ; Move cursor to left menu column
    ADDQ.W  #$1,D2               ; Increment menu item index
    DBRA    D3,.lp               ; Loop to print the next row

.rt ADDQ.W  #$4,SP               ; Pop record address off the stack
    MOVEM.L (SP)+,D2-D3/A2       ; Restore registers we used for looping
    RTS


    ; _UISM_Hilite -- Highlight the current selected menu row
    ; Args:
    ;   SP+$4: Address of UiScrollingMenu record; must be word-aligned
    ; Notes:
    ;   Inverts all of the pixels on the menu row, so can also "unhighlight"
    ;   Trashes D0-D1/A0-A1
_UISM_Hilite:
    MOVEA.L $4(SP),A0            ; Copy record address to A0

    ; Check whether the selected row is visible now; should be, but even so
    MOVE.W  kUISM_CPos(A0),D0    ; Move cursor position (highlighted row) to D0
    MOVE.W  kUISM_SPos(A0),D1    ; Move scroll position to D1
    CMP.W   D1,D0                ; Is the cursor above the top of the menu?
    BLO.S   .rt                  ; If so, jump ahead and quit
    ADD.W   kUISM_Rows(A0),D1    ; Add number of rows to scroll position
    CMP.W   D1,D0                ; Is the cursor below the bottom of the menu?
    BHS.S   .rt                  ; If so, jump ahead and quit

    ; Determine the rectangle to highlight and highlight it
    SUB.W   kUISM_SPos(A0),D0    ; Subtract scroll position from cursor position
    ADD.W   kUISM_Top(A0),D0     ; Add menu top; this is the row
    mUiInvertBox  D0,kUISM_Left(A0),#$1,kUISM_Cols(A0)   ; Invert the row

.rt RTS


    ; _UISM_Scroll -- Scroll the menu up or down one line
    ; Args:
    ;   SP+$4: w. Direction to scroll; postitive for down, negative for up
    ;   SP+$6: Address of UiScrollingMenu record; must be word-aligned
    ; Notes:
    ;   Un-highlight any highlighted row prior to calling
    ;   Does not update the scroll position at kUISM_SPos; do it yourself
    ;   Trashes D0-D1/A0-A1
_UISM_Scroll:
    MOVEA.L $6(SP),A0            ; Copy record address to A0
    TST.W   $4(SP)               ; What direction should we scroll?
    BMI.S   .up                  ; Negative number: scroll up
    BGT.S   .dn                  ; Positive number: scroll down
    RTS                          ; Zero: just return to caller

    ; Scrolling up - the first line scrolls much of the text
.up mUiScrollBox kUISM_Top(A0),kUISM_Left(A0),kUISM_Rows(A0),kUISM_Cols(A0),#-1
    MOVEA.L $6(SP),A0            ; Copy record address to A0 again
    MOVE.L  A0,-(SP)             ; Push record address onto the stack
    MOVE.W  #$1,-(SP)            ; We will redraw only one row
    MOVE.W  #$0,-(SP)            ; We will redraw the first row of the menu
    BRA.S   .dr                  ; Draw the newly revealed row

    ; Scrolling down - the first line scrolls much of the text
.dn mUiScrollBox kUISM_Top(A0),kUISM_Left(A0),kUISM_Rows(A0),kUISM_Cols(A0),#1
    MOVEA.L $6(SP),A0            ; Copy record address to A0 again
    MOVE.L  A0,-(SP)             ; Push record address onto the stack
    MOVE.W  #$1,-(SP)            ; We will redraw only one row
    MOVE.W  kUISM_Rows(A0),D0    ; Copy number of menu rows to D0, and...
    SUBQ.W  #$1,D0               ; ...one less is the row we will redraw
    MOVE.W  D0,-(SP)             ; Push that onto the stack

    ; Draw the newly revealed row
.dr BSR     _UISM_DrawRows       ; Draw the row cleared by the scrolling
    ADDQ.L  #$8,SP               ; Pop its arguments off the stack
    RTS


    ; _UISMM_UpOk -- Movement check: OK to move current selection up?
    ; Args:
    ;   A0: Address of UiScrollingMenu record; must be word-aligned
    ; Notes:
    ;   Z will be clear if and only if it is OK to move the selection up
    ;   Does not alter registers
_UISMM_UpOk:
    TST.W   kUISM_CPos(A0)       ; Is the cursor at or before(?) item 0?
    BLE.S   .no                  ; If so, moving up is not OK

    ANDI.B  #$FB,CCR             ; Check passed; moving up is OK; clear Z!
    RTS

.no ORI.B   #$04,CCR             ; Moving up is not OK; set Z flag
    RTS


    ; _UISMM_UpOk -- Movement check: OK to move current selection down?
    ; Args:
    ;   A0: Address of UiScrollingMenu record; must be word-aligned
    ; Notes:
    ;   Z will be clear if and only if it is OK to move the selection down
    ;   Trashes D0
_UISMM_DownOk:
    MOVE.W  kUISM_CPos(A0),D0    ; Copy current selection to D0
    ADDQ.W  #$1,D0               ; Add 1 to simulate moving forward
    CMP.W   kUISM_Len(A0),D0     ; Would we be past the last item?
    BGE.S   .no                  ; If so, moving down is not OK

    ANDI.B  #$FB,CCR             ; Check passed; moving down is OK; clear Z!
    RTS

.no ORI.B   #$04,CCR             ; Moving down is not OK; set Z flag
    RTS


    ; _UISMD_UShiftD -- Display check: how to update display after "move up"?
    ; Args:
    ;   A0: Address of UiScrollingMenu record; must be word-aligned
    ; Notes:
    ;   Z will be clear if cursor should stay put and menu items shifted down
    ;   Z will be set if only the cursor should move
    ;   Trashes D0-D1
_UISMD_UShiftD:
    MOVE.W  kUISM_SPos(A0),D1    ; Put scroll position in D1; is it 0?
    BLE.S   .no                  ; If so, only the cursor moves
    MOVE.W  kUISM_CPos(A0),D0    ; Put cursor position in D0, then subtract...
    SUB.W   D1,D0                ; ...scroll pos to get position in the menu
    CMP.W   kUISM_Marg(A0),D0    ; Is the cursor on or past the margin?
    BGE.S   .no                  ; If so, only the cursor moves

    ANDI.B  #$FB,CCR             ; Check passed; shift items down; clear Z!
    RTS

.no ORI.B   #$04,CCR             ; Check failed; only the cursor moves; set Z
    RTS


    ; _UISMD_DShiftU -- Display check: how to update display after "move down"?
    ; Args:
    ;   A0: Address of UiScrollingMenu record; must be word-aligned
    ; Notes:
    ;   Z will be clear if cursor should stay put and menu items shifted up
    ;   Z will be set if only the cursor should move
    ;   Trashes D0-D1
_UISMD_DShiftU:
    MOVE.W  kUISM_Len(A0),D1     ; Current length into D1, then subtract...
    SUB.W   kUISM_SPos(A0),D1    ; ...scroll pos to get rows past top of menu
    MOVE.W  kUISM_Rows(A0),D0    ; Copy menu height to D0
    CMP.W   D0,D1                ; Is the last menu item visible?
    BLE.S   .no                  ; If so, only the cursor moves

    MOVE.W  kUISM_Marg(A0),D1    ; Copy menu scroll margin to D1
    SUB.W   D1,D0                ; Subtract margin from menu height
    MOVE.W  kUISM_CPos(A0),D1    ; Put cursor position in D1, then subtract...
    SUB.W   kUISM_SPos(A0),D1    ; ...scroll pos to get position in menu
    CMP.W   D1,D0                ; Is cursor at or beyond the margin?
    BGT.S   .no                  ; If not, only the cursor moves

    ANDI.B  #$FB,CCR             ; Check passed; shift items up; clear Z!
    RTS

.no ORI.B   #$04,CCR             ; Check failed; only the cursor moves; set Z
    RTS
