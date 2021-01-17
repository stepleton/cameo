* Cameo/Aphid disk image selector: Text input fields
* ==================================================
*
* Forfeited into the public domain with NO WARRANTY. Read LICENSE for details.
*
* Routines for implementing text input fields; that is, user interface widgets
* akin to <input type="text"> form fields in HTML.
*
* Code that INCLUDEs this file must have defined `kSecCode` as a section symbol,
* ideally for the section containing the rest of the application code.
*
* These procedures make use of the `lisa_console_kbmouse.x68` and
* `lisa_console_screen.x68` components from the `lisa_io` library. Before using
* any routine defined below, both of those components must have been initialised
* via the `InitLisaConsoleKbMouse` and `InitLisaConsoleScreen` procedures.
*
* The UiTextInput routines have a vaguely "obejct oriented" design, taking as
* their only caller-supplied argument a "UiTextInput record" -- a 16-byte
* header followed by the string being edited by the text input field. In
* typical applications, the caller will:
*
*    1. use `UiTextInputInit` to initialise a memory region with a 16-byte
*       UiTextInput record header; various parameters in this header will
*       be set to "sensible" default settings,
*    2. customise the parameters in the record header to fit their application,
*    3. call `UiTextInput` and receive control again once the user has finished
*       editing the text.
*
* Public procedures:
*    - UiTextInputInit -- Initialise a UiTextInput record header
*    - UiTextInput -- Display then gather input from a UiTextInput widget
*    - UiTextInputShow -- Display a UiTextInput widget "from scratch"
*    - UiTextInputUpdate -- Update the TextInput after a keypress (or not)
*    - UiTextInputHideCursor -- Hide the cursor if it is showing


* ui_textinput Defines --------------------------


    ; UiTextInput record definition
    ;
    ; All public procedures in this library take the address of a UiTextInput
    ; record as an argument. These records are a 16-byte header that contains
    ; the parameters and state of a UiTextInput text input field, followed by
    ; the text being edited by that field, which can be of variable length. This
    ; text MUST be null-terminated.
    ;
    ; Note that the the two string length fields kUITI_Len and kUITI_Max do NOT
    ; count the null terminator.
    ;
    ; Code that customises the geometric parameters within a UiTextInput record
    ; must take care not to extend the field past the edge of the screen, nor
    ; to introduce geometric nonsense that imposes impossible constraints on
    ; the field layout (prefixes that overlap suffixes, too-large margins, and
    ; so on).
    ;
    ; A UiTextInput record must be word-aligned.
    ;
    ; The following symbols give names to byte offsets within UiTextInput
    ; records:

kUITI_Start EQU  $0              ; b. Textinput starting column; always < 90
kUITI_Width EQU  $1              ; b. Textinput width; always < (90 - Start)
kUITI_Marg  EQU  $2              ; b. Textinput scroll margins; always >= 0

kUITI_Resv  EQU  $3              ; b. Reserved for internal state

kUITI_PLen  EQU  $4              ; w. Prefix len; always in [0, Len-SLen]
kUITI_SLen  EQU  $6              ; w. Suffix len; always in [0, Len-PLen]
kUITI_Max   EQU  $8              ; w. Maximum text length (without terminator)

kUITI_CPos  EQU  $A              ; w. Cursor position; always in [0, Len]
kUITI_SPos  EQU  $C              ; w. Scroll position; always in [0, CPos]
kUITI_Len   EQU  $E              ; w. Text length; always >= (PLen+SLen)
kUITI_Text  EQU  $10             ; w. Offset to the text being edited itself


* ui_textinput Code -----------------------------


    SECTION kSecCode


    ; UiTextInputInit -- Initialise a UiTextInput record header
    ; Args:
    ;   SP+$4: Address of UiTextInput record to initialise; must be word-aligned
    ; Notes:
    ;   The default configuration for a UiTextInput record is as follows:
    ;       - Starts at column 0, 89 characters wide
    ;       - 4-character scrolling margin, no prefix, no suffix
    ;       - Max length is 511 characters (plus one terminating NUL)
    ;       - Cursor input position and scroll position are both 0
    ;       - The initial text has length 0
    ;   Does NOT place a terminating NUL immediately following the data
    ;       structure; you must do this if you wish to keep the text length
    ;       of 0, or null-terminate elsewhere if you prefer a different length
    ;   "Trashes" A0 (by leaving the argument address there)
UiTextInputInit:
    MOVEA.L $4(SP),A0            ; Copy record address to A0

    CLR.L   (A0)                 ; Most values we wish to set are 0, so...
    CLR.L   $4(A0)               ; ...clear the entire 16-byte record; then,...
    CLR.L   $8(A0)               ; ...set the nonzero values afterward:
    CLR.L   $C(A0)

    MOVE.B  #$59,kUITI_Width(A0)   ; Textinput is 89 characters wide...
    MOVE.B  #$04,kUITI_Marg(A0)  ; ...and has a 4-character scrolling margin

    MOVE.W  #$1FF,kUITI_Max(A0)  ; Text can be at most 511 chars, plus NUL

    RTS


    ; UiTextInput -- Display then gather input from a UiTextInput widget
    ; Args:
    ;   SP+$4: Address of a UiTextInput record; must be word-aligned
    ; Notes:
    ;   Displays the widget and manages all user interactions
    ;   Terminates when the user presses Clear (clears Z) or Return (sets Z)
    ;   Blinks the cursor whilst awaiting input
    ;   Trashes D0-D2/A0-A2
UiTextInput:
    MOVEA.L $4(SP),A0            ; Copy record address to A0
    MOVE.L  D3,-(SP)             ; Store D3 on the stack
    MOVE.L  A0,-(SP)             ; Store A0 on the stack
    BSR.S   UiTextInputShow      ; Show the UiTextInput widget

    ; The outer loop repeats the inner loop (giving us a sensible blinking
    ; frequency) and handles any keypresses occurring within the inner loop
.lo MOVEQ.L #$0,D3               ; Outer loop: repeat the inner loop once :-P

    ; The inner loop waits for keypresses
.li MOVE.W  #$BFFF,D2            ; Delay for LisaConsoleDelayForKbMouse
    BSR     LisaConsoleDelayForKbMouse  ; Pause a bit for keyboard input
    DBCS    D3,.li               ; No input at all? Repeat inner loop
    BCC.S   .bl                  ; Still no input? Just blink the cursor
    BNE.S   .li                  ; It wasn't keyboard input? Wait some more

    ; If here, then there was a keypress; figure out how to handle it
    CMPI.B  #$20,zLisaConsoleKbCode  ; Was it the clear key?
    BEQ.S   .cl                  ; If so, exit to clean up and return
    CMPI.B  #$48,zLisaConsoleKbCode  ; Was it the return key?
    BEQ.S   .cl                  ; If so, exit to clean up and return
    BRA.S   .up                  ; Neither; jump to update the widget

.bl CLR.B   zLisaConsoleKbCode   ; Prepare to blink by clearing the keycode
.up BSR     UiTextInputUpdate    ; Update the UiTextInput widget
    BRA.S   .lo                  ; Repeat the outer loop

    ; The user is done with the widget now
.cl BSR     UiTextInputHideCursor  ; Hide the cursor if it's still showing
    MOVE.L  (SP)+,A0             ; Recover A0 from the stack
    MOVE.L  (SP)+,D3             ; Recover D3 from the stack
    CMPI.B  #$48,zLisaConsoleKbCode  ; Set Z flag as described in docstring
    RTS


    ; UiTextInputShow -- Display a UiTextInput widget "from scratch"
    ; Args:
    ;   SP+$4: Address of a UiTextInput record; must be word-aligned
    ; Notes:
    ;   Trashes D0-D2/A0-A2
UiTextInputShow:
    MOVEA.L $4(SP),A0            ; Copy record address to A0
    MOVE.L  A2,-(SP)             ; Save old A2 value on the stack
    MOVEA.L A0,A2                ; Move record address to A2

    ; Move the text cursor to the starting point of the textinput and clear
    ; the area where the textinput will go
    MOVE.B  kUITI_Start(A2),D0   ; Copy the starting column of the textinput
    EXT.W   D0
    mUiGotoC  D0                 ; Move the "printing cursor" there
    MOVE.B  kUITI_Width(A2),D0   ; Copy the width of the textinput
    EXT.W   D0
    mUiClearBox   zRowLisaConsole,zColLisaConsole,#$1,D0   ; Clear the textinput
    BCLR.B  #$00,kUITI_Resv(A2)  ; Clear the "cursor blink" bit

    ; Find the address of the first character of visible text, then determine
    ; whether the text would extend past the end of the textinput
    LEA     kUITI_Text(A2),A0    ; Point A0 at the start of the text
    MOVE.W  kUITI_SPos(A2),D0    ; Copy index of first visible character to D0
    ADDA.W  D0,A0                ; Advance A0 to the first visible character
    MOVE.W  kUITI_Len(A2),D1     ; Copy text length to D1 and subtract index...
    SUB.W   D0,D1                ; ...of first visible char for text remaining
    MOVE.B  kUITI_Width(A2),D0   ; Copy textinput width to D0
    EXT.W   D0
    CMP.W   D0,D1                ; Would the text overflow the textinput?
    BLE.S   .jp                  ; No, go ahead and print it

    ; If here, the text would overflow the input, so before printing it,
    ; temporarily insert a NUL just before the first character that would
    ; overflow it, then print the result, then print an inverse-coloured
    ; ellipsis in the rightmost position
    MOVE.B  -1(A0,D0.W),-(SP)    ; Copy the last non-overflowing char to stack
    CLR.B   -1(A0,D0.W)          ; Replace first non-overflowing char with a NUL
    MOVEM.L A0/D0,-(SP)          ; Save A0 and D0 on the stack
    MOVE.L  A0,-(SP)             ; Put printable text addr on stack for mUiPrint
    mUiPrint  s,$03              ; Print the modified text and the ellipsis
    MOVEM.L (SP)+,A0/D0          ; Recover A0 and D0
    MOVE.B  (SP)+,-1(A0,D0.W)    ; Restore first non-overflowing char from stack
    BRA.S   .fe                  ; Jump ahead past the non-ellipsised print

    ; If here, the text won't overflow the textinput, so Just Print it
.jp MOVE.L  A0,-(SP)             ; Put printable text addr on stack for mUiPrint
    mUiPrint  s                  ; Print the non-overflowing text

    ; We also want to print an ellipsis at the beginning of the textinput if
    ; the first visible character isn't the first text character; while it might
    ; have been nice to do this "inline" as was done with the "overflow"
    ; ellipsis, this way is easier; finally, we leave the "printing cursor"
    ; at the beginning of the textinput
.fe MOVE.B  kUITI_Start(A2),D0   ; Copy the starting column of the textinput
    EXT.W   D0
    mUiGotoC  D0                 ; Move the "printing cursor" there
    TST.W   kUITI_SPos(A2)       ; Is first visible char the first text char?
    BEQ.S   .rt                  ; Yes, so jump ahead to return
    mUiPrint  $03                ; Print the inverse-coloured ellipsis char
    SUBQ.B  #$01,zColLisaConsole   ; Walk the print position back one char

.rt MOVE.L  (SP)+,A2             ; Restore A2 from stack
    RTS


    ; UiTextInputUpdate -- Update the TextInput after a keypress (or not)
    ; Args:
    ;   SP+$4: Address of a UiTextInput record; must be word-aligned
    ;   zLisaConsoleKbCode: Raw keycode of typed key, or 0 (see below)
    ;   zLisaConsoleKbChar: Interpreted ISO-8859-1 character for typed key
    ;   zLisaConsoleKbShift: Whether the shift key is down
    ; Notes:
    ;   Call with zLisaConsoleKbCode set to 0 to blink the cursor
    ;   Callers must detect Enter/Return keys for themselves
    ;   Trashes D0-D2/A0-A2
UiTextInputUpdate:
    MOVEA.L $4(SP),A0            ; Copy record address to A0
    TST.B   zLisaConsoleKbCode   ; Process a key or blink the cursor?
    BNE.S   .ub                  ; Jump if we're processing a key
    BRA     _UITI_InvertCursor   ; We're not; just blink the cursor and return

    ; We're processing a key; first, unblink the cursor if we think we need to
.ub MOVE.L  A0,-(SP)             ; Push record address onto the stack
    BSR     UiTextInputHideCursor  ; Unblink the cursor
    MOVEA.L (SP)+,A0             ; Restore record address to A0

    ; Which key has been pressed, and what do we do about it?
.pk MOVE.B  zLisaConsoleKbCode,D0  ; Copy keycode to D0 for speed
    CMP.B   #$20,D0              ; Clear key?
    BEQ.S   .rt                  ; Ignore it
    CMP.B   #$2F,D0              ; Keypad enter?
    BEQ.S   .rt                  ; Ignore it
    CMP.B   #$46,D0              ; Alphanumeric enter?
    BEQ.S   .rt                  ; Ignore it
    CMP.B   #$48,D0              ; Return key?
    BEQ.S   .rt                  ; Ignore it
    CMP.B   #$78,D0              ; Tab key?
    BEQ.S   .rt                  ; Ignore it

    ; If we're this far, we're going to invoke our helpers; each takes the
    ; address of the UiTextInput record as an argument on the stack
    MOVE.L  A0,-(SP)             ; Copy record adderss onto the stack

    CMP.B   #$22,D0              ; Is this the left arrow key?
    BNE.S   .ri                  ; No, keep looking...
    BSR     _UITI_Left           ; Yes, try to move the cursor left
    BRA.S   .wu                  ; Jump ahead to wrap up

.ri CMP.B   #$23,D0              ; Is this the right arrow key?
    BNE.S   .bs                  ; No, keep looking...
    BSR     _UITI_Right          ; Yes, try to move the cursor right
    BRA.S   .wu                  ; Jump ahead to wrap up

.bs CMP.B   #$45,D0              ; Is this the backspace key?
    BNE.S   .pp                  ; No, it's a printable char; process that
    TST.B   zLisaConsoleKbShift  ; Is the shift key down?
    BNE.S   .de                  ; Yes, jump ahead to delete current character
    BSR     _UITI_Backspace      ; No, delete preceding char (do a backspace)
    BRA.S   .wu                  ; Jump ahead to wrap up
.de BSR     _UITI_Delete         ; Delete current character
    BRA.S   .wu                  ; Jump ahead to wrap up

.pp MOVE.B  zLisaConsoleKbChar,-(SP)   ; Copy the char typed to the stack
    BSR     _UITI_Insert         ; Insert it into the text
    ADDQ.L  #$02,SP              ; Pop the char off of the stack; fall through

    ; Wrap-up: clean up the stack, blink the text field if the user did a bad
    ; thing, then restore the cursor to being "blinked on"
.wu ADDQ.L  #$04,SP              ; Pop the record address off of the stack
    BNE.S   .bl                  ; Keypress successful? Jump to reblink cursor

    MOVEA.L $4(SP),A0            ; Copy record address to A0 for warning blink
    BSR     _UITI_InvertTextInput  ; Blink the textinput box
    MOVE.W  #$7FFF,D0            ; Prepare delay loop iterator for the blink
.lp DBRA    D0,.lp               ; Loop so the blink soaks in
    MOVEA.L $4(SP),A0            ; Copy record address to A0 for warning unblink
    BSR     _UITI_InvertTextInput  ; Unblink the textinput box

.bl MOVEA.L $4(SP),A0            ; Copy record address to A0 for cursor reblink
    BSR.S   _UITI_InvertCursor   ; Reblink the cursor

.rt RTS


    ; UiTextInputHideCursor -- Hide the cursor if it is showing
    ; Args:
    ;   SP+$4: Address of a UiTextInput record; must be word-aligned
    ; Notes:
    ;   Trashes D0-D1/A0-A1
UiTextInputHideCursor:
    MOVEA.L $4(SP),A0            ; Place record address to A0
    BTST.B  #$00,kUITI_Resv(A0)  ; Is the cursor blinked (i.e. inverted)?
    BEQ.S   .rt                  ; No, jump to return
    BSR.S   _UITI_InvertCursor   ; Unblink the cursor
.rt RTS


    ; _UITI_InvertCursor -- Invert the character cell at the cursor location
    ; Args:
    ;   A0: Address of a UiTextInput record; must be word-aligned
    ; Notes:
    ;   Also inverts the LSBit in the record's reserved byte
    ;   Trashes D0-D1/A0-A1
_UITI_InvertCursor:
    EOR.B   #$01,kUITI_Resv(A0)  ; Invert the LSBit in the reserved byte
    MOVE.W  kUITI_CPos(A0),D0    ; Copy cursor position to D0
    SUB.W   kUITI_SPos(A0),D0    ; Subtract scroll pos for pos in text box
    BLT.S   .rt                  ; Cursor somehow left of text box? Do nothing
    CMP.B   kUITI_Width(A0),D0   ; Compare to text box width---yes, as a byte
    BGT.S   .rt                  ; Cursor somehow right of text box? Do nothing
    MOVE.B  kUITI_Start(A0),D1   ; Copy textinput starting column to D1
    EXT.W   D1
    ADD.W   D1,D0                ; Add to D0 for cursor screen position
    mUiInvertBox  zRowLisaConsole,D0,#$1,#$1   ; Invert that character cell
.rt RTS


    ; _UITI_InvertTextInput -- Invert the entire textinput box
    ; Args:
    ;   A0: Address of a UiTextInput record; must be word-aligned
    ; Notes:
    ;   Trashes D0-D1/A0-A1
_UITI_InvertTextInput:
    MOVE.B  kUITI_Start(A0),D0   ; Copy textinput starting column to D0
    EXT.W   D0
    MOVE.B  kUITI_Width(A0),D1   ; Copy textinput width to D1
    EXT.W   D1
    mUiInvertBox  zRowLisaConsole,D0,#$1,D1   ; Invert the textinput
    RTS


    ; _UITI_Insert -- Insert a character at the current cursor location
    ; Args:
    ;   SP+$6: Address of a UiTextInput record; must be word-aligned
    ;   SP+$4: b. Character to insert
    ; Notes:
    ;   Z will be clear if and only if the character was inserted
    ;   Trashes D0-D2/A0-A2
_UITI_Insert:
    MOVEA.L $6(SP),A0            ; Copy record address to A0
    BSR     _UITIE_InsertOk      ; Is it safe to insert a character?
    BNE.S   .ok                  ; If so, skip ahead to do it
    RTS                          ; Otherwise, return to the caller

    ; Move the string beyond the current location one character forward, making
    ; room at the current location for the new character; note that even if
    ; there are no chars to shift, we still shift the null terminator; then
    ; place the new character
.ok MOVE.W  kUITI_Len(A0),D0     ; Load string length into D0
    ADDQ.W  #$1,kUITI_Len(A0)    ; Now increase the string length by one char
    LEA.L   kUITI_Text(A0),A1    ; Load start of text to A1
    LEA.L   $1(A1,D0.W),A1       ; Point A1 just past string's null terminator
    SUB.W   kUITI_CPos(A0),D0    ; Subtract cursor pos from D0: chars to move
    ADDQ.W  #$1,kUITI_CPos(A0)   ; And advance the cursor position by one char
    LEA.L   $1(A1),A0            ; Point A0 /just past/ just past the terminator
.lp MOVE.B  -(A1),-(A0)          ;   Shift a char forward one step
    DBRA    D0,.lp               ;   Loop until done
    MOVE.B  $4(SP),(A1)          ; Now place the new character

    ; Update the display to show the new string
    MOVEA.L $6(SP),A0            ; Copy record address back to A0
    BSR     _UITID_InsShiftR     ; How do we update the display?
    BNE.S   .sh                  ; Text shifts right; scroll pos stays put
    ADDQ.W  #$1,kUITI_SPos(A0)   ; Text shifts left; cursor stays put

    ; Show the updated display ("Temporary"---replace with custom code)
.sh MOVE.L  A0,-(SP)             ; Copy record address onto the stack again
    BSR     UiTextInputShow      ; Call the text display code
    ADDQ.L  #$4,SP               ; Pop record address off the stack

    ANDI.B  #$FB,CCR             ; Insert was successful; clear Z!
    RTS


    ; _UITI_Backspace -- Remove a character to the left of the current location
    ; Args:
    ;   SP+$4: Address of a UiTextInput record; must be word-aligned
    ; Notes:
    ;   Z will be clear if and only if the character was deleted
    ;   Trashes D0-D2/A0-A2
_UITI_Backspace:
    MOVEA.L $4(SP),A0            ; Copy record address to A0
    BSR     _UITIE_BackspaceOk   ; Is it safe to backspace a character?
    BNE.S   .ok                  ; If so, skip ahead to do it
    RTS                          ; Otherwise, return to the caller

    ; Retract the string by one character just prior to the cursor position;
    ; note that we shift the null terminator as well
.ok SUBQ.W  #$1,kUITI_Len(A0)    ; Decrease the string length by one char
    MOVE.W  kUITI_CPos(A0),D0    ; Copy cursor pos to D0
    SUBQ.W  #$1,D0               ; Move it back one spot
    MOVE.W  D0,kUITI_CPos(A0)    ; Copy the new position to the record
    LEA.L   kUITI_Text(A0,D0.W),A1   ; Point A1 at the new cursor pos
    LEA.L   $1(A1),A0            ; Point A0 at the original cursor pos
.lp MOVE.B  (A0)+,(A1)+          ; Copy a character, and if it wasn't the...
    BNE.S   .lp                  ; ...terminator, loop to copy another

    ; Update the display to show the new string
    MOVEA.L $4(SP),A0            ; Copy record address back to A0
    BSR     _UITID_BksShiftL     ; How do we update the display?
    BNE.S   .sh                  ; Text shifts left; scroll pos stays put
    SUBQ.W  #$1,kUITI_SPos(A0)   ; Text shifts right; cursor stays put

    ; Show the updated display ("Temporary"---replace with custom code)
.sh MOVE.L  A0,-(SP)             ; Copy record address onto the stack again
    BSR     UiTextInputShow      ; Call the text display code
    ADDQ.L  #$4,SP               ; Pop record address off the stack

    ANDI.B  #$FB,CCR             ; Backspace was successful; clear Z!
    RTS


    ; _UITI_Delete -- Remove a character at the current location
    ; Args:
    ;   SP+$4: Address of a UiTextInput record; must be word-aligned
    ; Notes:
    ;   Z will be clear if and only if the character was deleted
    ;   Trashes D0-D2/A0-A2
_UITI_Delete:
    MOVEA.L $4(SP),A0            ; Copy record address to A0
    BSR     _UITIE_DeleteOk      ; Is it safe to delete a character?
    BNE.S   .ok                  ; If so, skip ahead to do it
    RTS                          ; Otherwise, return to the caller

    ; Retract the string by one character at the cursor position;
    ; note that we shift the null terminator as well
.ok SUBQ.W  #$1,kUITI_Len(A0)    ; Decrease the string length by one char
    MOVE.W  kUITI_CPos(A0),D0    ; Copy cursor pos to D0
    LEA.L   kUITI_Text(A0,D0.W),A1   ; Point A1 at the cursor pos
    LEA.L   $1(A1),A0            ; Point A0 at the following position
.lp MOVE.B  (A0)+,(A1)+          ; Copy a character, and if it wasn't the...
    BNE.S   .lp                  ; ...terminator, loop to copy another

    ; Update the display to show the new string; all updates shift text left
    MOVEA.L $4(SP),A0            ; Copy record address back to A0

    ; Show the updated display ("Temporary"---replace with custom code)
.sh MOVE.L  A0,-(SP)             ; Copy record address onto the stack again
    BSR     UiTextInputShow      ; Call the text display code
    ADDQ.L  #$4,SP               ; Pop record address off the stack

    ANDI.B  #$FB,CCR             ; Delete was successful; clear Z!
    RTS


    ; _UITI_Left -- Move the current location left
    ; Args:
    ;   SP+$4: Address of a UiTextInput record; must be word-aligned
    ; Notes:
    ;   Z will be clear if and only if the cursor moved left
    ;   Trashes D0-D2/A0-A2
_UITI_Left:
    MOVEA.L $4(SP),A0            ; Copy record address to A0
    BSR     _UITIE_LeftOk        ; Is it safe to move the cursor left?
    BNE.S   .ok                  ; If so, skip ahead to do it
    RTS                          ; Otherwise, return to the caller

    ; Update the display, which may have needed to shift
.ok BSR     _UITID_LShiftR       ; How do we update the display?
    BEQ.S   .ml                  ; Only the cursor should move
    SUBQ.W  #$1,kUITI_SPos(A0)   ; The visible text should shift rightward

    ; Move the cursor left---not so complicated
.ml SUBQ.W  #$1,kUITI_CPos(A0)   ; Move the cursor one step left

    ; Show the updated display ("Temporary"---replace with custom code)
    MOVE.L  A0,-(SP)             ; Copy record address onto the stack again
    BSR     UiTextInputShow      ; Call the text display code
    ADDQ.L  #$4,SP               ; Pop record address off the stack

    ANDI.B  #$FB,CCR             ; Moving left was successful; clear Z!
    RTS


    ; _UITI_Right -- Move the current location right
    ; Args:
    ;   SP+$4: Address of a UiTextInput record; must be word-aligned
    ; Notes:
    ;   Z will be clear if and only if the cursor moved right
    ;   Trashes D0-D2/A0-A2
_UITI_Right:
    MOVEA.L $4(SP),A0            ; Copy record address to A0
    BSR     _UITIE_RightOk       ; Is it safe to move the cursor right?
    BNE.S   .ok                  ; If so, skip ahead to do it
    RTS                          ; Otherwise, return to the caller

    ; Update the display, which may have needed to shift
.ok BSR     _UITID_RShiftL       ; How do we update the display?
    BEQ.S   .ml                  ; Only the cursor should move
    ADDQ.W  #$1,kUITI_SPos(A0)   ; The visible text should shift leftward

    ; Move the cursor left---not so complicated
.ml ADDQ.W  #$1,kUITI_CPos(A0)   ; Move the cursor one step right

    ; Show the updated display ("Temporary"---replace with custom code)
.sh MOVE.L  A0,-(SP)             ; Copy record address onto the stack again
    BSR     UiTextInputShow      ; Call the text display code
    ADDQ.L  #$4,SP               ; Pop record address off the stack

    ANDI.B  #$FB,CCR             ; Moving right was successful; clear Z!
    RTS


    ; _UITIE_InsertOk -- Edit check: is it OK to insert a character here?
    ; Args:
    ;   A0: Address of a UiTextInput record; must be word-aligned
    ; Notes:
    ;   Z will be clear if and only if it is OK to insert a character
    ;   Trashes D0-D1
_UITIE_InsertOk:
    MOVE.W  kUITI_Len(A0),D0     ; Copy text length to D0
    CMP.W   kUITI_Max(A0),D0     ; Is the text at or past max length?
    BGE.S   .no                  ; If so, inserting is not OK
    MOVE.W  kUITI_CPos(A0),D1    ; Copy cursor pos to D1
    CMP.W   kUITI_PLen(A0),D1    ; Is the cursor in the prefix somehow?
    BLT.S   .no                  ; If so, inserting is not OK
    SUB.W   kUITI_SLen(A0),D0    ; Subtract suffix size from text length
    CMP.W   D1,D0                ; Is the cursor in the suffix somehow?
    BLT.S   .no                  ; If so, inserting is not OK

    ANDI.B  #$FB,CCR             ; All checks pass; inserting is OK; clear Z!
    RTS

.no ORI.B   #$04,CCR             ; Inserting is not OK; set Z flag
    RTS


    ; _UITIE_BackspaceOk -- Edit check: OK to cut out the preceding character?
    ; Args:
    ;   A0: Address of a UiTextInput record; must be word-aligned
    ; Notes:
    ;   Z will be clear if and only if it is OK to cut out the character
    ;   Trashes D0-D1
_UITIE_BackspaceOk:
    MOVE.W  kUITI_Len(A0),D0     ; Copy text length to D0
    MOVE.W  kUITI_CPos(A0),D1    ; Copy cursor pos to D1; is it 0 or less?
    BLE.S   .no                  ; If so, a backspace is not OK
    CMP.W   kUITI_PLen(A0),D1    ; Would the backspace affect the prefix?
    BLE.S   .no                  ; If so, a backspace is not OK
    SUB.W   kUITI_SLen(A0),D0    ; Subtract suffix size from text length
    CMP.W   D1,D0                ; Is the cursor in the suffix somehow?
    BLT.S   .no                  ; If so, a backspace is not OK

    ANDI.B  #$FB,CCR             ; All checks pass; backspace is OK; clear Z!
    RTS

.no ORI.B   #$04,CCR             ; A backspace is not OK; set Z flag
    RTS


    ; _UITIE_DeleteOk -- Edit check: OK to cut out the character at the cursor?
    ; Args:
    ;   A0: Address of a UiTextInput record; must be word-aligned
    ; Notes:
    ;   Z will be clear if and only if it is OK to cut out the character
    ;   Trashes D0-D1
_UITIE_DeleteOk:
    MOVE.W  kUITI_Len(A0),D0     ; Copy text length to D0; is it 0 or less?
    BLE.S   .no                  ; If so, deleting is not OK
    MOVE.W  kUITI_CPos(A0),D1    ; Copy cursor pos to D1
    CMP.W   kUITI_PLen(A0),D1    ; Is the cursor in the prefix somehow?
    BLE.S   .no                  ; If so, deleting is not OK
    SUB.W   kUITI_SLen(A0),D0    ; Subtract suffix size from text length
    CMP.W   D1,D0                ; Is the cursor at or somehow in the suffix?
    BLE.S   .no                  ; If so, deleting is not OK

    ANDI.B  #$FB,CCR             ; All checks pass; deleting is OK; clear Z!
    RTS

.no ORI.B   #$04,CCR             ; Deleting is not OK; set Z flag
    RTS


    ; _UITIE_LeftOk -- Edit check: OK to move to the preceding character?
    ; Args:
    ;   A0: Address of a UiTextInput record; must be word-aligned
    ; Notes:
    ;   Z will be clear if and only if it is OK to move the cursor left
    ;   Trashes D1
_UITIE_LeftOk:
    MOVE.W  kUITI_CPos(A0),D1    ; Copy cursor pos to D1
    CMP.W   kUITI_PLen(A0),D1    ; Is the cursor somehow in the prefix?
    BLE.S   .no                  ; If so, moving left is not OK

    ANDI.B  #$FB,CCR             ; Check passed; moving left is OK; clear Z!
    RTS

.no ORI.B   #$04,CCR             ; Moving left is not OK; set Z flag
    RTS


    ; _UITIE_RightOk -- Edit check: OK to move to the following cursor?
    ; Args:
    ;   A0: Address of a UiTextInput record; must be word-aligned
    ; Notes:
    ;   Z will be clear if and only if it is OK to move the cursor right
    ;   Trashes D1
_UITIE_RightOk:
    MOVE.W  kUITI_Len(A0),D1     ; Copy text length to D1
    SUB.W   kUITI_SLen(A0),D1    ; Subtract suffix size from text length
    CMP.W   kUITI_CPos(A0),D1    ; Is the cursor at or somehow in the suffix?
    BLE.S   .no                  ; If so, moving right is not OK

    ANDI.B  #$FB,CCR             ; Check passed; moving right is OK; clear Z!
    RTS

.no ORI.B   #$04,CCR             ; Moving right is not OK; set Z flag
    RTS


* Not presently used---may be handy for later versions of the library
*
*     ; _UITID_ShowAllOk -- Display check: can the whole text fit the TextInput?
*     ; Args:
*     ;   A0: Address of a UiTextInput record; must be word-aligned
*     ; Notes:
*     ;   Z will be clear if and only if the whole text can fit in the widget
*     ;   Trashes D0
* _UITID_ShowAllOk:
*     MOVE.B  kUITI_Width(A0),D0   ; Copy textinput width to D0
*     EXT.W   D0                   ; Extend it to a word
*     CMP.W   kUITI_Len(A0),D0     ; Smaller than the current text length?
*     BLT.S   .no                  ; If so, the whole text cannot be shown
*
*     ANDI.B  #$FB,CCR             ; Check passed; the whole text fits; clear Z!
*     RTS
*
* .no ORI.B   #$04,CCR             ; The whole text does not fit; set Z flag
*     RTS


    ; _UITID_InsShiftR -- Display check: how to update display after an insert?
    ; Args:
    ;   A0: Address of a UiTextInput record; must be word-aligned
    ; Notes:
    ;   Z will be clear if the cursor and text following should move right
    ;   Z will be set if the cursor should stay, with text preceding moving left
    ;   Trashes D0-D1
_UITID_InsShiftR:
    MOVE.B  kUITI_Width(A0),D1   ; Copy textinput width into D1
    EXT.W   D1
    MOVE.W  kUITI_Len(A0),D0     ; Determine whether the end of the text...
    SUB.W   kUITI_SPos(A0),D0    ; ...fits in the text box, and if it does...
    CMP.W   D1,D0                
    BLE.S   .ok                  ; ...then expand to the right

    MOVE.W  kUITI_CPos(A0),D0    ; Put cursor position in D0, then subtract...
    SUB.W   kUITI_SPos(A0),D0    ; ...scroll pos to get position in textinput
    BLE.S   .ok                  ; Off screen to left? Expand to right, I guess
    SUB.B   kUITI_Marg(A0),D1    ; Subtract margin from width for right bound
    EXT.W   D1
    CMP.W   D1,D0                ; Is the cursor on or beyond the margin?
    BGT.S   .no                  ; If so, we should grow to the left

.ok ANDI.B  #$FB,CCR             ; Check passed; expand to the right; clear Z!
    RTS

.no ORI.B   #$04,CCR             ; Check failed; expand to the left; set Z
    RTS


    ; _UITID_BksShiftL -- Display check: how to update display after backspace?
    ; Args:
    ;   A0: Address of a UiTextInput record; must be word-aligned
    ; Notes:
    ;   Z will be clear if the cursor and text following should move left
    ;   Z will be set if the cursor should stay, with text preceding going right
    ;   Trashes D0-D1
_UITID_BksShiftL:
    MOVE.W  kUITI_SPos(A0),D1    ; Put scroll position in D1; is it 0?
    BLE.S   .ok                  ; If so, move text following left like normal
    MOVE.W  kUITI_CPos(A0),D0    ; Put cursor position in D0, then subtract...
    SUB.W   D1,D0                ; ...scroll pos to get position in textinput
    MOVE.B  kUITI_Marg(A0),D1    ; Put textinput margin in D1...
    EXT.W   D1
    CMP.W   D1,D0                ; Is the cursor on or past the margin?
    BLE.S   .no                  ; If so, move text preceding rightward

.ok ANDI.B  #$FB,CCR             ; Check passed; tow text leftward; clear Z!
    RTS

.no ORI.B   #$04,CCR             ; Check failed; suck text rightward; set Z
    RTS
 

    ; _UITID_LShiftR -- Display check: how to update display after "move left"?
    ; Args:
    ;   A0: Address of a UiTextInput record; must be word-aligned
    ; Notes:
    ;   Z will be clear if the cursor should stay put and all text shifted right
    ;   Z will be set if only the cursor should move
    ;   Trashes D0-D1
_UITID_LShiftR:
    MOVE.W  kUITI_SPos(A0),D1    ; Put scroll position in D1; is it 0?
    BLE.S   .no                  ; If so, only the cursor moves
    MOVE.W  kUITI_CPos(A0),D0    ; Put cursor position in D0, then subtract...
    SUB.W   D1,D0                ; ...scroll pos to get position in textinput
    MOVE.B  kUITI_Marg(A0),D1    ; Put textinput margin in D1...
    EXT.W   D1
    CMP.W   D1,D0                ; Is the cursor on or past the margin?
    BGT.S   .no                  ; If not, only the cursor moves

    ANDI.B  #$FB,CCR             ; Check passed; shift text right; clear Z!
    RTS

.no ORI.B   #$04,CCR             ; Check failed; only the cursor moves; set Z
    RTS


    ; _UITID_RShiftL -- Display check: how to update display after "move right"?
    ; Args:
    ;   A0: Address of a UiTextInput record; must be word-aligned
    ; Notes:
    ;   Z will be clear if the cursor should stay put and all text shifted left
    ;   Z will be set if only the cursor should move
    ;   Trashes D0-D1
_UITID_RShiftL:
    MOVE.W  kUITI_Len(A0),D1     ; Current length into D1, then subtract...
    SUB.W   kUITI_SPos(A0),D1    ; ...scroll pos for chars past left edge
    MOVE.B  kUITI_Width(A0),D0   ; Copy textinput width to D0
    EXT.W   D0
    CMP.W   D0,D1                ; Is the end of the text visible?
    BLE.S   .no                  ; If so, only the cursor moves

    MOVE.B  kUITI_Marg(A0),D1    ; Copy textinput scroll margin to D1
    EXT.W   D1
    SUB.W   D1,D0                ; Subtract margin from textinput width
    MOVE.W  kUITI_CPos(A0),D1    ; Put cursor position in D1, then subtract...
    SUB.W   kUITI_SPos(A0),D1    ; ...scroll pos to get position in textinput
    CMP.W   D1,D0                ; Is cursor at or beyond the margin?
    BGT.S   .no                  ; If not, only the cursor moves

    ANDI.B  #$FB,CCR             ; Check passed; shift text left; clear Z!
    RTS

.no ORI.B   #$04,CCR             ; Check failed; only the cursor moves; set Z
    RTS
