* Cameo/Aphid disk image selector: UI routines for Cameo/Aphid configuration
* ==========================================================================
*
* Forfeited into the public domain with NO WARRANTY. Read LICENSE for details.
*
* Routines that provide interfaces for modifying various bits of Cameo/Aphid
* configuration, plus (awkwardly enough) a routine that displays system status
* information around the main window.
*
* These routines make use of data definitions set forth in selector.x68 and
* routines and other resources defined in ask_ui.x68, block.x68, config.x68,
* key_value.x68, narrated.x68, script.x68, lisa_ui/lisa_console_screen.x68,
* ui_base.x68, ui_psystem_menu.x68, and ui_textinput.x68. They also invoke
* macros defined in ui_macros.x68 and require that the lisa_profile_io library
* from the lisa_io collection be memory-resident.
*
* Public procedures:
*    - AskAutoboot -- Interactively set up or disable autobooting
*    - AskMoniker -- Interactively change the Cameo/Aphid moniker
*    - KeyValueEdit -- Interactive editor for key/value store entries
*    - DoSysInfo -- Load & display system info around the drive image catalogue


* config_ui Defines -----------------------------


kCuiBlockRd EQU  $FFFEFD00         ; ProFileIo command: read from magic block

    ; These constants are offsets into the "status" data block that
    ; profile_plugin_FFFEFD_system_info.py returns to reads of block $FFFEFD.
    ; All of these values are ASCII digits
kCuiIDays   EQU  $0                ; Uptime days (4 chars)
kCuiIHours  EQU  $4                ; Uptime hours (2 chars)
kCuiIMins   EQU  $6                ; Uptime minutes (2 chars)
kCuiISecs   EQU  $8                ; Uptime seconds (2 chars)

kCuiIFree   EQU  $A                ; Filesystem bytes free (15 chars)

kCuiILoad1  EQU  $19               ; 1m load average (null-terminated)
kCuiILoad5  EQU  $20               ; 5m load average (null-terminated)
kCuiILoad15 EQU  $27               ; 15m load average (null-terminated)

kCuiIProcR  EQU  $2E               ; Running processes (null-terminated)
kCuiIProcT  EQU  $33               ; Total processes (null-terminated)


* config_ui Code --------------------------------


    SECTION kSecCode


    ; AskAutoboot -- Interactively set up or disable autobooting
    ; Args:
    ;   SP+$4: Address of a null-terminated filename string, required even if
    ;       the user intends to disable autobooting
    ;   zConfig: Pre-loaded configuration data structure
    ; Notes:
    ;   Trashes D0-D1/A0-A1; mutates zConfig, changes config on the Cameo/Aphid
AskAutoboot:
    BSR     ClearLisaConsoleScreen   ; Blank the screen
    mUiPrint  r1c1,<'{ Autoboot setup }',$0A,$0A,'   '>

    ; Is autoboot already enabled? It changes what we ask the user...
    MOVE.L  $4(SP),-(SP)           ; Copy filename string on the stack
    mUiPrint  s,<$0A,$0A,' '>      ; Print it
    PEA.L   zConfig(PC)            ; Push config record address onto the stack
    MOVE.W  #kC_FBScript,-(SP)     ; Interrogate the autoboot feature bit
    BSR     ConfFeatureTest        ; Was autoboot enabled?
    ADDQ.L  #$6,SP                 ; Pop arguments off the stack
    BEQ.S   .ad                    ; No, disabled, skip ahead
    mUiPrint  <'T',$28,'urn off autoboot, '>
.ad mUiPrint  <'S',$28,'et autoboot to this file, or C',$28,'ancel?',$0A,$0A,' '>

    ; ...but not how we interpret their keypresses :-)
.lp BSR     LisaConsoleWaitForKbMouse  ; Await a keypress
    BNE.S   .lp                    ; Loop if it wasn't a keypress
    PEA.L   .km(PC)                ; The key-interpreting table for UiPSystemKey
    MOVE.B  zLisaConsoleKbChar(PC),-(SP)   ; Push the key we read onto the stack
    BSR     UiPSystemKey           ; Go interpret the key
    ADDQ.L  #$6,SP                 ; Pop the UiPSystemKey arguments
    BNE.S   .lp                    ; Loop if user typed a nonsense key
    JMP     (A0)                   ; Jump as directed by the menu selection

    ; Menu handler for disabling autoboot
.mt PEA.L   zConfig(PC)            ; Push config record address onto the stack
    MOVE.W  #kC_FBScript,-(SP)     ; We want to clear the autoboot feature bit
    BSR     ConfFeatureClear       ; Clear it!
    ADDQ.L  #$2,SP                 ; Pop the second argument off the stack
    BSR     NConfPut               ; Write the config to the Cameo/Aphid
    ADDQ.L  #$4,SP                 ; Pop the config record address off the stack
    BSR     AskVerdictByZ          ; Say whether things worked out
    RTS

    ; Menu handler for setting or changing autoboot
.ms MOVE.L  $4(SP),-(SP)           ; Copy image filename address on the stack
    BSR     NMakeBasicBootScript   ; Set up a boot script for this filename
    ADDQ.L  #$4,SP                 ; Pop the filename address off the stack
    BNE.S   .rt                    ; Jump to return if it didn't work
    PEA.L   zConfig(PC)            ; Push config record address onto the stack
    MOVE.W  #kC_FBScript,-(SP)     ; We want to set the autoboot feature bit
    BSR     ConfFeatureSet         ; Set it!
    ADDQ.L  #$2,SP                 ; Pop the second argument off the stack
    BSR     NConfPut               ; Write the config to the Cameo/Aphid
    ADDQ.L  #$4,SP                 ; Pop the config record address off the stack
.rt BSR     AskVerdictByZ          ; Say whether things worked out
    RTS

    ; Menu handler for cancelling changes to autoboot
.mc PEA.L   sAskVerdictCancelled(PC)   ; We'll say the operation was cancelled
    BSR     AskVerdict             ; Go say it and await a keypress
    ADDQ.L  #$4,SP                 ; Pop off the address of "cancelled"
    RTS

    DS.W    0                      ; Word alignment
.km DC.B    $01,'T'
    DC.W    (.mt-.km)              ; Action for T: disable autoboot
    DC.B    $01,'S'
    DC.W    (.ms-.km)              ; Action for S: set autoboot
    DC.B    $01,'C'
    DC.W    (.mc-.km)              ; Action for C: cancel and return
    DC.W    $0000                  ; Table terminator


    ; AskMoniker -- Interactively change the Cameo/Aphid moniker
    ; Args:
    ;   zConfig: Pre-loaded configuration data structure
    ; Notes:
    ;   Trashes D0-D2/A0-A2
AskMoniker:
    ; Prepare the user interface
    BSR     ClearLisaConsoleScreen   ; Blank the screen
    mUiPrint  r1c1,<'{ Change moniker }',$0A,$0A,' Moniker: ['>
    MOVE.W  zRowLisaConsole(PC),-(SP)  ; Save current row on the stack
    mUiGotoC  #$1A                 ; Go where the right-side decoration begins
    PEA.L   sAskReturnCancel(PC)   ; Part of the right-side decoration
    mUiPrint  <']',$0A,$0A,$0A>,s  ; Print right-side decoration
    mUiGotoR  (SP)+                ; Return to row with "Moniker:"

    ; Prepare the text editing infrastructure for the moniker field
    LEA.L   zConTextInput(PC),A1   ; Point A1 at the UiTextInput data structure
    MOVE.B  #$B,kUITI_Start(A1)    ; The textbox starts at column 11
    MOVE.B  #$F,kUITI_Width(A1)    ; The textbox is 15 characters wide
    MOVE.W  #$F,kUITI_Max(A1)      ; The string may be at max 15 characters

    PEA.L   zConfig(PC)            ; Push zConfig address onto the stack
    BSR     ConfMonikerGet         ; Now A0 points at the current moniker
    ADDQ.L  #$4,SP                 ; Pop zConfig address off of the stack
    MOVE.L  A0,-(SP)               ; Push moniker address onto the stack
    PEA.L   kUITI_Text(A1)         ; Push the editable text address too
    MOVE.W  #$10,-(SP)             ; Copy (up to 15) chars plus terminator
    BSR     Copy                   ; Copy the moniker text
    ADDQ.L  #$6,SP                 ; Pop last two Copy arguments
    MOVE.L  (SP)+,A0               ; And reuse the first to point A0 at moniker

    MOVEQ.L #-1,D0                 ; We'll count the moniker strlen here
.lp ADDQ.W  #$1,D0                 ; Increment character count
    TST.B   (A0)+                  ; Have we hit the terminator yet?
    BNE.S   .lp                    ; No, keep looping

    LEA.L   zConTextInput(PC),A1   ; Point A1 at the UiTextInput data structure
    MOVE.W  D0,kUITI_Len(A1)       ; Register the length of the string
    MOVE.W  D0,kUITI_CPos(A1)      ; Set cursor position at end of string

    ; Call the high-level UiTextInput routine; abort if user cancels
    MOVE.L  A1,-(SP)               ; Push our textinput config on the stack
    BSR     UiTextInput            ; Get the input from the user
    MOVEA.L (SP)+,A0               ; Move textinput config off stack and into A0
    BNE.S   .no                    ; Did the user cancel? Skip ahead to quit
    TST.B   kUITI_Text(A0)         ; Did the user enter the empty string?
    BEQ.S   .no                    ; Skip ahead to quit

    ; Copy the new moniker into the config and write the config
    PEA.L   zConfig(PC)            ; Push the address of the config structure
    PEA.L   kUITI_Text(A0)         ; Push the address of the new moniker
    BSR     ConfMonikerSet         ; Update the config
    ADDQ.L  #$4,SP                 ; Pop new moniker address off the stack
    mUiGotoRC  #$6,#$0             ; Move cursor to a where NConfPut can speak
    BSR     NConfPut               ; Write the config to the Cameo/Aphid
    ADDQ.L  #$4,SP                 ; Pop config structure address off the stack
    BSR     AskVerdictByZ          ; Say whether things worked out
    BRA.S   .rt                    ; Jump ahead to return

    ; If here, the user has cancelled the operation
.no PEA.L   sAskVerdictCancelled(PC)   ; We'll say the operation was cancelled
    BSR     AskVerdict             ; Go say it and await a keypress
    ADDQ.L  #$4,SP                 ; Pop off the address of "cancelled"

.rt RTS


    ; KeyValueEdit -- Interactive editor for key/value store entries
    ; Args:
    ;   (none)
    ; Notes:
    ;   This editor is basically only good for editing key/value pairs that
    ;       consist only of keyboard characters; anyone who uses this to edit
    ;       their Cameo/Aphid config will shoot themselves in the foot!
    ;   This editor treats editing values like editing a sequence of eight
    ;       64-character strings; if the user supplies a shorter string in one
    ;       of the text boxes, then the null terminator and any trailing
    ;       garbage for the respective 64-character portion will wind up in
    ;       the value data
    ;   That said, a null terminator that comes after a full 64 characters will
    ;       not be copied into value data
    ;   Trashes D0-D2/A0-A2 and the zBlock disk block buffer
KeyValueEdit:
    ; Prepare zBlock as a key/value store load request with one entry
    PEA.L   zBlock(PC)             ; Push the address of the start of zBlock
    BSR     KeyValueLoadReqClear   ; Intialise this load request record
    ADDQ.L  #$4,SP                 ; Pop zBlock address off the stack

    ; Prepare the display
    BSR     ClearLisaConsoleScreen   ; Blank the screen
    mUiPrint  r1c1,<'{ Key/value store editor }',$0A,$0A,'       Key: ['>
    MOVE.W  zRowLisaConsole(PC),-(SP)  ; Save current row on the stack
    mUiGotoC  #$21                 ; Go where the right-side decoration begins
    PEA.L   sAskReturnCancel(PC)   ; Part of the right-side decoration
    mUiPrint  <']',$0A,$0A,$0A>,s  ; Print right-side decoration
    mUiGotoR  (SP)+                ; Return to row with "Key:"

    ; Prepare the text editing infrastructure for the key field
    LEA.L   zConTextInput(PC),A0   ; Point A0 at the UiTextInput data structure
    MOVE.B  #$D,kUITI_Start(A0)    ; The textbox starts at column 13
    MOVE.B  #$14,kUITI_Width(A0)   ; The textbox is 20 characters wide
    MOVE.W  #$14,kUITI_Max(A0)     ; The string may be at max 20 characters
    CLR.W   kUITI_CPos(A0)         ; The cursor starts at position 0
    CLR.W   kUITI_Len(A0)          ; The string initially has no characters
    PEA.L   kUITI_Text(A0)         ; Push text scratch area address onto stack
    MOVE.W  #$15,-(SP)             ; We want to zero out 21 characters
    BSR     Zero                   ; Zero them out
    ADDQ.L  #$6,SP                 ; Pop Zero arguments

    ; Call the high-level UiTextInput routine; abort if user cancels
    PEA.L   zConTextInput(PC)      ; Push our textinput config onto the stack
    BSR     UiTextInput            ; Get the input from the user
    MOVEA.L (SP)+,A0               ; Move textinput config off stack and into A0
    BNE     .no                    ; Did the user cancel? Skip ahead to quit
    TST.B   kUITI_Text(A0)         ; Did the user enter the empty string?
    BEQ     .no                    ; Skip ahead to quit

    ; Copy the user's key into the load request we're building into zBlock
    PEA.L   zBlock(PC)             ; Push zBlock address onto the stack
    PEA.L   kUITI_Text(A0)         ; Push the address of the user's key string
    CLR.W   -(SP)                  ; Push $0 as cache key; we'll change it later
    BSR     KeyValueLoadReqPush    ; Do the copy
    ADDQ.L  #$8,SP                 ; Pop KeyValueLoadReqPush arguments, part 1
    ADDQ.L  #$2,SP                 ; Pop KeyValueLoadReqPush arguments, part 2

    ; Prepare the text editing infrastructure for the cache key field
    mUiPrint  <$0A,' Cache key: [  ]'>
    LEA.L   zConTextInput(PC),A0   ; Point A0 at the UiTextInput data structure
    MOVE.B  #$2,kUITI_Width(A0)    ; The textbox is 2 characters wide
    MOVE.W  #$2,kUITI_Max(A0)      ; The string may be at max 2 characters
    CLR.W   kUITI_CPos(A0)         ; The cursor starts at position 0
    CLR.W   kUITI_Len(A0)          ; The string initially has no characters
    CLR.L   kUITI_Text(A0)         ; Clear out both characters and a bit more

    ; Call the high-level UiTextInput routine; abort if user cancels
    PEA.L   zConTextInput(PC)      ; Push our textinput config onto the stack
    BSR     UiTextInput            ; Get the input from the user
    MOVEA.L (SP)+,A0               ; Move textinput config off stack and into A0
    BNE     .no                    ; Did the user cancel? Skip ahead to quit
    TST.B   kUITI_Text(A0)         ; Did the user enter the empty string?
    BEQ     .no                    ; Skip ahead to quit

    ; Put user-specified cache key in the load request and save for later
    MOVE.W  kUITI_Text(A0),D0      ; Copy the key into D0
    LEA.L   zConCacheKey(PC),A1    ; Here's where we want to save it
    MOVE.W  D0,(A1)                ; Go save it
    ; TODO: Don't reach in and modify the cache request ourselves!
    LEA.L   zBlock(PC),A1          ; Point A1 at zBlock
    MOVE.B  D0,$2(A1)              ; Put 2nd byte of cache key in cache request
    LSR.W   #$8,D0                 ; Shift in first byte of cache key
    MOVE.B  D0,$1(A1)              ; Put 1st byte of cache key in cache request

    ; Try to execute the cache request and then load the cached data
    BSR     _ClearStatusLine       ; Clear status line; prepare to write there
    PEA.L   zBlock(PC)             ; Push zBlock address onto the stack
    BSR     NKeyValueLoad          ; Try to refresh the key/value cache
    ADDQ.L  #$4,SP                 ; Pop zBlock address off the stack
    BEQ.S   .cr                    ; On success, try reading data from cache
    BSR     AskVerdictByZ          ; Otherwise, say that things failed
    BRA     .rt                    ; Jump ahead to return
.cr BSR     _ClearStatusLine       ; Clear status line; prepare to write there
    MOVE.W  zConCacheKey(PC),-(SP)   ; Here's the cache key we want to read
    BSR     NKeyValueRead          ; Try to read it into zBlock
    ADDQ.L  #$2,SP                 ; Pop the cache key off the stack
    BEQ.S   .ed                    ; On success, jump ahead to the editor
    BSR     AskVerdictByZ          ; Otherwise, say that things failed
    BRA     .rt                    ; Jump ahead to return

    ; Here, the main editing loop
.ed BSR     _DispKvEditor          ; Jump to draw the editor
    BSR     FlushCops              ; Dump out the keyboard buffer
    PEA.L   .ek(PC)                ; The key-interpreting table for UiPSystemKey
.el BSR     LisaConsoleWaitForKbMouse  ; Await a keypress
    BNE.S   .el                    ; Loop if it wasn't a keypress
    MOVE.B  zLisaConsoleKbChar(PC),D0  ; Copy user keypress to D0
    CMPI.B  #'1',D0                ; If the keypress is less than 1...
    BLO.S   .ep                    ; ...then interpret it conventionally
    CMPI.B  #'8',D0                ; But if it's in [12345678]...
    BHI.S   .ep                    ; ...then we need to edit a row...
    ADDQ.L  #$4,SP                 ; ...so pop args off of the stack...
    BRA.S   .er                    ; ...and go edit it
.ep MOVE.B  D0,-(SP)               ; Push the key we read onto the stack
    BSR     UiPSystemKey           ; Go interpret the key
    ADDQ.L  #$2,SP                 ; Pop the key we read off the stack
    BNE.S   .el                    ; Loop if user typed a nonsense key
    ADDQ.L  #$4,SP                 ; Pop the table address off of the stack
    JMP     (A0)                   ; Jump as directed by the menu selection

    ; If here, we're editing an individual row
.er SUB.B   #'1',D0                ; Should now be a number in [0,7]
    EXT.W   D0                     ; Which makes it safe to word-extend this way
    MOVE.W  D0,-(SP)               ; Save that row number on the stack

    BSR     _ClearStatusLine       ; Clear status line; prepare to write there
    mUiGotoR  #$6                  ; But actually move to the status line
    PEA.L   sAskReturnCancel(PC)   ; Push editing directions onto the stack
    mUiPrint  s                    ; And print them

    MOVE.W  (SP),D0                ; Recover row to edit into D0
    LSL.W   #$6,D0                 ; Multiply row index by row size (64)
    LEA.L   zBlockData(PC),A0      ; Point A0 at the value data
    PEA.L   $0(A0,D0.W)            ; We want to edit this row of it
    LEA.L   zConTextInput(PC),A0   ; Point A0 at our TextInput record
    PEA.L   kUITI_Text(A0)         ; Push storage area for text being edited
    MOVE.W  #$40,-(SP)             ; We want to copy 64 bytes
    BSR     Copy                   ; Do the copy
    ADDQ.L  #$2,SP                 ; Pop Copy arguments, part 1
    ADDQ.L  #$8,SP                 ; Pop Copy arguments, part 2
    LEA.L   zConTextInput(PC),A0   ; Point A0 at the value data
    CLR.B   (kUITI_Text+$40)(A0)   ; Null-terminate the text buffer just in case

    MOVE.B  #$D,kUITI_Start(A0)    ; The textbox starts at column 13
    MOVE.B  #$40,kUITI_Width(A0)   ; The textbox is 64 characters wide
    MOVE.B  #$40,kUITI_Max(A0)     ; The text can be no longer than 64 chars
    CLR.W   kUITI_CPos(A0)         ; The cursor starts at position 0
    MOVEQ.L #-1,D0                 ; How long is the editable part of the text?
.sl ADDQ.W  #$1,D0                 ; D0 will count the string length
    TST.B   kUITI_Text(A0,D0.W)    ; Are we at the terminator?
    BNE.S   .sl                    ; If not, keep going
    MOVE.W  D0,kUITI_Len(A0)       ; If so, then D0 is the length of the text

    MOVE.W  (SP),D0                ; Recover row to edit into D0
    ADDQ.W  #$8,D0                 ; Turn it into a screen row
    mUiGotoR  D0                   ; Move the cursor there
    PEA.L   zConTextInput(PC)      ; Push our textinput config on the stack
    BSR     UiTextInput            ; Get the input from the user
    MOVEA.L (SP)+,A0               ; Move textinput config off stack and into A0
    BNE.S   .ez                    ; User cancel? Jump, return to main edit loop

    MOVE.W  (SP),D0                ; Recover row to edit into D0
    LSL.W   #$6,D0                 ; Multiply row index by row size (64)
    PEA.L   kUITI_Text(A0)         ; Push storage area for text that was edited
    LEA.L   zBlockData(PC),A0      ; Point A0 at the value data
    PEA.L   $0(A0,D0.W)            ; Here's where to deposit the edited text
    MOVE.W  #$40,-(SP)             ; 64 bytes of it
    BSR     Copy                   ; Do the copy
    ADDQ.L  #$8,SP                 ; Pop args to Copy, part 1
    ADDQ.L  #$2,SP                 ; Pop args to Copy, part 2

.ez ADDQ.L  #$2,SP                 ; Pop row number off of the stack
    BRA     .ed                    ; Back up to the main editing loop

    DS.W    0                      ; Word alignment
    ; UiPSystemKey table for the main editing loop
.ek DC.B    $01,'W'
    DC.W    (.wr-.ek)              ; Action for W: update the key/value entry
    DC.B    $01,'C'
    DC.W    (.no-.ek)              ; Action for C: cancel and return
    DC.W    $0000                  ; Table terminator

    ; If here, we're fixing to write the entry and return to the caller
.wr BSR     _ClearStatusLine       ; Clear status line; prepare to write there
    mUiPrint  <$0A,' Replace bytes 1FE-1FF with a checksum before writing? (Y/N)'> 
    BSR     FlushCops              ; Dump out the keyboard buffer
    PEA.L   .wk(PC)                ; The key-interpreting table for UiPSystemKey
.wl BSR     LisaConsoleWaitForKbMouse  ; Await a keypress
    BNE.S   .wl                    ; Loop if it wasn't a keypress
    MOVE.B  zLisaConsoleKbChar(PC),-(SP)   ; Push user keypress onto the stack
    BSR     UiPSystemKey           ; Go interpret the key
    ADDQ.L  #$2,SP                 ; Pop the key we read off the stack
    BNE.S   .wl                    ; Loop if user typed a nonsense key
    ADDQ.L  #$4,SP                 ; Pop the table address off of the stack
    JMP     (A0)                   ; Jump as directed by the menu selection

.wc PEA.L   zBlockData(PC)         ; Push address of the value data
    BSR     BlockCsumSet           ; Compute the checksum of the value data
    ADDQ.L  #$4,SP                 ; Pop the value data address off the stack
.wp BSR.S   _ClearStatusLine       ; Clear status line; prepare to write there
    PEA.L   zBlockTag(PC)          ; Push address of the key data
    PEA.L   zBlockData(PC)         ; Push address of the value data
    MOVE.W  zConCacheKey(PC),-(SP)   ; Push the cache key we want to write
    BSR     NKeyValuePut           ; Write to the key/value store
    ADDQ.L  #$8,SP                 ; Pop NKeyValuePut args, part 1
    ADDQ.L  #$2,SP                 ; Pop NKeyValuePut args, part 2
    BSR     AskVerdictByZ          ; Say whether that worked
    BRA.S   .rt                    ; Skip ahead to return

    DS.W    0                      ; Word alignment
    ; UiPSystemKey table for the 
.wk DC.B    $01,'Y'
    DC.W    (.wc-.wk)              ; Action for Y: compute a checksum first
    DC.B    $01,'N'
    DC.W    (.wp-.wk)              ; Action for N: go straight to writing
    DC.W    $0000                  ; Table terminator

    ; If here, the user has cancelled the operation
.no PEA.L   sAskVerdictCancelled(PC)   ; We'll say the operation was cancelled
    BSR     AskVerdict             ; Go say it and await a keypress
    ADDQ.L  #$4,SP                 ; Pop off the address of "cancelled"

.rt RTS

    ; _ClearStatusLine -- Clear the KeyValueEdit status line
    ; Args:
    ;   (none)
    ; Notes:
    ;   Cursor moves to the row ABOVE the status line since many routines
    ;       print a $0A prior to the line they want to show there
    ;   Trashes D0-D1/A0-A1
_ClearStatusLine:
.sl mUiClearBox   #$6,#$0,#$1,#$5A   ; Clear status line
    mUiGotoRC   #$5,#$0            ; Go to row 5, column 0
    RTS

    ; _DispKvEditor -- Draw the key-value editor for KeyValueEdit
    ; Args:
    ;   (none)
    ; Notes:
    ;   Trashes D0-D1/A0-A1
_DispKvEditor:
    BSR.S   _ClearStatusLine       ; Clear the status line
    PEA.L   sCuiEditUi(PC)         ; Push address of (much of) the editor UI
    mUiPrint  s                    ; Print it
    mUiGotoR  #$7                  ; Move cursor to row 7
    MOVEM.L D2/A2,-(SP)            ; Preserve D2 and A2 on the stack

    LEA.L   zBlockData(PC),A2      ; Point A2 at the beginning of value data
.do LEA.L   zRowLisaConsole(PC),A0   ; Point A0 at current screen row counter
    ADDQ.W  #$1,(A0)               ; And increment it
    CMPI.W  #$10,(A0)              ; Is the row greater than or equal to 16?
    BHS.S   .rt                    ; Then we're done
    mUiGotoC  #$D                  ; Move cursor horizontally to column 13
    MOVEQ.L #$3F,D2                ; Repeat 64 times...
.di mUiPutc (A2)+                  ; ...print the next character...
    DBRA    D2,.di                 ; ...in the value data
    mUiPutc #']'                   ; Decorate the right hand side of the row
    BRA.S   .do                    ; Then draw the next row

.rt MOVEM.L (SP)+,D2/A2            ; Recover D2 and A2 from the stack
    RTS


    ; DoSysInfo -- Load & display system info around the drive image catalogue
    ; Args:
    ;   (none)
    ; Notes:
    ;   Trashes D0-D1/A0-A1 and the zBlock disk block buffer
DoSysInfo:
    ; Print the "Filename" header
    mUiGotoRC   #$3,#$3            ; Which lives at row 3, column 3
    mUiPrint  <'Filename'>

    ; Next, read the "magic block" that contains system status into zBlock
    MOVE.L  #kCuiBlockRd,D1        ; We wish to read our "magic" block
    ; Retry count+sparing threshold don't matter, so we don't worry about D2
    LEA.L   zBlock(PC),A0          ; We want to read into the block buffer
    MOVEA.L zProFileIoPtr(PC),A1   ; Copy ProFile I/O routine address to A1
    JSR     (A1)                   ; Call it
    BNE     .rt                    ; On failure, just return silently

    ; It worked, so print status information, starting with uptime and load
    MOVEM.L A2-A3,-(SP)            ; Save A2 and A3 on the stack
    LEA.L   zBlock(PC),A2          ; Point A2 at the block buffer
    mUiGotoRC   #$22,#$3           ; Here's where that status line begins
    mUiPrint  <'Cameo/Aphid up '>

    MOVEQ.L #$2,D0                 ; For cosmetics: find the front of Days
.dl CMPI.B  #$20,kCuiIDays(A2,D0.W)  ; Is this character a space?
    DBEQ    D0,.dl                 ; No, keep searching backwards
    ADDQ.W  #$1,D0                 ; D0 now indexes the first non-space
    MOVEQ.L #$4,D1                 ; How many days digits do we need to print?
    SUB.W   D0,D1                  ; It's 4 minus the number of spaces
    LEA.L   kCuiIDays(A2,D0.W),A3  ; Load the calculated start of Days into A3
    mUiPrintStrN  D1,A3            ; And print the Days

    mUiPrint  <'d '>
    LEA.L   kCuiIHours(A2),A3      ; We ran this many hours
    mUiPrintStrN  #$2,A3
    BSR     .cl
    ADDQ.L  #$2,A3                 ; We ran this many minutes
    mUiPrintStrN  #$2,A3
    BSR     .cl
    ADDQ.L  #$2,A3                 ; We ran this many seconds
    mUiPrintStrN  #$2,A3
    mUiPrint  <', load average '>
    PEA.L   kCuiILoad1(A2)         ; Our 1-minute load average
    mUiPrint  s
    BSR     .cs
    PEA.L   kCuiILoad5(A2)         ; Our 5-minute load average
    mUiPrint  s
    BSR     .cs
    PEA.L   kCuiILoad15(A2)        ; Our 15-minute load average
    mUiPrint  s,<', processes '>
    PEA.L   kCuiIProcT(A2)         ; Number of total processes
    mUiPrint  s
    BSR     .cl
    PEA.L   kCuiIProcR(A2)         ; Number of running processes
    mUiPrint  s,<'      '>         ; Spaces in lieu of clearing the full line

    ; Continue by printing the filesystem size
    mUiGotoRC   #$3,#$39           ; Where we print the filesystem size
    LEA.L   kCuiIFree(A2),A3       ; Point A3 at the beginning of the size
.sl mUiPrintStrN  #$3,A3           ; Print three digits of the filesystem size
    MOVE.W  zColLisaConsole(PC),D0   ; Load current column into D0
    CMPI.W  #$4C,D0                ; At the last column for printing size?
    BHS.S   .sx                    ; If so, we're done printing size
    ADDQ.L  #$3,A3                 ; Advance A3 by three digits
    CMPI.B  #' ',-1(A3)            ; Was the last digit printed a space?
    BEQ.S   .ss                    ; If so, jump to print a space
    mUiPutc #$2C                   ; If not, print a comma
    BRA.S   .sl                    ; Loop to print more digits
.ss mUiPutc #$20                   ; Print a space
    BRA.S   .sl                    ; Loop to print more digits

.sx MOVEM.L (SP)+,A2-A3            ; Restore A2 and A3 from the stack
    mUiPrint  <' bytes free'>      ; Suffix to filesystem size
.rt RTS

    ; Helper: print a comma and a space
.cs mUiPrint  <', '>
    RTS

    ; Helper: print a colon
.cl mUiPutc   #':'
    RTS


* config_ui Data --------------------------------


    SECTION kSecData


sCuiEditUi:
    DC.B    $0A,' Edit which row (1-8), W(rite to the key/value store,'
    DC.B    ' or C(ancel?',$0A,$0A,' 1: 000-03F [',$0A,' 2: 040-07F [',$0A
    DC.B    ' 3: 080-0BF [',$0A,' 4: 0C0-0FF [',$0A,' 5: 100-13F [',$0A
    DC.B    ' 6: 140-17F [',$0A,' 7: 180-1BF [',$0A,' 8: 1C0-1FF [',$00


* config_ui Scratch data ------------------------


    SECTION kSecScratch


    DS.W    $0                   ; Word alignment
zConCacheKey:
    DC.W    $0000                ; Temporary storage for a key/value cache key


    ; UiTextInput for configuration changes -- includes 64-character buffer for
    ; strings; hope it won't make the program too big!
zConTextInput:
    DC.B    $FF                  ; Starting column is UNISET
    DC.B    $FF                  ; Textbox width is UNSET
    DC.B    $0                   ; It has no scroll margins (we don't scroll)
    DC.B    $0                   ; (Reserved for internal state)
    DC.W    $0                   ; There is no protected prefix
    DC.W    $0                   ; There is no protected suffix
    DC.W    $FFFF                ; String max width is UNSET (should be <= 65)
    DC.W    $0                   ; To change: cursor position
    DC.W    $0                   ; Scroll position is 0 and never changes
    DC.W    $0                   ; To change: text length

    DS.B    $40                  ; Character buffer for string data
    DC.W    $0                   ; Precautionary null terminator and padding
