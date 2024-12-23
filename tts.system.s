;;; ============================================================
;;; Text-To-Speech via S.A.M.
;;; ============================================================

        .setcpu "6502"

        .include "apple2.inc"
        .include "longbranch.mac"
        .include "prodos.inc"

        .org    $2000

;;; ============================================================
;;; Interpreter protocol
;;; http://www.easy68k.com/paulrsm/6502/PDOS8TRM.HTM#5.1.5.1

        jmp     start
        .byte   $EE, $EE        ; signature
        .byte   65              ; pathname buffer length ($2005)
str_path:
        .res    65, 0

SYS_PATH := $280

;;; ============================================================

IO_BUF := $800                  ; $800...$BFF

TEXT_BUF := $C00
TEXT_BUF_SIZE = $2000 - TEXT_BUF

;;; S.A.M. Load address and configuration
SAM_ADDR := $4000
SAM_COUT := $4126
SAM_SPEED = $4009
SAM_PITCH = $400A
SAM_ERROR = $400B               ; set after call if error occurred
SAM_ECHO  = $400C               ; if set, echo to COUT
SAM_REC   = $400D               ; if set, reciter mode; else phoneme mode
SAM_BUFPOS= $400E

;;; ROM Equates
INIT    := $FB2F
BELL1   := $FBDD
HOME    := $FC58
COUT    := $FDED

message:
        .byte   " S.A.M. - The Software Automatic Mouth", $0D
        .byte   "By DON'T ASK Computer Software  (C) 1982", $0D, $0D
        .byte   0

default:
        .byte   $10, "AE4PUL TUX4 FOH4EH2VER4", $0D
        .byte   0

;;; ============================================================
;;; Parameters for loading S.A.M.

.proc open_sam_params
param_count:    .byte   3
pathname:       .addr   SYS_PATH
io_buffer:      .addr   IO_BUF
ref_num:        .byte   0
.endproc

.proc read_sam_params
param_count:    .byte   4
ref_num:        .byte   0
data_buffer:    .addr   SAM_ADDR
request_count:  .word   $BF00 - SAM_ADDR
trans_count:    .word   0
.endproc

.proc close_sam_params
param_count:    .byte   1
ref_num:        .addr   0
.endproc

str_sam_filename:
        PASCAL_STRING "SAM"

;;; ============================================================
;;; Parameters for loading text file

.proc open_text_params
param_count:    .byte   3
pathname:       .addr   str_path
io_buffer:      .addr   IO_BUF
ref_num:        .byte   0
.endproc

.proc read_text_params
param_count:    .byte   4
ref_num:        .byte   0
data_buffer:    .addr   TEXT_BUF
request_count:  .word   TEXT_BUF_SIZE
trans_count:    .word   0
.endproc

.proc close_text_params
param_count:    .byte   1
ref_num:        .addr   0
.endproc

;;; ============================================================

.proc quit_params
param_count:    .byte   4
quit_type:      .byte   0
reserved1:      .word   0
reserved2:      .byte   0
reserved3:      .word   0
.endproc

;;; ============================================================

start:
        lda     #$95            ; Disable 80-col firmware
        jsr     COUT
        jsr     INIT
        jsr     HOME
        ldy     #0
:       lda     message,y
        beq     :+
        ora     #$80
        jsr     COUT
        iny
        bne     :-              ; always
:
        sta     KBDSTRB

        ;; ----------------------------------------
        ;; Construct path to S.A.M. routine

        ;; Strip off last path segment
        ldy     SYS_PATH
        jeq     fail
:       lda     SYS_PATH,y
        and     #$7F
        cmp     #'/'
        beq     :+
        dey
        bne     :-
:
        ;; Append filename
        iny
        ldx     #1
:       lda     str_sam_filename,x
        sta     SYS_PATH,y
        cpx     str_sam_filename
        beq     :+
        iny
        inx
        bne     :-              ; always
:       sty     SYS_PATH

        ;; ----------------------------------------
        ;; Load S.A.M. routine

        MLI_CALL OPEN, open_sam_params
        jcs     fail
        lda     open_sam_params::ref_num
        sta     read_sam_params::ref_num
        sta     close_sam_params::ref_num
        MLI_CALL READ, read_sam_params
        php
        MLI_CALL CLOSE, close_sam_params
        plp
        jcs     fail

        ;; ----------------------------------------
        ;; Configure SAM

        lda     #60
        sta     SAM_SPEED
        lda     #72
        sta     SAM_PITCH
        lda     #0
        sta     SAM_ECHO
        lda     #255
        sta     SAM_REC
        lda     #0
        sta     SAM_BUFPOS

        ;; ----------------------------------------
        ;; Pathname passed?

        lda     str_path
        bne     load_file

        ldy     #0
:       tya
        pha
        lda     default,y
        jeq     exit
        jsr     sam
        pla
        tay
        iny
        bne     :-              ; always

        ;; ----------------------------------------
        ;; Open text file

load_file:
        MLI_CALL OPEN, open_text_params
        bcs     fail
        lda     open_text_params::ref_num
        sta     read_text_params::ref_num
        sta     close_text_params::ref_num

        ;; ----------------------------------------
        ;; Read next chunk of text content into buffer

read_more:
        MLI_CALL READ, read_text_params
        bcs     finish          ; including EOF, only if 0 bytes read

        lda     read_text_params::data_buffer
        sta     ptr
        lda     read_text_params::data_buffer+1
        sta     ptr+1

        ;; ----------------------------------------
        ;; Send each byte in buffer to S.A.M.

read_loop:
        ptr := *+1
        lda     $1234           ; self-modified
        jsr     sam

        ;; Abort if Escape is pressed
        lda     KBD
        bpl     :+
        sta     KBDSTRB
        cmp     #$9B            ; Escape
        beq     finish
:
        ;; Advance ptr to next byte
        inc     ptr
        bne     :+
        inc     ptr+1
:
        ;; Decrement count
        lda     read_text_params::trans_count
        bne     :+
        dec     read_text_params::trans_count+1
:       dec     read_text_params::trans_count

        ;; Anything left?
        lda     read_text_params::trans_count
        ora     read_text_params::trans_count+1
        bne     read_loop
        beq     read_more       ; always

        ;; ----------------------------------------
        ;; Emit to SAM
sam:
        ora     #$80            ; TODO: Is this necessary?
        pha
        php
        sei
        jsr     SAM_COUT
        plp
        pla

        ;; Reset buffer position after CR
        ;; TODO: Why isn't S.A.M. doing this automatically?
        cmp     #$8D
        bne     :+
        lda     #0
        sta     SAM_BUFPOS
:
        rts

        ;; ----------------------------------------
        ;; Close text file and finish
finish:
        MLI_CALL CLOSE, close_text_params

        ;; Flush S.A.M.'s text buffer
        lda     #$0D
        jsr     sam
        jmp     exit

        ;; ----------------------------------------
        ;; Error encountered - just beep annoyingly
fail:
        jsr     BELL1
        ;; fall through to `exit`

        ;; ----------------------------------------
        ;; Exit back to ProDOS
exit:
        inc     $3F4            ; Invalidate the power-up byte
        MLI_CALL QUIT, quit_params

