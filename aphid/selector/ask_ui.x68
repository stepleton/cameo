* Cameo/Aphid disk image selector: resources for asking the user a question
* =========================================================================
*
* Forfeited into the public domain with NO WARRANTY. Read LICENSE for details.
*
* Routines and definitions for asking the user for some input, and also for
* showing the user the result of attempting to carry out some kind of operation.
* Some data definitions are not used by routines in this file.
*
* These routines make use of routines defined in
* lisa_ui/lisa_console_screen.x68 and ui_base.x68. They also invoke macros
* defined in ui_macros.x68.
*
* Public procedures:
*    - AskVerdict -- Present final operation's result and await keypress
*    - AskVerdictByZ -- Present verdict depending on Z, await keypress
*    - AskOpResultByZ -- Present an operation result depending on Z


* ask_ui Code -----------------------------------


    SECTION kSecCode


    ; AskVerdict -- Present final operation's result and await keypress
    ; Args:
    ;   SP+$4: l. Address of a "verdict" string, e.g. "succeeded"
    ; Notes:
    ;   At the bottom of the screen (row 34), prints "Operation" followed by the
    ;       verdict string, then ". Press any key to continue."
    ;   Prior contents of row 34 are not cleared
    ;   Trashes D0-D1/A0-A1
AskVerdict:
    mUiGotoRC   #$22,#$1         ; Jump to the bottom of the screen
    MOVE.L    $4(SP),-(SP)       ; Duplicate verdict address on stack
    mUiPrint  <'Operation '>,s,<'. Press any key to continue.'>
.wt BSR     LisaConsoleWaitForKbMouse  ; Await a keypress
    BNE.S   .wt                  ; Keep waiting if it wasn't a keypress
    RTS


    ; AskVerdictByZ -- Present verdict depending on Z, await keypress
    ; Args:
    ;   CCR: If Z=1, say "Operation succeeded", if Z=0, say it failed
    ; Notes:
    ;   Leaves Z unchanged
    ;   Unlike AskOpResultByZ, awaits a keypress
    ;   Trashes D0-D1/A0-A1
AskVerdictByZ:
    SNE.B   -(SP)                ; If Z push $00, otherwise push $FF
    BNE.S   .fa                  ; If ~Z, announce failure
    PEA.L   sAskVerdictSucceeded(PC)   ; Success verdict address on the stack
    BRA.S   .pr                  ; Jump ahead to print the verdict
.fa PEA.L   sAskVerdictFailed(PC)  ; Failure verdict on the stack
.pr BSR.S   AskVerdict           ; Print the verdict and await a keypress
    ADDQ.L  #$4,SP               ; Pop verdict address off the stack
    TST.B   (SP)+                ; Recover original Z from stack
    RTS


    ; AskOpResultByZ -- Present an operation result depending on Z
    ; Args:
    ;   CCR: If Z=1, say "OK\n\n", if Z=0, say "FAILED\n\n"
    ; Notes:
    ;   Leaves Z unchanged
    ;   Trashes D0-D1/A0-A1
AskOpResultByZ:
    SNE.B   -(SP)                ; If Z push $00, otherwise push $FF
    BNE.S   .fa                  ; If ~Z, announce failure
    PEA.L   sAskOpOk(PC)         ; "OK" address on the stack
    BRA.S   .pr                  ; Jump ahead to print the verdict
.fa PEA.L   sAskOpFailed(PC)     ; "failed" address on the stack
.pr mUiPrint  s                  ; Print the result
    TST.B   (SP)+                ; Recover original Z from stack
    RTS


* ask_ui Data -----------------------------------


    SECTION kSecData


sAskVerdictCancelled:
    DC.B    'cancelled',$0
sAskVerdictSucceeded:
    DC.B    'succeeded',$0
sAskVerdictFailed:
sAskOpFailed:
    DC.B    'failed',$0

sAskIssuing:
    DC.B   $0A,$0A,$0A,$0A,$0A,' Issuing command... ',$0
sAskOpOk:
    DC.B   'OK',$0

sAskReturnCancel:
    DC.B    ' Return (',$85,') to proceed, Clear (',$98,') to cancel.',$0
