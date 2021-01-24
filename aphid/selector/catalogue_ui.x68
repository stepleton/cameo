* Cameo/Aphid disk image selector: UI routines for the drive image catalogue
* ==========================================================================
*
* Forfeited into the public domain with NO WARRANTY. Read LICENSE for details.
*
* Routines that display the drive image catalogue and provide user interfaces
* for modifying it.
*
* Routines starting with `CatalogueMenu` present a scrolling menu view (see
* ui_scrolling_menu.x68) of the catalogue of drive images on the Cameo/Aphid
* (see catalogue.x68). Routines starting with `AskImage` present separate
* user interfaces that request information and confirmation from the user.
*
* These routines make use of data definitions set forth in selector.x68 and
* routines defined in ask_ui.x68, block.x68, catalogue.x68,
* lisa_ui/lisa_console_screen.x68, ui_base.x68, ui_scrolling_menu.x68, and
* ui_textinput.x68. They also invoke macros defined in ui_macros.x68 and
* require that the lisa_profile_io library from the lisa_io collection be
* memory-resident.
*
* Public procedures:
*    - CatalogueMenuShow -- Show the scrolling menu drive image catalogue
*    - CatalogueMenuUp -- Move the catalogue menu selection up
*    - CatalogueMenuDown -- Move the catalogue menu selection down
*    - AskImageSelect -- A UI narrating the selection of a new drive image
*    - AskImageNew -- A UI for creating a new drive image
*    - AskImageDelete -- A UI for confirming drive image deletion
*    - AskImageCopy -- A UI for copying a drive image
*    - AskImageRename -- A UI for renaming a drive image


* catalogue_ui Code ------------------------------


    SECTION kSecCode


    ; CatalogueMenuShow -- Show the scrolling menu drive image catalogue
    ; Args:
    ;   (none -- uses the zCatMenu data structure)
    ; Notes:
    ;   Does not refresh the catalogue prior to showing the menu
    ;   Does not clear the screen prior to showing the menu
    ;   Trashes D0-D2/A0-A1
CatalogueMenuShow:
    ; First, print the "------" that goes above and below the menu
    ; We use direct calls to print routines for speed and brevity
    MOVEQ.L #$2,D1               ; Start printing on column 2
.lp MOVEQ.L #'-',D0              ; Print a '-' character
    MOVEQ.L #$4,D2               ; Print it to row 4
    BSR     PutcLisaConsole      ; Print it
    MOVEQ.L #'-',D0              ; Print a '-' character
    MOVEQ.L #$21,D2              ; Print it to row 33
    BSR     PutcLisaConsole      ; Print it
    ADDQ.W  #$1,D1               ; Advance to the next column
    CMPI.W  #$57,D1              ; Are there still columns left to go?
    BLS.S   .lp                  ; Yes, loop back and print them

    ; Update information in the UiScrollingMenu record
    LEA.L   zCatMenu(PC),A0      ; Point A0 at the catalogue menu record
    LEA.L   _CataloguePItem(PC),A1   ; Point A1 at _CataloguePItem
    MOVE.L  A1,kUISM_PItem(A0)   ; Use A1 to set the PItem pointer
    MOVE.W  (zCatalogue+kCatH_Count,PC),D0   ; Number of catalogue items to D0
    MOVE.W  D0,kUISM_Len(A0)     ; Update the length of the menu
    CMP.W   kUISM_CPos(A0),D0    ; Is the cursor now past the end of the list?
    BLO.S   .dm                  ; If not, skip ahead to display
    CLR.W   kUISM_CPos(A0)       ; If so, scroll back to the top of the menu
    CLR.W   kUISM_SPos(A0)       ; (TODO: Do something more elegant...)

    ; Display the menu
.dm MOVE.L  A0,-(SP)             ; Push catalogue menu record on stack
    BSR     UiScrollingMenuShow  ; Display the drive catalogue menu
    ADDQ.L  #$4,SP               ; Pop catalogue menu record off stack
    RTS


    ; CatalogueMenuTop -- Move the catalogue menu selection to the first item
    ; Args:
    ;   (none -- uses the zCatMenu data structure)
    ; Notes:
    ;   Does NOT redraw the catalogue; this routine is meant mainly as a prelude
    ;       to displaying the catalogue for the first time on a new volume
    ;   Trashes A0
CatalogueMenuTop:
    LEA.L   zCatMenu(PC),A0      ; Point A0 at the catalogue menu record
    CLR.W   kUISM_CPos(A0)       ; If so, scroll back to the top of the menu
    CLR.W   kUISM_SPos(A0)       ; (TODO: Do something more elegant...)
    RTS


    ; CatalogueMenuUp -- Move the catalogue menu selection up
    ; Args:
    ;   (none -- uses the zCatMenu data structure)
    ; Notes:
    ;   Trashes D0-D1/A0-A1
CatalogueMenuUp:
    PEA.L   zCatMenu(PC)         ; Catalogue menu record address to the stack
    BSR     UiScrollingMenuUp    ; Move to the previous menu item
    ADDQ.L  #$4,SP               ; Pop the address off the stack
    RTS


    ; CatalogueMenuDown -- Move the catalogue menu selection down
    ; Args:
    ;   (none -- uses the zCatMenu data structure)
    ; Notes:
    ;   Trashes D0-D1/A0-A1
CatalogueMenuDown:
    PEA.L   zCatMenu(PC)         ; Catalogue menu record address to the stack
    BSR     UiScrollingMenuDown  ; Move to the previous menu item
    ADDQ.L  #$4,SP               ; Pop the address off the stack
    RTS


    ; _CataloguePItem -- Catalogue menu item printer callback
    ; Args:
    ;   SP+$4: zCatMenu
    ; Notes:
    ;   Filenames that are too wide are truncated with an inverted ellipsis
    ;       character.
    ;   Trashes D0-D1/A0-A1
_CataloguePItem:
    MOVEA.L $4(SP),A1            ; Point A1 at zCatMenu
    MOVE.W  kUISM_PIArg(A1),-(SP)  ; We need to print for this entry...
    BSR     CatalogueItemName    ; ...and the name is now (A0)
    ADDQ.L  #$2,SP               ; Pop item index off the stack

    ; This check depends on CatalogueUpdate padding out filenames in catalogue
    ; entries with NULs
    TST.B   $54(A0)              ; Can the whole string fit on screen?
    BEQ.S   .pa                  ; That's a NUL, so yes; jump to print it all

    ; Truncate long filenames with an ellipsis character
    LEA.L   $53(A0),A1           ; Point A1 toward the end of the string
    MOVE.L  A1,D1                ; Copy A1 to D1
    BCLR.L  #$0,D0               ; Make that address even, just in case
    MOVE.L  D1,A1                ; Copy it back to A1
    MOVE.W  (A1),-(SP)           ; Save string characters here on stack
    MOVE.L  A1,-(SP)             ; Save location of those chars on stack too
    MOVE.W  #$0300,(A1)          ; Place an ellipsis and a terminator here
    mUiPrintStr A0               ; Print the temporarily truncated string
    MOVEA.L (SP)+,A1             ; Restore the address of the truncation
    MOVE.W  (SP)+,(A1)           ; Undo the truncation
    BRA.S   .rt                  ; Jump ahead to return

.pa mUiPrintStr A0               ; Print the entire string
.rt RTS


    ; AskImageSelect -- A UI narrating the selection of a new drive image
    ; Args:
    ;   zCatMenu+kUISM_CPos: Index of the current selected drive image
    ; Notes:
    ;   Requires an accurate, up-to-date catalogue
    ;   Clears the screen prior to performing and narrating the selection
    ;   Z is set iff the selection operation succeeds
    ;   Trashes D0-D2/A0-A2
AskImageSelect:
    LEA.L   zCatMenu(PC),A0      ; Point A0 at the catalog menu record
    MOVE.W  kUISM_CPos(A0),-(SP)   ; Push currently selected item index to stack
    BSR     CatalogueItemName    ; A0 now points at the selection's filename
    ADDQ.L  #$2,SP               ; Pop item index off of stack
    MOVE.L  A0,-(SP)             ; Push filename onto the stack

    ; Perform and narrate the selection operation
    BSR     ClearLisaConsoleScreen   ; Blank the screen
    mUiPrint  r1c1,<'{ Select image }',$0A>
    BSR     NImageChange         ; Change the disk image
    ADDQ.L  #$4,SP               ; Pop filename off of stack
    BSR     AskVerdictByZ        ; Print the verdict, await a keypress
    RTS


    ; AskImageNew -- A UI for creating a new drive image
    ; Args:
    ;   (none)
    ; Notes:
    ;   Requires an accurate, up-to-date catalogue
    ;   Attempts to refresh the catalogue if the creation operation succeeds
    ;   Clears the screen prior to seeking input from the user
    ;   Z is set iff the creation operation and catalogue refresh both succeed
    ;       (User cancellation is not success)
    ;   Trashes D0-D2/A0-A2
AskImageNew:
    ; Copy the untitled drive image name to zBlock -- a scratch area that's also
    ; the place where the drive image name will serve as an ImageNew argument
    PEA.L   sNewImageFilename(PC)  ; Copy from the default new image filename
    PEA.L   zBlock(PC)           ; Copy to the beginning of zBlock
    BSR     StrCpy255            ; Do the copy
    ADDQ.L  #$8,SP               ; Pop the copy arguments off the stack

    ; Ask the user to edit the filename
    PEA.L   sAskTitleNew(PC)     ; Here's the UI's title string
    CLR.L   -(SP)                ; There is no old filename subtitle
    CLR.L   -(SP)                ; Since there's no filename to display
    PEA.L   zBlock(PC)           ; Here's the filename to edit
    BSR     _AskFilename         ; Ask the user what filename they'd like
    ADDQ.L  #$8,SP               ; Pop _AskFilename args, part 1
    ADDQ.L  #$8,SP               ; Pop _AskFilename args, part 2

    BEQ.S   .go                  ; User says do it! Jump ahead
    PEA.L   sAskVerdictCancelled(PC)  ; No, user wants to cancel
    BSR     AskVerdict           ; Tell user that we cancelled
    ADDQ.L  #$4,SP               ; Pop the AskVerdict argument
    BRA.S   .rt                  ; Jump ahead to return

    ; Attempt to create the image using shared code for 1-arg operations
.go PEA.L   ImageNew(PC)         ; We want to call ImageNew
    PEA.L   sAskOpFailedCreate(PC)   ; This is its failure message
    BSR     _AskImageCommonOneArg  ; Call common code for 1-arg operations
    ADDQ.L  #$8,SP               ; Pop common code arguments off the stack

.rt RTS


    ; AskImageDelete -- A UI for confirming drive image deletion
    ; Args:
    ;   zCatMenu+kUISM_CPos: Index of the current selected drive image
    ; Notes:
    ;   Requires an accurate, up-to-date catalogue
    ;   Attempts to refresh the catalogue if the deletion operation succeeds
    ;   Clears the screen prior to seeking input from the user
    ;   Z is set iff the deletion operation and catalogue refresh both succeed
    ;       (User cancellation is not success)
    ;   Trashes D0-D2/A0-A2
AskImageDelete:
    ; Copy the original filename to zBlock -- where it will also serve as the
    ; ImageDelete argument
    LEA.L   zCatMenu(PC),A0      ; Point A0 at the catalog menu record
    MOVE.W  kUISM_CPos(A0),-(SP)   ; Push currently selected item index to stack
    BSR     CatalogueItemName    ; A0 now points at the selection's filename
    ADDQ.L  #$2,SP               ; Pop item index off of stack
    MOVE.L  A0,-(SP)             ; Copy a string from that address
    PEA.L   zBlock(PC)           ; Copy it to the beginning of zBlock
    BSR     StrCpy255            ; Do the copy
    ADDQ.L  #$8,SP               ; Pop StrCpy255 args off the stack

    ; Ask the user if they really want to delete this file
    BSR     ClearLisaConsoleScreen   ; Blank the screen
    PEA.L   zBlock(PC)           ; Push the filename to delete onto the stack
    mUiPrint  r1c1,<'{ Delete image }',$0A,$0A,'   Image file: '>,s
    PEA.L   sAskReturnCancel(PC)   ; Message about keys to press
    mUiPrint  <$0A,$0A,' This operation CANNOT BE UNDONE!',$0A>,s
.wt BSR     LisaConsoleWaitForKbMouse  ; Await a keypress
    BNE.S   .wt                  ; Keep waiting if it wasn't a keypress
    MOVE.B  zLisaConsoleKbCode(PC),D0  ; Load user's key into D0
    CMPI.B  #$48,D0              ; Did the user type Return?
    BEQ.S   .go                  ; If so, go delete the file
    CMPI.B  #$20,D0              ; Did the user type Clear?
    BNE.S   .wt                  ; No, await another keypress

    ; If here, the user has cancelled; quit now
    PEA.L   sAskVerdictCancelled(PC)  ; No, user wants to cancel
    BSR     AskVerdict           ; Tell user that we cancelled
    ADDQ.L  #$4,SP               ; Pop the AskVerdict argument
    BRA.S   .rt                  ; Jump ahead to return

    ; Attempt to delete the image using shared code for 1-arg operations
.go PEA.L   ImageDelete(PC)      ; We want to call ImageDelete
    PEA.L   sAskOpFailedDelete(PC)   ; This is its failure message
    BSR.S   _AskImageCommonOneArg  ; Call common code for 1-arg operations
    ADDQ.L  #$8,SP               ; Pop common code arguments off the stack

.rt RTS


    ; _AskImageCommonOneArg -- Common code for AskImageNew and AskImageDelete
    ; Args:
    ;   SP+$8: l. Address of ImageNew or ImageDelete, as appropriate
    ;   SP+$4: l. Address of sAskOpFailedCreate or sAskOpFailedDelete, same
    ;   zBlock: Filename argument for ImageNew or ImageDelete
    ; Notes:
    ;   Requires an accurate, up-to-date catalogue
    ;   Attempts to refresh the catalogue if the image operation succeeds
    ;   Does less than _AskImageCommonOneArg because New and Delete have less
    ;       in common than Copy and Rename
    ;   Z is set iff the image operation and catalogue refresh both succeed
    ;       (User cancellation is not success)
    ;   Trashes D0-D2/A0-A2
_AskImageCommonOneArg:
    PEA.L   sAskIssuing(PC)      ; Print "\n\n\n\n\nIssuing command... "
    mUiPrint  s
    MOVEA.L $8(SP),A0            ; A0 holds the address of Image___
    PEA.L   zBlock(PC)           ; Filename argument for Image___
    JSR     (A0)                 ; Call Image___
    ADDQ.L  #$4,SP               ; Pop Image___ argument
    BSR     AskOpResultByZ       ; Print whether we succeeded or failed
    SNE.B   -(SP)                ; If Z push $00, otherwise push $FF
    BEQ.S   .cr                  ; On success, jump to update the catalogue
    MOVE.L  $6(SP),-(SP)         ; Copy failure message on the stack
    mUiPrint  s                  ; Print it
    PEA.L   sAskOpFailedComms(PC)  ; "we couldn't talk to Cameo/Aphid"
    mUiPrint  s                  ; Print it

    ; Now try to refresh the catalogue, whether the operation succeeded or not
.cr BSR     NCatalogueUpdate     ; Narrated version of catalogue updating

    ; Compute verdict based on the success of both steps and await a keypress
    SNE.B   D0                   ; If Z set D0 to $00, otherwise to $FF
    OR.B    (SP)+,D0             ; Or it with saved ~Z from Image___
    TST.B   D0                   ; Was Z set for both? That's our verdict
    BSR     AskVerdictByZ        ; Print the verdict, await a keypress

.rt RTS


    ; AskImageCopy -- A UI for copying a drive image
    ; Args:
    ;   zCatMenu+kUISM_CPos: Index of the current selected drive image
    ; Notes:
    ;   Requires an accurate, up-to-date catalogue
    ;   Attempts to refresh the catalogue if the copy operation succeeds
    ;   Clears the screen prior to seeking input from the user
    ;   Z is set iff the copy operation and catalogue refresh both succeed
    ;       (User cancellation is not success)
    ;   Trashes D0-D2/A0-A2
AskImageCopy:
    PEA.L   ImageCopy(PC)        ; Call _AskImageCommonTwoArg with arguments...
    PEA.L   sAskTitleCopy(PC)    ; ...for copying a file
    PEA.L   sAskSubtitleCopy(PC)
    BSR.S   _AskImageCommonTwoArg
    ADDQ.L  #$8,SP               ; Pop _AskImageCommonTwoArg arguments, part 1
    ADDQ.L  #$4,SP               ; Pop _AskImageCommonTwoArg arguments, part 2
    RTS


    ; AskImageRename -- A UI for renaming a drive image
    ; Args:
    ;   zCatMenu+kUISM_CPos: Index of the current selected drive image
    ; Notes:
    ;   Requires an accurate, up-to-date catalogue
    ;   Attempts to refresh the catalogue if the rename operation succeeds
    ;   Clears the screen prior to seeking input from the user
    ;   Z is set iff the rename operation and catalogue refresh both succeed
    ;       (User cancellation is not success)
    ;   Trashes D0-D2/A0-A2
AskImageRename:
    PEA.L   ImageRename(PC)      ; Call _AskImageCommonTwoArg with arguments...
    PEA.L   sAskTitleRename(PC)    ; ...for renaming a file
    PEA.L   sAskSubtitleRename(PC)
    BSR.S   _AskImageCommonTwoArg
    ADDQ.L  #$8,SP               ; Pop _AskImageCommonTwoArg arguments, part 1
    ADDQ.L  #$4,SP               ; Pop _AskImageCommonTwoArg arguments, part 2
    RTS


    ; _AskImageCommonTwoArg -- Common code for AskImageCopy and AskImageRename
    ; Args:
    ;   SP+$C: l. Address of ImageCopy or ImageRename, as appropriate
    ;   SP+$8: l. Address of the title string ("Copy" or  "Rename")
    ;   SP+$4: l. Address of the subtitle ("Copy from" or "Old filename")
    ;   zCatMenu+kUISM_CPos: Index of the current selected drive image
    ; Notes:
    ;   Requires an accurate, up-to-date catalogue
    ;   Attempts to refresh the catalogue if the image operation succeeds
    ;   Clears the screen prior to seeking input from the user
    ;   Does more than _AskImageCommonOneArg because Copy and Rename have more
    ;       in common than New and Delete
    ;   Z is set iff the image operation and catalogue refresh both succeed
    ;       (User cancellation is not success)
    ;   Trashes D0-D2/A0-A2
_AskImageCommonTwoArg:
    ; Copy the original filename to zBlock -- where it will also serve as an
    ; ImageCopy/ImageRename argument
    LEA.L   zCatMenu(PC),A0      ; Point A0 at the catalog menu record
    MOVE.W  kUISM_CPos(A0),-(SP)   ; Push currently selected item index to stack
    BSR     CatalogueItemName    ; A0 now points at the selection's filename
    ADDQ.L  #$2,SP               ; Pop item index off of stack
    MOVE.L  A0,-(SP)             ; Copy a string from that address
    PEA.L   zBlock(PC)           ; Copy it to the beginning of zBlock
    BSR     StrCpy255            ; Do the copy

    ; We want to copy the original filename again -- where _AskFilename can edit
    ; it, and where it too will be an ImageCopy/ImageRename argument
    MOVE.L  (SP),$4(SP)          ; Replace source filename on stack with zBlock
    MOVE.L  A0,(SP)              ; And dest. filename with end of the last copy
    BSR     StrCpy255            ; Do the copy
    MOVE.L  (SP)+,A1             ; Pop copy destination address to A1
    MOVE.L  (SP)+,A0             ; Pop copy source address to A0

    ; Now ask the user to edit the filename
    MOVE.L  $8(SP),-(SP)         ; Duplicate first _AskFilename arg on stack
    MOVE.L  $8(SP),-(SP)         ; Duplicate second _AskFilename arg on stack
    MOVE.L  A0,-(SP)             ; Source file is the old filename (third arg)
    MOVE.L  A1,-(SP)             ; Dest. file is the editable filename (fourth)
    BSR.S   _AskFilename         ; Ask the user what filename they'd like
    ADDQ.L  #$8,SP               ; Pop _AskFilename args, part 1
    ADDQ.L  #$8,SP               ; Pop _AskFilename args, part 2

    BEQ.S   .go                  ; User says do it! Jump ahead
    PEA.L   sAskVerdictCancelled(PC)  ; No, user wants to cancel
    BSR     AskVerdict           ; Tell user that we cancelled
    ADDQ.L  #$4,SP               ; Pop the AskVerdict argument
    BRA.S   .rt                  ; Jump ahead to return

    ; Attempt to execute the command
.go PEA.L   sAskIssuing(PC)      ; Print "\n\n\n\n\nIssuing command... "
    mUiPrint  s
    MOVE.L  $C(SP),A0            ; A0 holds the address of Image____
    LEA.L   zBlock(PC),A1        ; Holds filename arguments for Image____
    MOVE.L  A1,-(SP)             ; Pointer to first filename onto stack
.lp TST.B   (A1)+                ; Are we past the first filename yet?
    BNE.S   .lp                  ; If not, keep going
    MOVE.L  A1,-(SP)             ; Pointer to second filename onto stack
    JSR     (A0)                 ; Call Image____
    ADDQ.L  #$8,SP               ; Pop Image____ arguments
    BSR     AskOpResultByZ       ; Print whether we succeeded or failed
    SNE.B   -(SP)                ; If Z push $00, otherwise push $FF
    BEQ.S   .cr                  ; On success, jump to update the catalogue
    PEA.L   sAskOpFailedComms(PC)  ; "we couldn't talk to Cameo/Aphid"
    PEA.L   sAskOpFailedCreate(PC)   ; "A file with that name exists, or"
    mUiPrint  s,s                ; Print the bad news

    ; Now try to refresh the catalogue, whether the operation succeeded or not
.cr BSR     NCatalogueUpdate     ; Narrated version of catalogue updating

    ; Compute verdict based on the success of both steps and await a keypress
    SNE.B   D0                   ; If Z set D0 to $00, otherwise to $FF
    OR.B    (SP)+,D0             ; Or it with saved ~Z from Image____
    TST.B   D0                   ; Was Z set for both? That's our verdict
    BSR     AskVerdictByZ        ; Print the verdict, await a keypress

.rt RTS


    ; _AskFilename -- A standard interface for asking for a filename
    ; Args:
    ;   SP+$10: l. Address of title string (the X in "X image")
    ;   SP+$0C: l. Address of "old filename" subtitle, or $0 for no subtitle
    ;   SP+$08: l. Address of old filename; ignored if SP+$0C is 0
    ;   SP+$04: l. Address of the editable new filename
    ; Notes:
    ;   Clears the screen prior to seeking input from the user
    ;   Sets Z iff the user typed Return (and not Clear: Proceed, not Cancel)
    ;   Trashes D0-D2/A0-A2
_AskFilename:
    ; Copy the filename to the place where we will edit it, and then use what we
    ; learn along the way to fill in zCatTextInput
    MOVE.L  $4(SP),-(SP)         ; Copy from the argument location
    LEA.L   zCatTextInput(PC),A0   ; Point A0 at the textinput record
    PEA.L   kUITI_Text(A0)       ; Copy to the record's own string buffer
    BSR     StrCpy255            ; Go copy the string
    MOVE.L  (SP)+,A1             ; Pop record's string buffer address into A1
    ADDQ.L  #$4,SP               ; (Discard the original string address)

    ; Compute length of the string being edited; note that A0 now points just
    ; past the terminator of the copied string
    SUBA.L  A1,A0                ; A0 now holds 1 + the string length
    SUBQ.L  #$1,A0               ; Now A0 is the string length (sans NULL)
    MOVE.W  A0,D0                ; Put it in D0 for more convenience
    LEA.L   zCatTextInput(PC),A1   ; Point A1 at the textinput record
    MOVE.W  D0,kUITI_Len(A1)     ; Copy the string length there

    ; Compute cursor position for the textinput
    CLR.W   kUITI_CPos(A1)       ; Set cursor position to 0 (paranoia)
    MOVE.W  D0,D1                ; Copy string length to D1
    SUBQ.W  #$6,D1               ; Subtract 6, the length of ".image"
    BLO.S   .sp                  ; (Oops, length<6? Nevermind! More paranoia)
    MOVE.W  D1,kUITI_CPos(A1)    ; That's the cursor position

    ; Compute scroll position for the textinput
.sp CLR.W   kUITI_SPos(A1)       ; By default, the scroll position is 0
    MOVE.B  kUITI_Width(A1),D1   ; Copy textinput width to D1
    ANDI.W  #$00FF,D1            ; Unsigned-extend D1 to a word
    SUB.W   D1,D0                ; Is the filename wider than the textinput?
    BLS.S   .ui                  ; If not, scroll position 0 is fine
    MOVE.W  D0,kUITI_CPos(A1)    ; Otherwise, ".image" abuts the rightmost edge

    ; Prepare the user interface
.ui BSR     ClearLisaConsoleScreen   ; Blank the screen
    MOVE.L  $10(SP),-(SP)        ; Copy title string address on stack
    mUiPrint  r1c1,<'{ '>,s,<' image }',$0A,$0A>
    TST.L   $C(SP)               ; Is there an "old filename" subtitle?
    BEQ.S   .nf                  ; No, jump ahead
    MOVE.L  $08(SP),-(SP)        ; Copy old filename on stack
    MOVE.L  $10(SP),-(SP)        ; Copy subtitle address on stack
    mUiPrint  s,<':  '>,s,<$0A>  ; Print "old filename" line and newline
.nf MOVE.W  zRowLisaConsole(PC),-(SP)  ; Save current row on the stack
    mUiPrint  <' New filename: ['>   ; Print "new filename" left-side decoration
    mUiGotoC  #$57               ; Go where the right-side decoration begins
    PEA.L    sAskReturnCancel(PC)  ; Part of the right-side decoration
    mUiPrint  <']',$0A,$0A,$0A>,s  ; Print right-side decoration
    mUiGotoR  (SP)+              ; Return to row with "new filename"

    ; Call the high-level UiTextInput routine; abort if user cancels
    PEA.L   zCatTextInput(PC)    ; Push our textinput config on the stack
    BSR     UiTextInput          ; Get the input from the user
    ADDQ.L  #$4,SP               ; Pop the textinput config off the stack
    BNE.S   .rt                  ; And on failure, give up straight away

    ; User said proceed, so copy the edited string on top of the original
    LEA.L   zCatTextInput(PC),A0   ; Point A0 at the textinput record
    PEA.L   kUITI_Text(A0)       ; Copy from the record's own string buffer
    MOVE.L  $8(SP),-(SP)         ; Copy to the argument location
    BSR     StrCpy255            ; Go copy the string
    ADDQ.L  #$8,SP               ; Pop the StrCpy255 arguments off the stack
    ORI.B   #$04,CCR             ; And set the Z flag to mark success

.rt RTS


* catalogue_ui Data -----------------------------


    SECTION kSecData


sAskTitleNew:
    DC.B    'New',$0
sAskTitleCopy:
    DC.B    'Copy',$0
sAskTitleRename:
    DC.B    'Rename',$0


sAskSubtitleCopy:
    DC.B    '    Copy from',$0
sAskSubtitleRename:
    DC.B    ' Old filename',$0


sAskOpFailedCreate:
    DC.B   $0A,'   Either a file with that name already exists, or ',$0
sAskOpFailedDelete:
    DC.B   $0A,'   Either no file with that name exists, or ',$0
sAskOpFailedComms:
    DC.B   'there was a problem telling the'
    DC.B   $0A,'   Cameo/Aphid what to do.',$0


sNewImageFilename:
    DC.B    'Untitled.image',$0


* catalogue_ui Scratch data ---------------------


    SECTION kSecScratch


    DS.W    $0                   ; Word alignment
    ; UiScrollingMenu record for the drive image catalogue menu
zCatMenu:
    DC.W    $5                   ; Menu top is on row 5
    DC.W    $3                   ; Menu left is on column 3
    DC.W    $1C                  ; The menu has 28 rows
    DC.W    $54                  ; The menu has 84 columns
    DC.W    $3                   ; Let's use a three-row scroll margin
    DC.W    $0                   ; Without initialisation, no menu items
    DC.W    $0                   ; Initial cursor position is 0
    DC.W    $0                   ; Initial scroll position is 0
    DC.L    $0                   ; Receives the address of CataloguePItem
    DC.L    $0                   ; Argument for CataloguePItem


    DS.W    $0                   ; Word alignment
    ; UiTextInput for filename queries -- includes 256 character buffer for
    ; strings; hope it won't make the program too big!
zCatTextInput:
    DC.B    $10                  ; Starting column is 16
    DC.B    $47                  ; The textbox is 71 characters wide
    DC.B    $5                   ; It has five character scroll margins
    DC.B    $0                   ; (Reserved for internal state)
    DC.W    $0                   ; Filenames have no reserved prefix
    DC.W    $6                   ; The ".image" suffix is protected, though
    DC.W    $FF                  ; Filenames are at most 255 characters long
    DC.W    $0                   ; To change: cursor position
    DC.W    $0                   ; To change: scroll position
    DC.W    $0                   ; To change: text length

    DS.B    $100                 ; Character buffer for string data
