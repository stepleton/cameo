* Cameo/Aphid disk image selector: UCSD p-System-style menus
* ==========================================================
*
* Forfeited into the public domain with NO WARRANTY. Read LICENSE for details.
*
* Displays a menu at the top of the screen that resembles the menus used by the
* UCSD p-System (and systems it inspired, like the Monitor and the Pascal
* Workshop). Uses the `ui_base.x68` library.
* 
*    [Title] Command: Y(odel, W(arble, U(lulate, C(aterwaul, ? [1.2]
*
* The "[Title]" prefix is novel to this library, and optional. The version
* string "[1.2]" is common to several p-System implementations, and also
* optional. The text in between usually presents several single-letter menu
* options in the style shown, although the library will accept any string for
* this region.
*
* By convention, the ? command displays more options that would not fit in the
* menu, often without the version string:
*
*    [Title] Command: B(ellow, S(hriek
*
* In either menu, all of the commands are usually available, including ?, which
* has the effect of toggling back and forth between the menus.
*
* Identifying commands that all start with different letters is a challenge for
* the menu designer.
*
* Public procedures:
*    - UiPSystemShow -- Show a UCSD p-System style menu
*    - UiPSystemKey -- Interpret a keypress
*
* All public procedures have convenience macros in `ui_macros.x68`.
*
* There's not much to this component. Typical applications will display a menu
* with UiPSystemShow, collect a key input through some I/O library, then
* attempt to interpret the keypress with UiPSystemKey.


* ui_psystem_menu Code --------------------------


    SECTION kSecCode


    ; UiPSystemShow -- Show a UCSD p-System style menu
    ; Args:
    ;   SP+$C: l. Address of the version string, or $0 to show no version string
    ;   SP+$8: l. Address of the command text, or $0 to show no command text
    ;   SP+$4: l. Address of the title string, or $0 to show no title
    ; Notes:
    ;   Menus that extend beyond one row of text cause undefined behaviour
    ;   Trashes D0-D1/A0-A1
UiPSystemShow:
    ; First, clear the row where the menu line displays, and indent two spaces
    mUiClearBox  #$1,#$0,#$1,#$5A
    mUiPrint   r1c2              ; Ready to go at row 1 column 2
    ; Print the title if supplied
    TST.L   $4(SP)               ; Is there a title string?
    BEQ.S   .co                  ; No, skip to the command string
    MOVE.L  $4(SP),-(SP)         ; Yes, duplicate its pointer on the stack
    mUiPutc #'['
    mUiPrint   s,<'] '>          ; Print the title string in square brackets
    ; Print the command text if supplied
.co TST.L   $8(SP)               ; Is there command text?
    BEQ.S   .ve                  ; No, skip to the version string
    MOVE.L  $8(SP),-(SP)         ; Yes, duplicate its pointer on the stack
    mUiPrint  s                  ; Print the command text by itself
    mUiPutc #$20                 ; Trailing space after command text
    ; Print the version string if supplied
.ve TST.L   $C(SP)               ; Is there a version string?
    BEQ.S   .rt                  ; No, skip to return
    MOVE.L  $C(SP),-(SP)         ; Yes, duplicate its pointer on the stack
    mUiPutc #'[' 
    mUiPrint   s                 ; Print the version string in square brackets
    mUiPutc #']'

.rt RTS


    ; UiPSystemKey -- Interpret a keypress
    ; Args:
    ;   SP+$6: l. Address of the "menu list" data structure (see notes)
    ;   SP+$4: b. ISO 8859-1 character byte from the keypress
    ; Notes:
    ;   The word-aligned "menu list" repeats:
    ;      - a padding byte which is either $00 (requiring an exact match) or
    ;        $01 (case-insensitive matches OK); use no other padding byte
    ;      - an ISO 8859-1 character byte; if you've specified a $01 padding
    ;        byte for case-insensitve matching, this must be an uppercase letter
    ;      - a 16-bit signed offset from the "menu list" address in SP+$4
    ;   The menu list is terminated with a $0000 word
    ;   This routine attempts to match the SP+$6 argument with a menu list entry
    ;   If a match is found, a full address is computed in A0 and Z is set
    ;   Otherwise Z is cleared
    ;   Trashes D0,A0
UiPSystemKey:
    MOVEA.L $6(SP),A0            ; Point A0 at the menu list
.lo TST.W   (A0)                 ; Have we reached the end of the menu list?
    BEQ.S   .no                  ; Yes, quit empty-handed
    MOVE.B  $4(SP),D0            ; (Re)copy the character byte to D0
    BTST.B  #$0,(A0)+            ; Is this entry's case-insensitive flag set?
    BEQ.S   .cp                  ; If not, skip ahead to compare
    ANDI.B  #$DF,D0              ; If so, make the character byte uppercase
.cp CMP.B   (A0)+,D0             ; Does the key match the list entry?
    BEQ.S   .ok                  ; Yes, construct the jump address and return
    ADDQ.L  #$2,A0               ; No, move to the next menu list entry
    BRA.S   .lo                  ; Loop again to process it

.no ANDI.B  #$FB,CCR             ; Clear the Z flag
    BRA.S   .rt                  ; Jump to exit

.ok MOVE.W  (A0),D0              ; Copy address offset to D0
    MOVEA.L $6(SP),A0            ; Point A0 back at the menu list
    ADDA.W  D0,A0                ; Add the address offset
    ORI.B   #$04,CCR             ; Set the Z flag

.rt RTS
