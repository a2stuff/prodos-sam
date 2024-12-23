# S.A.M. - ProDOS Utilities

S.A.M - The Software Automatic Mouth, by DON'T ASK Computer Software, is a speech generation system for the Apple II and other 8-bit computers including the Commodore 64. It came in many flavors, but the one of interest here is a pure-software implementation.

This repo contains notes and utilities for interacting with the library from ProDOS.

## `SAM` binary breakdown

Load address: $4000

SPEED  = $4009
PITCH  = $400A
ERROR  = $400B (set after call if an error occurred)
ECHO   = $400C (if set, echo to COUT)
REC    = $400D (if set, reciter mode; else phoneme mode)
BUFPOS = $400E
STASH  = $400F
BUFFER = $4010 ... $410F

Main entry points:
- $4000 - jumps to $4110 (entry point)
- $4003 - jumps to $41A2 ???
- $4006 - jumps to $66AD ???

$4009 - $410F - data

$4110
- sets $36/37 (COUT hook) to $4126
- clears ECHO
- sets BUFPOS to 0
- sets REC
- rts

$4126 - character hook
- stores A=char at $400F
- pushes X/Y
- control char? $4151
- puts (masked) char at BUFFER,BUFPOS
- checks ECHO, maybe calls COUT1 w/ unmasked char
- restores A/X/Y
- rts

$4151 - control character handler
- CHR$(5) - sets ECHO
- CHR$(14) - clears ECHO
- CHR$(20) - sets REC
- CHR$(16) - clears REC
- CHR$(13) - flush buffer ($4181 ....)
- otherwise ignore

## Using SAM from Assembly Language

The easiest way to interact with SAM is to load the library into memory, initialize it, then feed it data character by character.

```
        ;; Initialize
        lda     #60
        sta     SPEED
        lda     #72
        sta     PITCH
        lda     #0
        sta     ECHO
        lda     #255
        sta     REC
        lda     #0
        sta     BUFPOS

        ;; Feed characters
        lda     #'H'|$80
        jsr     $4126
        lda     #'I'|$80
        jsr     $4126
        lda     #$8D    ; flush buffer
        jsr     $4126
        lda     #0      ; reset buffer pointer
        sta     BUFPOS
```

The source file `tts.system.s` uses S.A.M. this approach to implement a ProDOS system file that acts as an interpreter. If passed a text file it will send the characters on through S.A.M. to generate speech.

## Using SAM from BASIC.SYSTEM

If you grab the disk from Asimov and copy just the SAM file over, you can use the following mini version of "SAYIT" this from BASIC.SYSTEM:

```
 10  PRINT  CHR$ (4)"BLOAD SAM,A$4000"
 30 SAM = 16384:SP = SAM + 9:PI = SAM + 10:ER = SAM + 11
 35 EC = SAM + 12:RE = SAM + 13:BP = SAM + 14
 40 SS = 60:PP = 72
 50  POKE SP,SS: POKE PI,PP
 55  FOR I = 0 TO 6: READ B: POKE 768 + I,B: NEXT
 56  POKE EC,0: POKE RE,255: POKE BP,0
 100  INPUT "> ";A$
 110  GOSUB 500
 120  GOTO 100
 500  POKE BP,0
 510  PRINT  CHR$ (4)"PR#A$300": PRINT A$: PRINT  CHR$ (4)"PR#0"
 520  RETURN
 1000  DATA  216,120,32,38,65,88,96
```


The BASIC program above pokes a short ML relay into $300:

```
  CLD    ; Tell ProDOS this is a real handler
  SEI    ; Cargo culted from a HRCG example
  JSR $4126 ; Call S.A.M.
  CLI    ; Cargo culted
  RTS
```

This allows `PR#A$300` to attach S.A.M., `PR#0` to detach.

The BASIC program sets `SPEED` and `PITCH` with pokes like SAYIT does. It then sets up ECHO, REC, and BUFPOS like a call to $4000 would, but $4000 also hooks $36/37 which we _don't_ want.

You can control ECHO and REC via control characters:

CHR$(5) - sets ECHO
CHR$(14) - clears ECHO
CHR$(20) - sets REC
CHR$(16) - clears REC
CHR$(13) - (i.e. carriage return) flush the buffer

REC is Reciter Mode. The S.A.M. manual on Asimov (which details a very different API, but the concepts are the same) describes it in detail. With Reciter Mode enabled, you can use english words and S.A.M. will infer phonemes using $MAGIC. With Reciter Mode disabled, you need to use explicit phonemes, e.g. CHR$(16);"AE4PUL TUX4 FOH4EH2ER4" (tables/examples in the manual)

Here's a slightly longer version:
```
 5  PRINT "S.A.M. will say what you type"
 6  PRINT "/Q    - quit"
 7  PRINT "/S nn - set speed, /S 60 is normal"
 8  PRINT "/P nn - set pitch, /P 72 is normal"
 9  PRINT "/O ppppp - use phonemes, like AE4PUL"
 10  PRINT  CHR$ (4)"BLOAD SAM,A$4000"
 30 SAM = 16384:SP = SAM + 9:PI = SAM + 10:ER = SAM + 11
 35 EC = SAM + 12:RE = SAM + 13:BP = SAM + 14
 40 SS = 60:PP = 72
 50  POKE SP,SS: POKE PI,PP
 55  FOR I = 0 TO 6: READ B: POKE 768 + I,B: NEXT
 56  POKE EC,0: POKE RE,255: POKE BP,0
 100  INPUT "> ";A$
 101  IF  MID$ (A$,1,2) = "/S" THEN  POKE SP, VAL ( MID$ (A$,3)): GOTO 100
 102  IF  MID$ (A$,1,2) = "/P" THEN  POKE PI, VAL ( MID$ (A$,3)): GOTO 100
 103  IF  MID$ (A$,1,2) = "/Q" THEN  END
 105  IF  MID$ (A$,1,2) = "/O" THEN A$ =  CHR$ (16) +  MID$ (A$,3): GOSUB 500:A$ =  CHR$ (20)
 110  GOSUB 500
 120  GOTO 100
 500  POKE BP,0
 510  PRINT  CHR$ (4)"PR#A$300": PRINT A$: PRINT  CHR$ (4)"PR#0"
 520  RETURN
 1000  DATA  216,120,32,38,65,88,96
```
