* Cameo/Aphid disk image selector: main program
* =============================================
*
* Forfeited into the public domain with NO WARRANTY. Read LICENSE for details.
*
* This is the "Selector": a disk image management utility for Cameo/Aphid
* ProFile hard drive emulators, meant to run on all Apple Lisa variants that
*   a) were sold to the public and
*   b) are capable of running the Lisa Office System.
*
* Users can use this program to select which hard drive image contains the data
* that the Cameo/Aphid should serve to the Lisa; they can also direct the
* Cameo/Aphid to create, copy, rename, or delete hard drive images. There is
* even a rudimentary scripting capability for some of these actions; for now,
* though, the only capability in easy reach of users is setting up a boot-time
* "autorun" script that chooses a disk image and directs the Lisa to boot from
* it.
*
* All of the Cameo/Aphid-specific actions triggered by this program (managing
* drive images, viewing and changing configuration, and so on) are accomplished
* through writes to various Cameo/Aphid "magic blocks": blocks that, when
* accessed for reading or writing, engage various Cameo/Aphid special features.
* See documetation in the Cameo/Aphid Python implementation for details.
*
* Compilation size can be reduced by approximately half a kilobyte if you know
* the "stepleton_hd" bootloader (https://github.com/stepleton/bootloader_hd)
* will load this program; see the fStandalone flag below.


* Compilation flags -----------------------------


    ; Set this flag to 0 if and only if it will be loaded and executed by the
    ; "stepleton_hd" bootloader; otherwise, set to 1 (see comments in MAIN)
fStandalone EQU 1


* Preamble --------------------------------------


    ; This program is organised into four sections. Clarifying the brief
    ; descriptions below: kSecScratch is mainly for small items that you would
    ; find on the heap in conventional programs, but this program doesn't have a
    ; heap: we just preallocate various data structures (and statically
    ; initialise some of their data members). kSecBuffer is all of the memory
    ; past kSecScratch: we use it for a few larger objects, for general purpose
    ; reading and writing, and for items that can grow without bound (that's the
    ; disk image catalogue, for now).
kSecCode    EQU 0                ; For executable code
kSecData    EQU 1                ; For immutable data (e.g. many strings)
kSecScratch EQU 2                ; For mutable temporary storage
kSecBuffer  EQU 3                ; More mutable temporary storage


kSecC_Start EQU $800             ; The bootloader loads code to $800
    ; We manually trim these sizes down to the smallest values that won't result
    ; in more than one byte being assigned to the same memory location (the
    ; telltale sign of which is an error message from srec_cat).
kSecC_SSize EQU $32BA            ; The size of all code if fStandalone=0
kSecC_PSize EQU $1F6             ; Additional code size if fStandalone=1
kSecD_Size  EQU $1160            ; The size of the kSecData section
kSecS_Size  EQU $26A             ; The size of the kSecScratch section


    IFEQ fStandalone
kSecD_Start EQU (kSecC_Start+kSecC_SSize)
    ENDC
    IFNE fStandalone
kSecD_Start EQU (kSecC_Start+kSecC_SSize+kSecC_PSize)
    ENDC
kSecS_Start EQU (kSecD_Start+kSecD_Size)
kSecB_Start EQU (kSecS_Start+kSecS_Size)


    SECTION kSecCode
    ORG     kSecC_Start
    SECTION kSecData
    ORG     kSecD_Start
    SECTION kSecScratch
    ORG     kSecS_Start
    SECTION kSecBuffer
    ORG     kSecB_Start


    INCLUDE ui_macros.x68


* Main program ----------------------------------


    SECTION kSecCode


MAIN:
    ; If this program is loaded by the "stepleton_hd" bootloader, we can count
    ; on the lisa_io/lisa_profile_io.x68 routines being resident in memory
    ; somewhere, the data structures for those routines being initialised to
    ; work with the boot disk, and registers A0-A3 pointing to useful elements
    ; within that library. But if we were loaded by anything else, we have to
    ; bring our own copy of those routines (see the includes section below)
    ; and initialise things the same way the "stepleton_hd" bootloader does.
    IFNE fStandalone
    MOVE.B  $1B3,D0              ; Boot device ID saved by the ROM into D0
    ANDI.W  #$000F,D0            ; Just in case it's weird: force into [0,15]
    MOVE.W  #kDrive_Prts,D1      ; In D1: load parport device ID bitmap
    BTST.L  D0,D1                ; Is the device ID a parallel port?
    BNE.S   .ps                  ; If so, skip ahead to initialise it
    MOVEQ.L #$2,D0               ; Otherwise, fall back on the internal port
.ps BSR     ProFileIoSetup       ; Set up the parallel port for that device
    BSR     ProFileIoInit        ; Initialise the VIAs (or VIA, for exp.cards)
    LEA.L   ProFileIoSetup(PC),A0  ; Set registers like the "stepleton_hd"...
    LEA.L   ProFileIoInit(PC),A1   ; ...bootloader does
    LEA.L   ProFileIo(PC),A2
    LEA.L   zProFileErrCode(PC),A3
    ENDC

    ; By this point, thanks to the "stepleton_hd" bootloader or the code just
    ; above, a library for hard drive I/O will be memory resident, with pointers
    ; to key routines waiting in the address registers. We save these pointers
    ; to locations in memory with a single instruction.
    LEA.L   zProFileIoSetupPtr(PC),A4
    MOVEM.L A0-A3,(A4)

    ; 1. Initialise library components for screen and keyboard/mouse I/O.
    BSR     InitLisaConsoleKbMouse
    BSR     InitLisaConsoleScreen
    BSR     ClearLisaConsoleScreen

    ; 2. Say hello
    PEA     sVersion(PC)         ; Push version string onto the stack
    mUiPrint  r1c1,<'[Cameo/Aphid]',$0A,' Hard drive image manager v'>,s

    ; 3. Initialise our own drive bookkeeping.
    BSR     NHelloBootDrive      ; Try to get Cameo/Aphid info from boot device
    BNE     .ui                  ; Not a Cameo/Aphid; skip ahead to the UI

    ; 4. Try to load configuration information
    BSR     NConfLoad            ; Try to load local configuration information
    BNE     .ui                  ; That failed; skip ahead to the UI
    PEA.L   zConfig(PC)          ; We will read configuration information here
    BSR     NConfRead            ; Try to read local configuration information
    BNE.S   .no                  ; Failed, skip ahead to skip ahead to the UI
    BSR     ConfIsOk             ; Check config integrity
.no ADDQ.L  #$4,SP               ; Pop zConfig address off the stack
    BNE     .ui                  ; Sometihng failed; skip ahead to the UI

    ; 5. Try to show splash image and fanfare
    BSR     _TrySplashImage      ; Try to show the splash image

    ; 6. Attempt to load and run an autoboot program
    BSR     _TryLoadAutoboot     ; Try to load the program
    BNE     .ui                  ; No autoboot program, jump to the main menu
    BSR     FlushCops            ; Flush any bytes coming in from the COPS
    mUiPrint  <$0A,$0A,' (Any key to interrupt) Running autoboot program in 3...'>
    BSR     _AnyKeyDelay         ; Wait one second for any key
    BEQ.S   .ui                  ; Key pressed; jump ahead to the main menu
    mUiPrint  <'2...'>
    BSR     _AnyKeyDelay         ; Wait one second for any key
    BEQ.S   .ui                  ; Key pressed; jump ahead to the main menu
    mUiPrint  <'1...',$0A>
    BSR     _AnyKeyDelay         ; Wait one second for any key
    BEQ.S   .ui                  ; Key pressed; jump ahead to the main menu

    PEA.L   zScriptPad(PC)       ; Push address of autoboot script
    MOVE.B  #$02,-(SP)           ; Pause for keypress if the script fails
    BSR     Interpret            ; Run autoboot program; may never return!
    ADDQ.L  #$6,SP               ; But if it does, pop Interpret arguments

    ; 7. Over to the main menu
.ui BRA     Interface            ; It never returns


    ; _TrySplashImage -- Display the splash image if it's enabled
    ; args:
    ;   (none)
    ; notes:
    ;   Scrolls only the first five lines of text out of the way of the image
    ;   Trashes D0-D1/A0-A1 and the zBlock disk block buffer
_TrySplashImage:
    PEA.L   zConfig(PC)          ; Push config address on the stack
    MOVE.W  #kC_FBitmap,-(SP)    ; We want to see if there's a splash image
    BSR     ConfFeatureTest      ; See whether there is
    ADDQ.L  #$6,SP               ; Pop ConfFeatureTest args off the stack
    BEQ.S   .rt                  ; Skip ahead to return if there's not

    MOVE.W  #'SB',-(SP)          ; Push cache key for the boot bitmap
    BSR     KeyValueRead         ; Read it into zBlock
    ADDQ.L  #$2,SP               ; Pop cache key off the stack
    BNE.S   .rt                  ; Skip ahead if it didn't read

    mUiScrollBox  #$0,#$0,#$A,#$5A,#-4   ; Scroll: make room for the image
    LEA.L   zRowLisaConsole(PC),A0   ; Point A0 at the current cursor row
    ADDQ.W  #$4,(A0)             ; And bump that down four rows

    LEA.L   zBlockData(PC),A0    ; Point A0 at the bitmap we read
    MOVE.L  zLisaConsoleScreenBase(PC),A1  ; Point A1 at the screen
    ADDA.W  #$32B,A1             ; Advance A1 to row 1, column 1
    MOVEQ.L #$1F,D0              ; Outer loop counter: 32 1-pixel rows
.lo MOVEQ.L #$3,D1               ; Inner loop counter: 4 32-pixel columns
.li MOVE.L  (A0)+,(A1)+          ; Copy 32-bits of bitmap
    DBRA    D1,.li               ; Iterate inner loop
    ADDA.W  #$4A,A1              ; Advance A1 to next screen row
    DBRA    D0,.lo               ; Iterate outer loop

.rt RTS


    ; _TryLoadAutoboot -- Attempt to load the autoboot script into zBlock
    ; args:
    ;   (none)
    ; notes:
    ;   Sets Z iff autoboot is enabled, the script loaded successfully, and the
    ;       script block checksum matched
    ;   Trashes D0-D1/A0-A1 and the zBlock disk block buffer
_TryLoadAutoboot:
    PEA.L   zConfig(PC)          ; Push config address on the stack
    MOVE.W  #kC_FBScript,-(SP)   ; We want to see if autoboot is enabled
    BSR     ConfFeatureTest      ; See whether it is
    ADDQ.L  #$6,SP               ; Pop ConfFeatureTest args off the stack
    EORI.B  #$04,CCR             ; Invert Z so Z means autoboot enabled
    BNE.S   .rt                  ; And skip ahead if it's not

    MOVE.W  #'Sa',-(SP)          ; Push cache key for "page 1" of the script
    BSR     NKeyValueRead        ; Read it into zBlock
    ADDQ.L  #$2,SP               ; Pop cache key off the stack
    BNE.S   .rt                  ; Skip ahead if that didn't work

    MOVE.L  A1,-(SP)             ; Put zBlockData address on the stack
    PEA.L   zScriptPad(PC)       ; Copy it to the script area
    MOVE.W  #$200,-(SP)          ; Copy 512 bytes in total
    BSR     Copy                 ; Do the copy
    ADDQ.L  #$2,SP               ; Pop copy size off the stack
    BSR     BlockCsumCheck       ; Check block checksum (reuse zScriptPad arg)
    ADDQ.L  #$8,SP               ; Pop args to BlockCsumCheck and Copy

.rt RTS


    ; _AnyKeyDelay -- Delay for a while unless the user presses a key
    ; Args:
    ;   (none)
    ; Notes:
    ;   Will delay even longer if the user moves or clicks the mouse
    ;   Trashes D0-D1/A0-A1
_AnyKeyDelay:
    MOVE.W  #$FFFE,D2            ; Delay loop iterations for awaiting keys
    BSR     LisaConsoleDelayForKbMouse   ; Poll the COPS for a while
    BEQ.S   .rt                  ; Return straightaway on a full keypress
.x1 MOVE.W  #$FFFE,D2            ; Delay loop constant again
    BSR     LisaConsoleDelayForKbMouse   ; Poll the COPS for a while
    BCC.S   .rt                  ; No COPS byte at all? Jump to return
    BEQ.S   .rt                  ; Full keypress? Jump to return here, too
    BRA.S   .x1                  ; Otherwise we must need more COPS bytes
.rt RTS


* Included components ---------------------------


    INCLUDE ask_ui.x68
    INCLUDE block.x68
    INCLUDE boot.x68
    INCLUDE catalogue.x68
    INCLUDE catalogue_ui.x68
    INCLUDE config.x68
    INCLUDE config_ui.x68
    INCLUDE drive.x68
    INCLUDE key_value.x68
    INCLUDE narrated.x68
    INCLUDE script.x68
    INCLUDE selector_ui.x68
    INCLUDE ui_base.x68
    INCLUDE ui_psystem_menu.x68
    INCLUDE ui_scrolling_menu.x68
    INCLUDE ui_screensaver.x68
    INCLUDE ui_textinput.x68
    INCLUDE lisa_io/lisa_console_kbmouse.x68
    IFNE fStandalone
    SECTION kSecCode             ; (lisa_profile_io.x68 doesn't use sections)
    INCLUDE lisa_io/lisa_profile_io.x68
    ENDC


* Fixed data ------------------------------------


    SECTION kSecData


sVersion:
    DC.B    '0.8',$00


* Scratch data ----------------------------------


    SECTION kSecScratch


    DS.W    0                    ; Word alignment
    ; Pointers to ProFile I/O library data and routines
zProFileIoSetupPtr:
    DC.L    'I/O '               ; Points to: I/O data structure setup routine
zProFileIoInitPtr:
    DC.L    'lib '               ; Points to: I/O port initialisation routine
zProFileIoPtr:
    DC.L    'poin'               ; Points to: block read/write routine
zProFileErrCodePtr:
    DC.L    'ters'               ; Points to: error code byte


* Buffer data -----------------------------------


    SECTION kSecBuffer


    ; 532 bytes of RAM for blocks read from/written to the disk
zBlock:
    ; This data is here just so the assembler will complain if the contents of
    ; the kSecScratch section start to impinge on this section. We can comment
    ; this out altogether if the code is building without complaint, but there's
    ; probably no need for that unless these are the only two bytes in the final
    ; 512-byte block.
    DC.B    'OK'                 ; Not used; unnecessary

    ; By ProFile convention, the first 20 bytes of data are the "tag"
zBlockTag   EQU zBlock
    ; And the remaining 512 bytes are the "data"
zBlockData  EQU zBlock+$14

    ; Next up is the standard location for 512 bytes of configuation
zConfig     EQU zBlock+$214

    ; Then a 512-byte scratch pad for scripts
zScriptPad  EQU zBlock+$214+$200

    ; The remaining space is dedicated to the disk image catalogue
zCatalogue  EQU zBlock+$214+$200+$200

    END     MAIN
