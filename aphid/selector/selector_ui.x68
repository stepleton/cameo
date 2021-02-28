* Cameo/Aphid disk image selector: Main user interface
* ====================================================
*
* Forfeited into the public domain with NO WARRANTY. Read LICENSE for details.
*
* Routines for presenting the main user interface, as implemented in four
* nested loops, viz:
*
*   ** Primary loop (Interface):
*      - Check that attached device is a Cameo/Aphid
*        - If not, scan for Cameo/Aphids, allow user to choose one
*      - If here, it's an Aphid, read its configuration
*      - Then update the drive catalogue
*     ** Secondary loop (_IF_Secondary):
*        - Update the drive image catalogue
*        - Clear screen
*        - Draw the disk image menu
*       ** Tertiary loop (_IF_Tertiary):
*          - Draw the command menu at the top of the screen
*          - Empty keyboard buffer
*         ** Inner loop (_IF_Quarternary):
*            - Retrieve and draw status info from Cameo/Aphid
*            - Get keyboard input
*            - If a command, clear screen and run, then restart primary loop
*            - If a menu interaction, do a menu thing
*
* Public procedures:
*    - Interface -- Main user interface loop; never returns


* selector_ui Code ------------------------------


    SECTION kSecCode


    ; Interface -- Main user interface loop; never returns
    ; Args:
    ;   (none)
    ; Notes:
    ;   Most of this code is actually a menu for changing the currently selected
    ;       parallel port
    ;   Precondition: zCurrentDrive must be initialised; prior to calling this
    ;       routine, call HelloBootDrive to initialise the minimum functionality
    ;       of drive.x68
    ;   Never returns (so you can BRA here); can jump to the ROM monitor though
Interface:
    BSR     ClearLisaConsoleScreen   ; Blank the screen
    mUiPrint  r1c0                 ; Move cursor down from top of screen
    BSR     NCameoAphidCheck       ; Is this a Cameo/Aphid?
    BNE.S   .no                    ; No, jump ahead to choose a device
    BSR     NConfLoad              ; Load up its key/value cache
    BNE.S   .no                    ; No, jump ahead to choose a device

    PEA.L   zConfig(PC)            ; Push config structure address
    BSR     NConfRead              ; Read in the config structure
    BEQ.S   .ca                    ; Success? Jump to check its integrity
    ADDQ.L  #$4,SP                 ; Failed, pop config structure address
    BRA.S   .no                    ; And jump ahead to choose a device
.ca BSR     ConfIsOk               ; Is the configuration OK?
    BEQ.S   .go                    ; Yes, go enter the secondary loop
    BSR     Conf1New               ; No, initialise a new config structure
.go ADDQ.L  #$4,SP                 ; Pop config structure address
    BSR     _IF_Secondary          ; Enter nested loop
    BEQ     .cd                    ; Return with Z set means choose a new device

    ; Otherwise, if we're here, the user chose to quit: exit to the ROM
.ex BSR     ClearLisaConsoleScreen   ; Blank the screen
    mUiPrint  r1c1,<'Bye!'>        ; Since exiting to ROM takes a little while
    CLR.L   D0                     ; Display no error code to the user
    SUBA.L  A2,A2                  ; There is no icon to show
    LEA.L   sSuiBye(PC),A3         ; But there is this message
    JMP     $FE0084                ; Return to the ROM monitor; bye!

    ; If here, the current device wasn't a Cameo/Aphid; say so
.no BSR     CurrentDriveParallel   ; Is the current device a parallel port?
    BEQ.S   .pp                    ; Yes, move ahead
    mUiPrint  <$0A,$0A,' This program isn',$27,'t connected to any parallel port.',$0A>
    BRA     .cs
.pp mUiPrint  <$0A,$0A,' The current port ('>
    MOVE.B  zCurrentDrive(PC),-(SP)  ; Parallel port identifier to stack
    ORI.B   #$80,(SP)                ; Set bit for "the"
    BSR     PrintParallelPort        ; Print he parallel port name
    ADDQ.L  #$2,SP                   ; Pop parallel port identifier off stack
    mUiPrint  <') hasn',$27,'t got a Cameo/Aphid attached.',$0A>
    BRA.S   .cs

    ; If here, the user wanted to choose a different device
.cd BSR     ClearLisaConsoleScreen   ; Blank the screen
    mUiPrint  r1c0,<' { Choose parallel port }',$0A>

    ; Scan for devices, make a menu of devices to choose, and get a choice
.cs BSR     NUpdateDriveCatalogue  ; Scan for connected Cameo/Aphid devices

    MOVE.W  D2,-(SP)               ; Save D2 on the stack for the following
    MOVE.W  #-kDrive_NEXT,D0       ; This will be an offset into zDrives
    CLR.W   D1                     ; Here's how many Cameo/Aphids there are
    MOVE.B  #'0',D2                ; Initialise menu option key

.cl LEA.L   zDrives(PC),A0         ; (Re)point A0 at zDrives
    ADD.W   #kDrive_NEXT,D0        ; Advance the zDrives offset
    ADDQ.B  #$1,D2                 ; Increment menu option key
    TST.B   kDrive_ID(A0,D0.W)     ; Done with the scan?
    BEQ.S   .cc                    ; If so, onward to choosing
    TST.B   kDrive_Aphd(A0,D0.W)   ; Does this port have a Cameo/Aphid attached?
    BEQ.S   .cl                    ; No, on to the next port
    ADDQ.W  #$1,D1                 ; Yes, bump up the Cameo/Aphid count

    MOVEM.W D0-D1/A0,-(SP)         ; Save registers on the stack before printing
    mUiPrint  <$0A,' ('>           ; Print option key
    mUiPutc D2
    mUiPrint  <') '>
    MOVEM.W (SP),D0-D1/A0          ; Restore registers that printing trashed
    MOVE.B  kDrive_ID(A0,D0.W),-(SP)   ; Push drive ID on the stack
    ORI.B   #$40,(SP)              ; Turn on PrintParallelPort capitalisation
    BSR     PrintParallelPort      ; Print the name of the parallel port
    ADDQ.L  #$2,SP                 ; Pop drive ID off the stack
    MOVEM.W (SP),D0-D1/A0          ; Restore registers that printing trashed
    PEA.L   kDrive_Mnkr(A0,D0.W)   ; Push moniker address on the stack
    mUiPrint  <': "'>,s,<'"'>      ; Print the Cameo/Aphid's moniker; also pops
    MOVEM.W (SP)+,D0-D1/A0         ; Restore and pop registers fom the stack

    BRA     .cl                    ; On to the next drive

.cc MOVE.W  (SP)+,D2               ; Recover D2 from the stack before moving on
    TST.W   D1                     ; Are there any Cameo/Aphids at all?
    BEQ     .cx                    ; If not, skip ahead to complain

    mUiPrint  <$0A,$0A,' Please select a parallel port by number.'>
.cm BSR     UiScreensaverWaitForKb   ; Await a keypress
    BNE     .cd                    ; Back to top if it wasn't a keypress
    PEA.L   .ct(PC)                ; The key-interpreting table for UiPSystemKey
    MOVE.B  zLisaConsoleKbChar(PC),-(SP)   ; Push the key we read onto the stack
    BSR     UiPSystemKey           ; Go interpret the key
    ADDQ.L  #$2,SP                 ; Pop the key we read off the stack
    BNE.S   .cm                    ; Loop if user typed a nonsense key
    ADDQ.L  #$4,SP                 ; Pop the table address off of the stack
    JMP     (A0)                   ; Jump as directed by the menu selection

.c1 MOVE.B  #$02,-(SP)             ; Select the internal parallel port
    BRA.S   .cz                    ; Jump ahead to select it
.c2 MOVE.B  #$03,-(SP)             ; Select the slot 1 lower port
    BRA.S   .cz                    ; Jump ahead to select it
.c3 MOVE.B  #$04,-(SP)             ; Select the slot 1 upper port
    BRA.S   .cz                    ; Jump ahead to select it         Eh, could
.c4 MOVE.B  #$06,-(SP)             ; Select the slot 2 lower port     be more
    BRA.S   .cz                    ; Jump ahead to select it          compact,
.c5 MOVE.B  #$07,-(SP)             ; Select the slot 2 upper port    I suppose.
    BRA.S   .cz                    ; Jump ahead to select it
.c6 MOVE.B  #$09,-(SP)             ; Select the slot 3 lower port
    BRA.S   .cz                    ; Jump ahead to select it
.c7 MOVE.B  #$0A,-(SP)             ; Select the slot 3 upper port

.cz BSR     NSelectParallelPort    ; Select the user's chosen parallel port
    ADDQ.L  #$2,SP                 ; Pop the parallel port off the stack
    BNE.S   .uh                    ; Allow user to give up on failure
    BRA     Interface              ; And once more from the top!

.cx mUiPrint  <$0A,' It seems no port has a Cameo/Aphid attached.'>

    ; If we're here, we can't run; ask the user for a last-ditch action
.uh mUiPrint  <$0A,$0A,' Q(uit to ROM, S(tart over, or try to B(oot anyway?'>
.ul BSR     UiScreensaverWaitForKb   ; Await a keypress
    BNE     .cd                    ; Back to top if it wasn't a keypress
    PEA.L   .kt(PC)                ; The key-interpreting table for UiPSystemKey
    MOVE.B  zLisaConsoleKbChar(PC),-(SP)   ; Push the key we read onto the stack
    BSR     UiPSystemKey           ; Go interpret the key
    ADDQ.L  #$2,SP                 ; Pop the key we read off the stack
    BNE.S   .ul                    ; Loop if user typed a nonsense key
    ADDQ.L  #$4,SP                 ; Pop the table address off of the stack
    JMP     (A0)                   ; Jump as directed by the menu selection

    ; If we're here, the user wants us to try to boot anyway; exciting!
.ba BSR     CurrentDriveParallel   ; Is the current device a parallel port?
    BNE.S   .bx                    ; No, go complain
    BSR     NBootHd                ; Yes, try to boot
    BRA     Interface              ; Then, if we're back (?), start all over!
.bx PEA.L   sSuiNotParport(PC)     ; "The current device isn't a parallel port"
    mUiPrint  s                    ; Print the complaint
    BRA.S   .uh                    ; Then back to the "last ditch" menu

.ct DC.B    $00,'1'
    DC.W    (.c1-.ct)              ; Action for 1: Select the internal port
    DC.B    $00,'2'
    DC.W    (.c2-.ct)              ; Action for 2: Select slot 1 lower port
    DC.B    $00,'3'
    DC.W    (.c3-.ct)              ; Action for 3: Select slot 1 upper port
    DC.B    $00,'4'
    DC.W    (.c4-.ct)              ; Action for 4: Select slot 2 lower port
    DC.B    $00,'5'
    DC.W    (.c5-.ct)              ; Action for 3: Select slot 2 upper port
    DC.B    $00,'6'
    DC.W    (.c6-.ct)              ; Action for 6: Select slot 3 lower port
    DC.B    $00,'7'
    DC.W    (.c7-.ct)              ; Action for 3: Select slot 3 upper port
    DC.W    $0000                  ; Table terminator

    DS.W    0                      ; Word alignment
.kt DC.B    $01,'Q'
    DC.W    (.ex-.kt)              ; Action for Q: Quit to the ROM
    DC.B    $01,'S'
    DC.W    (Interface-.kt)        ; Action for S: Start over from the top
    DC.B    $01,'B'
    DC.W    (.ba-.kt)              ; Action for B: just try to boot
    DC.W    $0000                  ; Table terminator


    ; _IF_Secondary -- Nested user interface loops
    ; Args:
    ;   zConfig: Pre-loaded configuration data structure
    ; Notes:
    ;   Returning with Z set means that the user wants to choose a new
    ;       device; Z clear means the user wants to quit to ROM
    ;   Consider no register or memory area unchanged after calling
_IF_Secondary:
    BSR     CatalogueMenuTop       ; Reset catalogue scroll position to 0
    BSR     ClearLisaConsoleScreen   ; Blank the screen
    BSR     CatalogueInit          ; Init catalogue and force full reload
    mUiPrint  r1c0                 ; Move cursor down from top of screen
    BSR     NCatalogueUpdate       ; Update the drive image catalogue
    BNE     _IF_Fatal              ; Quit to the outer loop on error
    ; Branch to _IF_SecondaryNoUpdate for redrawing the catalogue from scratch
    ; without updating the catalogue: this is appropriate for resuming after
    ; operations that update the catalogue on their own.
_IF_SecondaryNoUpdate:
    BSR     ClearLisaConsoleScreen   ; Blank the screen
    BSR     CatalogueMenuShow      ; Show the catalogue menu

    ; Fall into the tertiary loop
_IF_Tertiary:
    ; Draw the command menu
    MOVE.B  zSuiWhichMenu(PC),D0   ; Should we show 2nd menu? (This is just TST)
    BNE.S   .2m                    ; Yes, jump ahead to prepare and show it
    PEA.L   sVersion(PC)           ; No, push program version string pointer
    PEA.L   sSuiMenu1(PC)          ; Push the address of the first menu
    BRA.S   .pm                    ; Jump ahead to push the moniker
.2m CLR.L   -(SP)                  ; Don't show a version string for 2nd menu
    PEA.L   sSuiMenu2(PC)          ; Push the address of the second menu
.pm PEA.L   zConfig(PC)            ; Push config address onto the stack
    BSR     ConfMonikerGet         ; Push the moniker to the stack
    MOVE.L  A0,(SP)                ; Replace config address with the moniker's
    BSR     UiPSystemShow          ; Paint the p-System style command menu
    ADDQ.L  #$8,SP                 ; Pop UiPSystemShow arguments, part 1
    ADDQ.L  #$4,SP                 ; Pop UiPSystemShow arguments, part 2

    ; Empty the keyboard (and mouse) buffer
    BSR     FlushCops              ; Dump out the keyboard buffer

    ; Fall into the quarternary loop
_IF_Quarternary:
    ; Clear tally of how many times we've drawn the status line
    CLR.W   D3                     ; Note: we clear it in other places, too

    ; Get and draw status from the Cameo/Aphid, or do the screensaver
.sl BSR     DoSysInfo              ; Print system status information
    ADDQ.W  #$1,D3                 ; Increment the tally of status line draws
    CMPI.W  #$3C,D3                ; Are there 60 of them so far?
    BLO.S   .pl                    ; Not yet; skip ahead to poll KB and mouse
    BSR     UiScreensaver          ; Yes, time for the screensaver!
    BRA.S   _IF_SecondaryNoUpdate  ; We're back; go redraw the screen

    ; Poll the keyboard and mouse for input, for a little while
.pl MOVE.W  D2,-(SP)               ; Push D2 to the stack
    MOVE.W  #$FFFE,D2              ; Number of times to poll the COPS
    BSR     LisaConsoleDelayForKbMouse   ; Poll the COPS for input
    BCS.S   .px                    ; Got a COPS byte, skip ahead to handle it
    MOVE.W  #$FFFE,D2              ; Number of times to poll the COPS
    BSR     LisaConsoleDelayForKbMouse   ; Poll the COPS for input
    ; Process the result of polling
.px MOVEM.W (SP)+,D2               ; Restore D2 from stack, leaving flags alone
    BCC.S   .sl                    ; Nothing read from COPS? Refresh status line
    BEQ.S   .me                    ; A glyph key is fully typed; go deal with it
    ROXR.W  #$1,D0                 ; Test X by rotating and checking the sign...
    BMI.S   .pl                    ; ...If set, we need to get more COPS bytes
    
    ; If here, we interpret raw character codes for scrolling, and the way this
    ; is implemented means you can "turbo scroll" by moving the mouse while you
    ; hold down the key; I actually like this a lot, so let's let it stay :-)
    PEA.L   .ks(PC)                ; The key-interpreting table for UiPSystemKey
    MOVE.B  zLisaConsoleKbCode(PC),-(SP)   ; Push the raw keycode onto the stack
    BSR     UiPSystemKey           ; Go interpret the key
    ADDQ.L  #$6,SP                 ; Pop the UiPSystemKey arguments
    BNE.S   .zt                    ; Loop if user typed a nonsense key
    JMP     (A0)                   ; Jump as directed by the menu selection

    ; For resetting the screensaver countdown without drawing the status line
.zt CLR.W   D3                     ; Clear the tally of status line draws
    BRA.S   .pl                    ; Return to keyboard polling

.cu BSR     CatalogueMenuUp        ; Move upward in the disk image menu
    BRA.S   .zt                    ; Get ready to return to keyboard polling

.cd BSR     CatalogueMenuDown      ; Move downward in the disk image menu
    BRA.S   .zt                    ; Get ready to return to keyboard polling

    DS.W    0                      ; Word alignment
.ks DC.B    $00,$A5
    DC.W    (.cu-.ks)              ; Action for keypad 8: menu up
    DC.B    $00,$A7
    DC.W    (.cu-.ks)              ; Action for up arrow: menu up
    DC.B    $00,$AB
    DC.W    (.cd-.ks)              ; Action for down arrrow: menu down
    DC.B    $00,$AD
    DC.W    (.cd-.ks)              ; Action for keypad 2: menu down
    DC.W    $0000                  ; Table terminator

    ; For interpreting a full keypress of a glyph key
.me PEA.L   .km(PC)                ; The key-interpreting table for UiPSystemKey
    MOVE.B  zLisaConsoleKbChar(PC),-(SP)   ; Push the key we read onto the stack
    BSR     UiPSystemKey           ; Go interpret the key
    ADDQ.L  #$6,SP                 ; Pop the UiPSystemKey arguments
    BNE.S   .pl                    ; Loop if user typed a nonsense key
    JMP     (A0)                   ; Jump as directed by the menu selection

    ; Menu key handler for booting from a disk image
.mb BSR     ClearLisaConsoleScreen   ; Blank the screen
    mUiPrint  r1c0                 ; Move cursor down from top of screen
    LEA.L   zCatMenu(PC),A0        ; Point A0 at the catalog menu record
    MOVE.W  kUISM_CPos(A0),-(SP)   ; Push currently selected item index to stack
    BSR     CatalogueItemName      ; A0 now points at the selection's filename
    ADDQ.L  #$2,SP                 ; Pop item index off of stack
    MOVE.L  A0,-(SP)               ; Push filename onto the stack
    BSR     NImageChange           ; Change the disk image
    ADDQ.L  #$4,SP                 ; Pop filename off of stack
    BNE     _IF_Fatal              ; Quit to the outer loop on error
    BSR     NBootHd                ; Attempt to boot
    BRA     _IF_Secondary          ; We're back? Well, restart first nested loop

    ; Menu key handler for selecting a disk image
.ms BSR     AskImageSelect         ; Present user with image selection display
    BRA     _IF_SecondaryNoUpdate  ; Restart first nested loop

    ; Menu key handler for creating a new disk image
.mn BSR     AskImageNewExtended    ; Present user with new drive image UI
    BRA     _IF_SecondaryNoUpdate  ; Restart first nested loop

    ; Menu key handler for copying a disk image
.mc BSR     AskImageCopy           ; Present user with drive image copy UI
    BRA     _IF_SecondaryNoUpdate  ; Restart first nested loop

    ; Menu key handler for renaming a disk image
.mr BSR     AskImageRename         ; Present user with drive image renaming UI
    BRA     _IF_SecondaryNoUpdate  ; Restart first nested loop

    ; Menu key handler for deleting a disk image
.md BSR     AskImageDelete         ; Present user with drive image deletion UI
    BRA     _IF_SecondaryNoUpdate  ; Restart first nested loop

    ; Menu key handler for switching the menu on display
.m_ LEA.L   zSuiWhichMenu(PC),A0   ; Point A0 at the "which menu" flag
    EORI.B  #$FF,(A0)              ; Toggle it
    BRA     _IF_Tertiary           ; Resume tertiary nested loop --- redraw menu

    ; Menu key handler for toggling autoboot (cheekily reaches into zCatMenu)
.ma LEA.L   zCatMenu(PC),A0        ; Point A0 at the catalog menu record
    MOVE.W  kUISM_CPos(A0),-(SP)   ; Push currently selected item index to stack
    BSR     CatalogueItemName      ; A0 now points at the selection's filename
    ADDQ.L  #$2,SP                 ; Pop item index off of stack
    MOVE.L  A0,-(SP)               ; Put the selection's filename onto the stack
    BSR     AskAutoboot            ; User interface for autoboot configuration
    ADDQ.L  #$4,SP                 ; Pop the filename pointer off the stack
    BRA     _IF_SecondaryNoUpdate  ; Restart first nested loop

    ; Menu key handler for changing a moniker
.mm BSR     AskMoniker             ; User interface for moniker modification
    BRA     _IF_SecondaryNoUpdate  ; Restart first nested loop

    ; Menu key handler for the key/value editor; note that restarting the first
    ; nested loop may be risky if the user has hand-edited the config!
.mk BSR     KeyValueEdit           ; User interface for key/value editing
    BRA     _IF_SecondaryNoUpdate  ; Restart first nested loop

    ; Menu key handler for selecting a new port
.mp ORI.B   #$04,CCR               ; Set the Z flag; we want a new device
    BRA.S   .rt                    ; Jump ahead to quit

    ; Menu key handler for quitting to the ROM
.mq ANDI.B  #$FB,CCR               ; Clear the Z flag; we want to quit to ROM
    BRA.S   .rt                    ; Jump ahead to quit

    DS.W    0                      ; Word alignment
.km DC.B    $01,'B'
    DC.W    (.mb-.km)              ; Action for B: boot from a drive image
    DC.B    $01,'S'
    DC.W    (.ms-.km)              ; Action for S: select a drive image
    DC.B    $01,'N'
    DC.W    (.mn-.km)              ; Action for N: create a new drive image
    DC.B    $01,'C'
    DC.W    (.mc-.km)              ; Action for C: copy a drive image
    DC.B    $01,'R'
    DC.W    (.mr-.km)              ; Action for R: rename a drive image
    DC.B    $01,'D'
    DC.W    (.md-.km)              ; Action for D: delete a drive image
    DC.B    $00,'?'
    DC.W    (.m_-.km)              ; Action for ?: toggle the command menu
    DC.B    $01,'A'
    DC.W    (.ma-.km)              ; Action for A: toggle autoboot
    DC.B    $01,'M'
    DC.W    (.mm-.km)              ; Action for M: change moniker
    DC.B    $01,'K'
    DC.W    (.mk-.km)              ; Action for K: key/value editor
    DC.B    $01,'P'
    DC.W    (.mp-.km)              ; Action for P: select a new port
    DC.B    $01,'Q'
    DC.W    (.mq-.km)              ; Action for Q: quit to ROM
    DC.W    $0000                  ; Table terminator

.rt RTS


    ; Handling fatal errors -- quit out of _IF_Secondary
    ; Code must not BSR or JSR here: use an ordinary jump
    ; Will exit from the "calling" function (on purpose)
    ; Does not run the screensaver here, so screen burn-in could be a risk after
    ; a fatal error, just like with the Classic MacOS "bomb" dialogue
_IF_Fatal:
    PEA.L   sSuiFatal(PC)          ; Push the address of the apology string
    mUiPrint  s                    ; Print it
    PEA.L   .kt(PC)                ; The key-interpreting table for UiPSystemKey
.lp BSR     LisaConsoleWaitForKbMouse  ; Await a keypress
    BNE.S   .lp                    ; Loop if it wasn't a keypress
    MOVE.B  zLisaConsoleKbChar(PC),-(SP)   ; Push the key we read onto the stack
    BSR     UiPSystemKey           ; Go interpret the key
    ADDQ.L  #$2,SP                 ; Pop the key we read off the stack
    BNE.S   .lp                    ; Loop if user typed a nonsense key
    ADDQ.L  #$4,SP                 ; Pop the key-table address
    JMP     (A0)                   ; Jump as directed by the menu selection

.rq ANDI.B  #$FB,CCR               ; User wants to quit to ROM; clear Z
    BRA.S   .rt
.rr ORI.B   #$04,CCR               ; User wants another go; set Z
.rt RTS

    DS.W    0                      ; Word alignment
.kt DC.B    $01,'Q'
    DC.W    (.rq-.kt)              ; Action for Q: quit to the ROM
    DC.B    $01,'R'
    DC.W    (.rr-.kt)              ; Action for R: choose a new device
    DC.W    $0000                  ; Table terminator


* selector_ui Data ------------------------------


    SECTION kSecData


sSuiBye:
    DC.B    'COME BACK SOON...',$00
sSuiNotParport:
    DC.B    $0A,$0A,' The current device isn',$27,'t a parallel port.',$0A
    DC.B    ' Try quitting to the ROM and booting from the '
    DC.B    'STARTUP FROM... menu',$00

sSuiMenu1:
    DC.B    'Command: B(oot, S(elect, N(ew, C(opy, R(ename, D(elete, ?',$00
sSuiMenu2:
    DC.B    'Command: A(utoboot toggle, M(oniker, K(ey/value, P(ort, Q(uit',$00

sSuiFatal:
    DC.B    $0A,$0A,' Sorry about that. What now: Q(uit to the ROM or '
    DC.B    'R(estart this program?',$00


* selector_ui Scratch data ----------------------


    SECTION kSecScratch


zSuiWhichMenu:
    DC.B    $00                    ; Show first menu if 0, else show second menu
