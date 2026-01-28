; **************************************************************** ;
; NormalLuser 
; Fast SD Read Audio Toon Demo on the BE6502 1/23/2026
; Assemble with VASM:
;    vasm6502_oldstyle -Fbin -dotdir -wdc02 -L Listing.txt FastSDToonRom.asm
; Start SD audio/video decoder with 8000R from WOZ using Serial connection.
; **************************************************************** ;
Programstart        = $8000 ;$200                  ; $F700 ; Page align!
Display             = $2000     ; start of memory mapped display 100x64 mapped to 128x64
; WozMon with NormalLuser Fast Binary Load
ZP          = $20
XAML        = ZP + 0             ;*Index pointers
XAMH        = ZP + 1 
STL         = ZP + 2 
STH         = ZP + 3 
L           = ZP + 4 
H           = ZP + 5 
YSAV        = ZP + 6 
MODE        = ZP + 7 
MSGL        = ZP + 8 
MSGH        = ZP + 9 
COUNTER     = ZP + 10 
CRC         = ZP + 11 
CRCCHECK    = ZP + 17
VGAClock    = $C 
IN          = $0200 ; *Input buffer*
Woz         = $F700 ; Start of WozMon

zp_sd_cmd_address   = $A2
zp_sd_cmd_addressH  = $A3
Screen              = $B1
ScreenH             = $B2
DummyZP             = $A8
DummyZPH            = $A9
VIA_PORTA_Ind       = $AA
VIA_PORTA_IndH      = $AB
;IRQAudioPointer     = $AC
;IRQAudioPointerH    = $AD
IRQTempA            = $AE
AudioBuffer	        = $1F00 ; 256 byte rolling buffer for audio samples

ACIA                = $5000 
ACIA_DAT            = ACIA
ACIA_SR             = ACIA+1
ACIA_CMD            = ACIA+2
ACIA_CTRL           = ACIA+3

VIA               = $6000
VIA_PORTB         = VIA   ;$6000 ; Control and manual read port of SD card
VIA_PORTA         = VIA+1 ;$6001 ; SD byte reads here with pulse gen-shift register 
VIA_DDRB          = VIA+2 ;$6002
VIA_DDRA          = VIA+3 ;$6003
VIA_T1CL          = VIA+4 ;$6004
VIA_T1CH          = VIA+5 ;$6005
VIA_T1LL          = VIA+6 ;$6006
VIA_T1LH          = VIA+7 ;$6007
VIA_T2CL          = VIA+8 ;$6008
VIA_T2CH          = VIA+9 ;$6009
VIA_SHIFT         = VIA+10;$600A ; CB2 on VIA is connected to speaker with a resistor and capacitor to reduce current and another capacitor  to act as lowpass audio filter.
VIA_AUX           = VIA+11;$600B 
VIA_PCR           = VIA+12;$600C
VIA_IFR           = VIA+13;$600D
VIA_IER           = VIA+14;$600E
VIA_IORA          = VIA+15;$600F
;FrameRate        = 20
;VGARate          = 60    ; Actually it is more like 60.31Hz. Adjust video conversion for this. 
FPSClock          = 3     ; VGARate/FrameRate 

  .org Programstart ; Page align this program in RAM/ROM

  SEI              ; Stop IRQ's so audio does not play until we are ready
  ldx #$FF         ; Lets start at the top of the stack
  txs              ; Nice and clean,  with room on the bottom if we need it   
  LDX #0           ; X only used by IRQ Audio player

 LDA #$20    ; Screen starts at $2000
 STA ScreenH
 STZ Screen
 STZ DummyZP ;Make sure Dummy Reads for SD card Toss Bits routine don't hit VIA or ACIA

; Cycle count Indirect pointers for TossBits
 LDA #>VIA_PORTA
 STA VIA_PORTA_IndH
 LDA #<VIA_PORTA
 STA VIA_PORTA_Ind

; SD card initial setup
 lda #$00 
 sta VIA_DDRA     ; ALL INPUT ;Bit 1 input, rest output
 LDA #$7F         ; Change to %01111111 so that bit 7 is input. ;#$FF 
 STA VIA_DDRB     ; $6002  ;PB out
 ;LDA #$1         ;
 ;STA VIA_PORTB   ; SD clock to default High state for startup routine?
 lda #$0a         ; Make CA2 pulse each time port A is read tnx gfoot!
 sta VIA_PCR


; **** INIT SD CARD ***
 jsr sd_init
; ****  INIT Audio  ***
; Clear audio Buffer:
 LDY #$0
 LDA #$0
AudioClearLoop:
 STA AudioBuffer,y
 INY
 BNE AudioClearLoop

 LDA #$0
 STA VIA_AUX ;$600B  ;Clear ACR
 LDA #$14
 STA VIA_AUX ;$600B  ; Set to shift out under T2
 LDA #$84 ; ORA #$84 ; Set IRQ for shift register
 STA VIA_IER
;Slowest is FF,FF 61,61 is 3,157
 ;LDA #$9B ; Low Bitrate 15,920 / 1,990 ;#$40 ;#$1F ;6C 
 LDA #$40 ; High Bitrate 37,872/4,734
 ;LDA #$1F ;
 STA VIA_T2CL ;$6008  ;What speed to shift out at
 STA VIA_T2CH ;$6009
 ; Start the frame sync clock
 LDA #FPSClock ;#$3
 STA VGAClock
 


 CLI            ; Ready to start playing Audio!
 LDA #$0
 STA VIA_SHIFT  ; First shift out triggers IRQ routine.
 LDX #0 ; Start postion of Audio playback in buffer.
 

 LDA #FPSClock ;#$3
 STA VGAClock
 LDY #$0
; This could be unrolled more if placed in ROM, but not needed for 20FPS+Audio.
; The 512 byte CRC bytes required for SD card mode READ_MULTIBLOCK makes issues because
; the 6,400 drawn pixels/bytes divided by 64 is 12.5
; This means it is better to just read a fixed 256 audio block every frame so that the same
; draw routine can be used every frame.
; IE (6,400+256)/512 = 13. 
DrawLoop:
 LDA #$20
 STA ScreenH
 ;LDY #$0 ;Should Always be 0?
 JSR Line500_Odd
 JSR Line12
 JSR TossBits ;~13 toss bits per frame with audio. 156 cycles for JSR/RTS 3,120 saved per second if unrolled.
 JSR Line88_Even
 JSR Line400_Odd
 JSR Line24
 JSR TossBits
 JSR Line76_Odd
 JSR Line400_Even
 JSR Line36
 JSR TossBits
 JSR Line64_Even
 JSR Line400_Odd
 JSR Line48
 JSR TossBits
 JSR Line52_Odd
 JSR Line400_Even
 JSR Line60
 JSR TossBits
 JSR Line40_Even
 JSR Line400_Odd
 JSR Line72
 JSR TossBits
 JSR Line28_Odd
 JSR Line400_Even
 JSR Line84
 JSR TossBits
 JSR Line16_Even
 JSR Line400_Odd
 JSR Line96
 JSR TossBits
 JSR Line4_Odd
 JSR Line500_Even
 JSR Line8
 JSR TossBits
 JSR Line92_Odd
 JSR Line400_Even
 JSR Line20
 JSR TossBits
 JSR Line80_Even
 JSR Line400_Odd
 JSR Line32
 JSR TossBits
 JSR Line68_Odd
 JSR Line400_Even
 JSR Line44
 JSR TossBits
 JSR Line56_Even
 ; Last 2 lines
 JSR Line200_Odd
 
 ; Load 256 Audio Bytes Here. Fully unroll in ROM?
 ; LDY #$0 ; Should be 0 already?
 ; Here I load 4 bytes manually so I can time the reset of the X register
 LDA VIA_PORTA
 STA AudioBuffer,y
 INY ;11 per buffered sample
 LDA VIA_PORTA
 STA AudioBuffer,y
 INY ;11 per buffered sample
 
 ; Reset the read pointer after 2 bytes loaded to start of buffer.
 ; This is from trial and error testing.
 LDX #0 ; Start postion of Audio playback in buffer.
 ; Load two more bytes quickly
 LDA VIA_PORTA
 STA AudioBuffer,y
 INY ;11 per buffered sample
 LDA VIA_PORTA
 STA AudioBuffer,y
 INY ;11 per buffered sample
 
AudioTop: ; 3,009 cycle loop with 4 read unroll (- the above 4 bytes).
 LDA VIA_PORTA
 STA AudioBuffer,y
 INY ;11 per buffered sample
 LDA VIA_PORTA
 STA AudioBuffer,y
 INY ;11 per buffered sample
 LDA VIA_PORTA
 STA AudioBuffer,y
 INY ;11 per buffered sample
 LDA VIA_PORTA
 STA AudioBuffer,y
 INY ;11 per buffered sample
 BNE AudioTop ;+2 cycles
 
 JSR TossBits 
 
 VGASync: 
 LDA VGAClock
 BNE VGASync    ; Check if NMI clock is zero yet?
 LDA #FPSClock  ; #3 ;20 FPS is 60/3 
 STA VGAClock   ; Set next VGA Sync clock value

 ;Debug: Turn on a pin while waiting for vsync
; LDA #$2 ;$%00000010
; ORA VIA_PORTB 
; STA VIA_PORTB 
; VGASync: 
;  LDA VGAClock
;  BNE VGASync    ; Check if NMI clock is zero yet?
;  LDA #FPSClock  ; #3 ;20 FPS is 60/3 
;  STA VGAClock   ; Set next VGA Sync clock value
 ;Debug: Turn pin back off
; LDA #$FD ;$%11111101
; AND VIA_PORTB 
; STA VIA_PORTB 

;  ;Debug Version Turn pin on and off while waiting for vsync
; VGASync: 
;  ;Debug: Turn on a pin while waiting for vsync
;  LDA #$2 ;$%00000010 ;4
;  ORA VIA_PORTB  ;4
;  STA VIA_PORTB  ;4
 
;  ;Debug: Turn pin back off
;  LDA #$FD ;$%11111101 l 4 
;  AND VIA_PORTB  ; 4
;  STA VIA_PORTB  ;4
; ;Check Vsync:
;  LDA VGAClock ;3
;  BNE VGASync    ; 2/3 Check if NMI clock is zero yet?
;  LDA #FPSClock  ; #3 ;20 FPS is 60/3 
;  STA VGAClock   ; Set next VGA Sync clock value
 
 ; Next Frame.
 JMP DrawLoop
 
 ; ***** Toss Bits here
TossBits:            ; New 99 to 108 (sometimes a few more?) cycle Routine.  
; Must throw away 10 bytes every block read from the SD card No choice 
; Actually....... it is not 10 bytes if I read at 5Mhz like I am now.
; It is 2 16 bit CRC bytes IE 4 bytes need to be read and thrown out.
; Followed by some number of 'pre-charge' cycles to get the card ready for
; the next block of data.
; 10 just happens to work at slower speeds, IE with VIA bit-bang.
; At higher speeds it is actually variable as to how much time it takes the card to be ready
; Usually 6, sometimes 5, sometimes 7 'pre-charge' on the cards I am using it seems.
; Below uses 65C02 Zeropage Indirect because it is 5 cycles.
; Minimum of 6 cycles needed after each 4 cycle read for pulse generator to finish shifting and reset.
; IE, 10 cycles read rate is the fastest my circuit can read from the SD card.

 LDA (VIA_PORTA_Ind) ; 5 cycles byte 1
 LDA (DummyZP)       ; 5 cycles delay for Pulse Generator circuit to shift out pulse x8 and reset. 
 LDA (VIA_PORTA_Ind) ; Byte 2
 LDA (DummyZP) ;
 LDA (VIA_PORTA_Ind) ; Byte 3
 LDA (DummyZP) ;
 LDA (VIA_PORTA_Ind) ; Byte 4
 LDA (DummyZP) ;
; Pre-Charge clocks needed for SD card to be ready
 LDA (VIA_PORTA_Ind) ; Byte 5
 LDA (DummyZP) ;
 LDA (VIA_PORTA_Ind) ; Byte 6
 LDA (DummyZP) ;
 LDA (VIA_PORTA_Ind) ; Byte 7
 LDA (DummyZP) ;
 LDA (VIA_PORTA_Ind) ; Byte 8
 LDA (DummyZP) ;
 LDA (VIA_PORTA_Ind) ; Byte 9

; On my Kingston SD card there are reads after 2 16 bit required CRC bytes.
; To save cycles I will spam port A with almost enough reads
; so I only need to check this as few times as possible. My testing shows a total of 9 bytes read is safe.
; So this loop usually runs 0, 1 or 2 times at 5mhz. Sometimes 3 maybe?
TossBitsCardReadyLoop:
 LDA VIA_PORTA
 CMP #254 ; result of 255 is Card pre-charge next block, 254 means it is done and next read will be good.
 BNE TossBitsCardReadyLoop
 ; ***** End Toss Bits
 RTS
 
 ; Unrolled routines for loading bytes to screen buffer below
 ; Screen is 100x64 mapped to a 128x64 area of RAM starting at $2000.
 ; 28 bytes/pixels are off screen at end of each row.
 ; IE line 0 starts at $2000, line 1 starts at $2080
 ; Routine is doubled-up with a Even and Odd version of each to account for this layout.
 ; Using direct JSR list, no need to page align.
Line500_Odd:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line499:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line498:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line497:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line496:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line495:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line494:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line493:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line492:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line491:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line490:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line489:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line488:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line487:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line486:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line485:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line484:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line483:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line482:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line481:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line480:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line479:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line478:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line477:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line476:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line475:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line474:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line473:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line472:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line471:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line470:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line469:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line468:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line467:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line466:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line465:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line464:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line463:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line462:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line461:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line460:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line459:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line458:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line457:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line456:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line455:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line454:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line453:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line452:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line451:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line450:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line449:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line448:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line447:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line446:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line445:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line444:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line443:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line442:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line441:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line440:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line439:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line438:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line437:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line436:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line435:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line434:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line433:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line432:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line431:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line430:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line429:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line428:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line427:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line426:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line425:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line424:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line423:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line422:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line421:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line420:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line419:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line418:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line417:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line416:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line415:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line414:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line413:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line412:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line411:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line410:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line409:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line408:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line407:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line406:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line405:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line404:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line403:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line402:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line401:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
 
 LDY #$80	 ; Next Line ************************
 
Line400_Even:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line399:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line398:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line397:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line396:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line395:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line394:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line393:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line392:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line391:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line390:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line389:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line388:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line387:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line386:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line385:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line384:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line383:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line382:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line381:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line380:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line379:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line378:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line377:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line376:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line375:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line374:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line373:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line372:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line371:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line370:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line369:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line368:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line367:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line366:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line365:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line364:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line363:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line362:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line361:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line360:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line359:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line358:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line357:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line356:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line355:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line354:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line353:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line352:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line351:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line350:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line349:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line348:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line347:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line346:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line345:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line344:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line343:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line342:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line341:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line340:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line339:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line338:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line337:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line336:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line335:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line334:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line333:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line332:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line331:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line330:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line329:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line328:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line327:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line326:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line325:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line324:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line323:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line322:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line321:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line320:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line319:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line318:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line317:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line316:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line315:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line314:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line313:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line312:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line311:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line310:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line309:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line308:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line307:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line306:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line305:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line304:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line303:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line302:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line301:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
 
 LDY #$0	 ; Next Line *******************
 INC ScreenH
 
Line300_Odd:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line299:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line298:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line297:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line296:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line295:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line294:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line293:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line292:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line291:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line290:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line289:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line288:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line287:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line286:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line285:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line284:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line283:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line282:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line281:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line280:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line279:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line278:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line277:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line276:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line275:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line274:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line273:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line272:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line271:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line270:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line269:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line268:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line267:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line266:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line265:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line264:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line263:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line262:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line261:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line260:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line259:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line258:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line257:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line256:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line255:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line254:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line253:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line252:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line251:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line250:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line249:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line248:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line247:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line246:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line245:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line244:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line243:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line242:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line241:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line240:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line239:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line238:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line237:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line236:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line235:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line234:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line233:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line232:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line231:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line230:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line229:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line228:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line227:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line226:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line225:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line224:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line223:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line222:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line221:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line220:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line219:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line218:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line217:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line216:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line215:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line214:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line213:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line212:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line211:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line210:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line209:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line208:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line207:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line206:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line205:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line204:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line203:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line202:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line201:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
 
 LDY #$80        ; Next Line ***************************
 
Line200_Even:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line199:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line198:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line197:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line196:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line195:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line194:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line193:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line192:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line191:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line190:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line189:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line188:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line187:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line186:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line185:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line184:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line183:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line182:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line181:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line180:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line179:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line178:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line177:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line176:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line175:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line174:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line173:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line172:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line171:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line170:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line169:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line168:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line167:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line166:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line165:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line164:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line163:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line162:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line161:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line160:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line159:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line158:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line157:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line156:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line155:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line154:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line153:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line152:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line151:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line150:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line149:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line148:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line147:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line146:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line145:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line144:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line143:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line142:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line141:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line140:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line139:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line138:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line137:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line136:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line135:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line134:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line133:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line132:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line131:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line130:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line129:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line128:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line127:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line126:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line125:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line124:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line123:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line122:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line121:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line120:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line119:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line118:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line117:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line116:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line115:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line114:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line113:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line112:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line111:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line110:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line109:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line108:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line107:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line106:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line105:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line104:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line103:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line102:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line101:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte

 LDY #$0	 ; Next Line *********************
 INC ScreenH

LineFill_Odd:
Line100_Odd:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line99_Odd:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line98_Odd:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line97_Odd:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line96_Odd:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line95_Odd:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line94_Odd:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line93_Odd:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line92_Odd:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line91_Odd:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line90_Odd:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line89_Odd:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line88_Odd:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line87_Odd:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line86_Odd:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line85_Odd:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line84_Odd:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line83_Odd:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line82_Odd:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line81_Odd:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line80_Odd:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line79_Odd:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line78_Odd:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line77_Odd:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line76_Odd:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line75_Odd:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line74_Odd:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line73_Odd:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line72_Odd:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line71_Odd:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line70_Odd:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line69_Odd:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line68_Odd:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line67_Odd:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line66_Odd:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line65_Odd:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line64_Odd:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line63_Odd:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line62_Odd:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line61_Odd:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line60_Odd:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line59_Odd:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line58_Odd:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line57_Odd:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line56_Odd:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line55_Odd:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line54_Odd:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line53_Odd:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line52_Odd:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line51_Odd:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line50_Odd:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line49_Odd:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line48_Odd:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line47_Odd:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line46_Odd:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line45_Odd:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line44_Odd:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line43_Odd:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line42_Odd:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line41_Odd:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line40_Odd:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line39_Odd:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line38_Odd:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line37_Odd:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line36_Odd:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line35_Odd:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line34_Odd:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line33_Odd:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line32_Odd:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line31_Odd:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line30_Odd:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line29_Odd:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line28_Odd:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line27_Odd:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line26_Odd:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line25_Odd:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line24_Odd:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line23_Odd:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line22_Odd:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line21_Odd:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line20_Odd:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line19_Odd:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line18_Odd:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line17_Odd:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line16_Odd:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line15_Odd:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line14_Odd:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line13_Odd:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line12_Odd:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line11_Odd:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line10_Odd:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line9_Odd:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line8_Odd:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line7_Odd:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line6_Odd:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line5_Odd:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line4_Odd:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line3_Odd:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_Odd:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line1_Odd:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 ;INY             ; 2 cycles 1 byte
Line0_Odd:
 ;LDA VIA_PORTA   ; 4 cycles 3 bytes
 ;STA (Screen),Y  ; 6 cycles 2 bytes
 ;INY             ; 2 cycles 1 byte
 LDY #$80
LineNone:
 RTS
 
 
;********************** Even Start 5 Lines x 500 Pixels ****************************** 
 
Line500_Even:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_499:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_498:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_497:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_496:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_495:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_494:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_493:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_492:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_491:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_490:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_489:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_488:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_487:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_486:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_485:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_484:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_483:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_482:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_481:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_480:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_479:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_478:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_477:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_476:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_475:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_474:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_473:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_472:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_471:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_470:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_469:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_468:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_467:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_466:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_465:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_464:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_463:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_462:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_461:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_460:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_459:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_458:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_457:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_456:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_455:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_454:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_453:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_452:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_451:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_450:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_449:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_448:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_447:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_446:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_445:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_444:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_443:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_442:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_441:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_440:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_439:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_438:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_437:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_436:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_435:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_434:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_433:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_432:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_431:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_430:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_429:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_428:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_427:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_426:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_425:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_424:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_423:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_422:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_421:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_420:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_419:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_418:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_417:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_416:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_415:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_414:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_413:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_412:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_411:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_410:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_409:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_408:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_407:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_406:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_405:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_404:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_403:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_402:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_401:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
 
 LDY #$0	 ; Next Line2_ ************************
 INC ScreenH
 
Line400_Odd:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_399:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_398:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_397:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_396:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_395:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_394:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_393:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_392:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_391:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_390:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_389:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_388:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_387:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_386:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_385:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_384:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_383:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_382:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_381:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_380:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_379:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_378:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_377:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_376:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_375:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_374:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_373:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_372:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_371:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_370:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_369:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_368:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_367:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_366:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_365:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_364:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_363:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_362:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_361:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_360:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_359:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_358:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_357:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_356:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_355:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_354:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_353:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_352:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_351:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_350:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_349:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_348:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_347:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_346:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_345:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_344:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_343:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_342:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_341:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_340:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_339:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_338:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_337:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_336:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_335:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_334:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_333:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_332:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_331:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_330:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_329:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_328:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_327:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_326:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_325:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_324:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_323:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_322:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_321:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_320:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_319:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_318:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_317:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_316:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_315:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_314:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_313:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_312:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_311:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_310:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_309:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_308:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_307:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_306:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_305:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_304:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_303:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_302:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_301:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
 
 LDY #$80	 ; Next Line2_ *******************
 
 
Line300_Even:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_299:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_298:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_297:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_296:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_295:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_294:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_293:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_292:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_291:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_290:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_289:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_288:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_287:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_286:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_285:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_284:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_283:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_282:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_281:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_280:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_279:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_278:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_277:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_276:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_275:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_274:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_273:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_272:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_271:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_270:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_269:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_268:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_267:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_266:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_265:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_264:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_263:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_262:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_261:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_260:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_259:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_258:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_257:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_256:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_255:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_254:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_253:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_252:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_251:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_250:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_249:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_248:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_247:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_246:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_245:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_244:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_243:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_242:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_241:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_240:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_239:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_238:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_237:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_236:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_235:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_234:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_233:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_232:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_231:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_230:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_229:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_228:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_227:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_226:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_225:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_224:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_223:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_222:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_221:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_220:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_219:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_218:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_217:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_216:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_215:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_214:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_213:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_212:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_211:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_210:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_209:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_208:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_207:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_206:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_205:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_204:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_203:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_202:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_201:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
 
 LDY #$0        ; Next Line2_ ***************************
 INC ScreenH
 
Line200_Odd:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_199:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_198:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_197:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_196:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_195:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_194:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_193:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_192:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_191:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_190:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_189:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_188:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_187:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_186:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_185:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_184:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_183:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_182:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_181:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_180:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_179:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_178:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_177:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_176:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_175:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_174:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_173:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_172:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_171:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_170:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_169:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_168:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_167:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_166:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_165:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_164:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_163:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_162:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_161:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_160:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_159:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_158:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_157:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_156:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_155:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_154:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_153:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_152:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_151:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_150:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_149:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_148:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_147:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_146:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_145:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_144:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_143:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_142:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_141:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_140:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_139:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_138:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_137:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_136:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_135:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_134:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_133:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_132:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_131:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_130:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_129:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_128:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_127:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_126:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_125:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_124:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_123:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_122:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_121:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_120:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_119:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_118:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_117:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_116:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_115:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_114:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_113:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_112:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_111:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_110:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_109:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_108:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_107:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_106:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_105:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_104:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_103:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_102:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_101:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte

 LDY #$80	 ; Next Line2_ *********************
 

LineFill_Even:
Line100_Even:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line99_Even:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line98_Even:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line97_Even:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line96_Even:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line95_Even:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line94_Even:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line93_Even:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line92_Even:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line91_Even:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line90_Even:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line89_Even:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line88_Even:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line87_Even:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line86_Even:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line85_Even:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line84_Even:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line83_Even:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line82_Even:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line81_Even:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line80_Even:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line79_Even:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line78_Even:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line77_Even:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line76_Even:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line75_Even:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line74_Even:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line73_Even:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line72_Even:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line71_Even:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line70_Even:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line69_Even:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line68_Even:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line67_Even:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line66_Even:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line65_Even:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line64_Even:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line63_Even:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line62_Even:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line61_Even:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line60_Even:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line59_Even:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line58_Even:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line57_Even:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line56_Even:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line55_Even:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line54_Even:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line53_Even:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line52_Even:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line51_Even:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line50_Even:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line49_Even:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line48_Even:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line47_Even:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line46_Even:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line45_Even:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line44_Even:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line43_Even:
 LDA VIA_PORTA ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line42_Even:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line41_Even:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line40_Even:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line39_Even:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line38_Even:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line37_Even:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line36_Even:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line35_Even:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line34_Even:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line33_Even:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line32_Even:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line31_Even:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line30_Even:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line29_Even:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line28_Even:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line27_Even:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line26_Even:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line25_Even:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line24_Even:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line23_Even:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line22_Even:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line21_Even:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line20_Even:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line19_Even:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line18_Even:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line17_Even:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line16_Even:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line15_Even:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line14_Even:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line13_Even:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line12_Even:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line11_Even:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line10_Even:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line9_Even:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line8_Even:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line7_Even:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line6_Even:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line5_Even:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line4_Even:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line3_Even:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2_Even:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line1_Even:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 ;INY             ; 2 cycles 1 byte
Line0_Even:
 ;LDA VIA_PORTA   ; 4 cycles 3 bytes
 ;STA (Screen),Y  ; 6 cycles 2 bytes
 ;INY             ; 2 cycles 1 byte
 LDY #$0
 INC ScreenH
LineNone_Even:
 RTS
 
 
 ; ********************** Line Fill, no new line *******************
 ; Makes JSR list easier and more clear to have this routine. 
 ; Could fold into Line Odd above and manually LDY #$0 INC ScreenH/ LDY #$80  to save space?

LineFill:
Line100:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line99:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line98:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line97:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line96:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line95:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line94:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line93:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line92:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line91:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line90:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line89:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line88:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line87:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line86:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line85:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line84:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line83:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line82:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line81:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line80:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line79:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line78:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line77:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line76:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line75:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line74:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line73:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line72:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line71:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line70:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line69:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line68:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line67:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line66:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line65:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line64:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line63:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line62:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line61:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line60:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line59:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line58:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line57:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line56:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line55:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line54:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line53:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line52:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line51:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line50:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line49:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line48:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line47:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line46:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line45:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line44:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line43:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line42:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line41:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line40:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line39:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line38:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line37:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line36:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line35:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line34:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line33:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line32:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line31:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line30:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line29:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line28:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line27:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line26:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line25:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line24:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line23:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line22:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line21:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line20:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line19:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line18:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line17:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line16:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line15:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line14:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line13:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line12:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line11:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line10:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line9:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line8:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line7:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line6:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line5:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line4:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line3:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line2:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line1:
 LDA VIA_PORTA   ; 4 cycles 3 bytes
 STA (Screen),Y  ; 6 cycles 2 bytes
 INY             ; 2 cycles 1 byte
Line0:
 ;LDA VIA_PORTA   ; 4 cycles 3 bytes
 ;STA (Screen),Y  ; 6 cycles 2 bytes
 ;INY             ; 2 cycles 1 byte
 RTS
 
 


;****************************************************************************
;******************************* SD INIT ************************************
;**************************************************************************** 
;  Modified SD startup code used for new pulse gen/shift register circuit
;  that uses modified Ben Eater PS/2 keyboard hardware and unused gates
;  to read an entire byte with just a LDA VIA_PORTA.
;  Able to read 1 byte every 10 clock cycles.
SD_CS   = $20 ;%00100000
SD_MOSI = $8  ;%00001000
SD_SCK  = $1  ;%00000001 ;%00001000
SD_MISO = $80 ;%10000000 ;%00000010
;PORTB_OUTPUTPINS = SD_CS | SD_SCK | SD_MOSI
sd_init: 
;  Thanks George Foot! https://githubcom/gfoot/sdcard6502 and for all your help on
;  6502.org forums and https://wwwredditcom/r/beneater/ !!
;
; Since the SD boot only runs at the start there is no real need to optimize this if it works
; I use Kingston Canvas Select Plus 32GB micro SD cards
; 2 pack with SD adapter for less than $8 at normal online places
; This code does a good job of booting them up I've used 4 so far without any issues

initfailed:
  lda #SD_CS | SD_MOSI
  ldx #160               ; toggle the clock 160 times, so 80 low-high transitions
; Let the SD card boot up, by pumping the clock with SD CS disabled
; We need to apply around 80 clock pulses with CS and MOSI high
; Normally MOSI doesn't matter when CS is high, but the card is
; not yet is SPI mode, and in this non-SPI state it does care
preinitloop:
  eor #SD_SCK
  sta VIA_PORTB
  dex
  bne preinitloop
  jsr longdelay ; delay loops changed to RTS, works with my cardm change back if you have issues. 

  
cmd0 ; GO_IDLE_staTE - resets card to idle state, and SPI mode
   lda #<cmd0_bytes
  sta zp_sd_cmd_address
  lda #>cmd0_bytes
  sta zp_sd_cmd_address+1

  jsr sd_sendcommand

  ; Expect status response $01 (not initialized)
  cmp #$01
  bne initfailed

  jsr longdelay

cmd8 ; SEND_IF_COND - tell the card how we want it to operate (33V, etc)
  lda #<cmd8_bytes
  sta zp_sd_cmd_address
  lda #>cmd8_bytes
  sta zp_sd_cmd_address+1

  jsr sd_sendcommand

  ; Expect status response $01 (not initialized)
  cmp #$01
  bne initfailed

  ; Read 32-bit return value, but ignore it
  jsr sd_readbyte
  jsr sd_readbyte
  jsr sd_readbyte
  jsr sd_readbyte

  jsr longdelay

cmd55 ; APP_CMD - required prefix for ACMD commands
  lda #<cmd55_bytes
  sta zp_sd_cmd_address
  lda #>cmd55_bytes
  sta zp_sd_cmd_address+1

  jsr sd_sendcommand

  ; Expect status response $01 (not initialized)
  cmp #$01
  bne initfailed

  jsr longdelay

cmd41 ; APP_SEND_OP_COND - send operating conditions, initialize card
   lda #<cmd41_bytes
  sta zp_sd_cmd_address
  lda #>cmd41_bytes
  sta zp_sd_cmd_address+1

  jsr sd_sendcommand

  ; Status response $00 means initialised
  cmp #$00
  beq initialized

  ; Otherwise expect status response $01 (not initialized)
  cmp #$01
  bne initfailed

  ; Not initialized yet, so wait a while then try again.
  ; This retry is important, to give the card time to initialize.
  jsr longdelay
  jsr longdelay
  jmp cmd55

    jsr longdelay
initialized
; Setup SD card to read forever
    lda #SD_MOSI ;| SD_CLK
    sta  VIA_PORTB 
    lda #$52 ; CMD18 - READ_MULTI_BLOCK
    ; WOW, that easy! Change $51 to $52 and I can stream
    ; bytes off the SD card forrever! Yea!
    ;Just have to remember to throw away the 10 byte
    ; CRC every 512 bytes Other than that, the bits stream forever Yea!
    jsr sd_writebyte    
    ; Start at the beginning of the SD card. IE RAW mode.
    ; Write binary data directly to the card with HxD or another Hex editor that can directly open SD cards
    lda #$00           ; sector 24:31
    jsr sd_writebyte
    lda #$00           ; sector 16:23
    jsr sd_writebyte
    lda #$00           ; sector 8:15
    jsr sd_writebyte
    lda #$00           ; sector 0:7
    jsr sd_writebyte
    lda #77;RLECount   ; crc (not checked, random data sent)
    jsr sd_writebyte

    jsr sd_waitresult
    cmp #$00
    beq readsuccess
    rts ;jmp BadAppleStart;reset ;This change makes it pretty reliable after a reboot

readsuccess
  ; wait for data
  jsr sd_waitresult
  cmp #$fe
  beq SdBooted
  ;Retry until it works
  rts ;jmp BadAppleStart;reset
SdBooted
  ;SD card booted, setup some values
  lda #SD_MOSI ;| SD_CLK               ; enable card (CS low), set MOSI (resting state), SCK low
  sta VIA_PORTB 
  ; Port A is in Clock pulse mode
  ; A read will pulse the clock on pin CA2 of the 6522 
  ; We will stream forever after that    
 



;\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/
;*******************************************************************************
;****************************** XX DECODE XX  **********************************
;******************************  -  START -   **********************************
;*******************************************************************************
; One pulse to start bits to shift register? Nope, not needed.
;lda VIA_PORTA ; Dummy Read to prime the shift register? Nope, not needed.
;********************* XX Jump to video stream decode now! XX ******************
;*******************************************************************************
;/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\
  rts


sd_readbyte: ; Used by SD INIT
  ; Enable the card and tick the clock 8 times with MOSI high, 
  ; capturing bits from MISO and returning them
  ldx #8                      ; we'll read 8 bits
readbyteloop:
  lda #SD_MOSI                ; enable card (CS low), set MOSI (resting state), SCK low
  sta VIA_PORTB

  lda #SD_MOSI | SD_SCK       ; toggle the clock high
  sta VIA_PORTB

  lda VIA_PORTB                   ; read next bit
  and #SD_MISO

  clc                         ; default to clearing the bottom bit
  beq readbytebitnotset              ; unless MISO was set
  sec                         ; in which case get ready to set the bottom bit
readbytebitnotset:

  tya                         ; transfer partial result from Y
  rol                         ; rotate carry bit into read result
  tay                         ; save partial result back to Y

  dex                         ; decrement counter
  bne readbyteloop                   ; loop if we need to read more bits

  rts


sd_writebyte:
  ; Tick the clock 8 times with descending bits on MOSI
  ; SD communication is mostly half-duplex so we ignore anything it sends back here

  ldx #8                      ; send 8 bits
writebyteloop:
  asl                         ; shift next bit into carry
  tay                         ; save remaining bits for later
  lda #0
  bcc writebytesendbit                ; if carry clear, don't set MOSI for this bit
  ora #SD_MOSI
writebytesendbit:
  sta VIA_PORTB                   ; set MOSI (or not) first with SCK low
  eor #SD_SCK
  sta VIA_PORTB                   ; raise SCK keeping MOSI the same, to send the bit
  tya                         ; restore remaining bits to send
  dex
  bne writebyteloop                   ; loop if there are more bits to send
  rts

sd_waitresult:
  ; Wait for the SD card to return something other than $ff
  jsr sd_readbyte
  cmp #$ff
  beq sd_waitresult
  rts

sd_sendcommand:
  ldx #0
  lda (zp_sd_cmd_address,x)
  lda #SD_MOSI  ;| SD_CLK         ; pull CS low to begin command ?? Debug, not sure
  sta  VIA_PORTB 
  ldy #0
  lda (zp_sd_cmd_address),y    ; command byte
  jsr sd_writebyte
  ldy #1
  lda (zp_sd_cmd_address),y    ; data 1
  jsr sd_writebyte
  ldy #2
  lda (zp_sd_cmd_address),y    ; data 2
  jsr sd_writebyte
  ldy #3
  lda (zp_sd_cmd_address),y    ; data 3
  jsr sd_writebyte
  ldy #4
  lda (zp_sd_cmd_address),y    ; data 4
  jsr sd_writebyte
  ldy #5
  lda (zp_sd_cmd_address),y    ; crc
  jsr sd_writebyte
  jsr sd_waitresult
  pha
  ; End command
  lda #SD_CS | SD_MOSI ;| SD_CLK   ; set CS high again, no spi mode 0? Debug
  sta  VIA_PORTB 
  pla   ; restore result code
  rts
;  .byte 'NormalLuser'



delay:
 RTS ; Faster boot without the delay and still works on my SD card
;   ldx #0
;   ldy #0
; delayloop
;   dey
;   bne delayloop
;   dex
;   bne delayloop
;   rts

longdelay:
 RTS ; Faster boot without the delay and still works on my SD card
;   jsr mediumdelay
;   jsr mediumdelay
;   jsr mediumdelay
mediumdelay:
  RTS ; Faster boot without the delay and still works on my SD card
;   jsr delay
;   jsr delay
;   jsr delay
;   jmp delay

 ;.org $2600
cmd0_bytes 
  .byte $40, $00, $00, $00, $00, $95
cmd8_bytes
  .byte $48, $00, $00, $01, $aa, $87
cmd55_bytes
  .byte $77, $00, $00, $00, $00, $01
cmd41_bytes
  .byte $69, $40, $00, $00, $00, $01 

  .byte "NormalLuser"

;\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/
;*******************************************************************************
;******************************  XX  WOZ  XX  **********************************
;******************************  -  START -   **********************************
;*******************************************************************************


;MSG do not need to be byte aligned. Put before Woz since there is room.
MSG1        .byte "Woz FL: NormalLuser FastSD Toon w Audio 8000 R ",0
MSG2        .byte "Load Data Start |  Data End",0
MSG3        .byte "        ",0
MSG4        .byte " -Start Binary File Transfer-",0
MSG5        .byte " All Bytes Imported -Done-",0
MSG6        .byte "-Timeout- NormalLuser Fast Binary Load",0
 ;.org Woz
; align  8    ; Page align Woz
 .org $F700
WozStart:    ; WozMon with L command for load,wider display, Rockwell ACIA routine
RESET
            CLD             ;Clear decimal arithmetic mode.
            CLI
            LDX #$FF        ;Lets start at the top of the stack.
            TXS             ;Nice
            

            LDA #$1F        ;* Init ACIA to 19200 Baud.
            STA ACIA_CTRL
            LDA #$0B        ;* No Parity. No IRQ
            STA ACIA_CMD
            
            JSR NewLine
            LDA #<MSG1
            LDX #>MSG1
            JSR SHWMSG      ;* Show Welcome.
            JSR NewLine
            JSR NewLine

;EDIT
            ;STZ BeepEnable
            STZ VIA_AUX
;END EDIT

            
SOFTRESET   LDA #$9B        ;* Auto escape.
NOTCR       CMP #$88        ;"<-"? * Note this was chaged to $88 which is the back space key.
            BEQ BACKSPACE   ;Yes.
            CMP #$9B        ;ESC?
            BEQ ESCAPE      ;Yes.
            INY             ;Advance text index.
            BPL NEXTCHAR    ;Auto ESC if >127.
ESCAPE      LDA #$DC        ;"\"
            JSR ECHO        ;Output it.
GETLINE     LDA #$8D        ;CR.
            JSR ECHO        ;Output it.
            LDA #$0A
            JSR ECHO
            LDY #$01        ;Initiallize text index.
BACKSPACE   DEY             ;Backup text index.
            BMI GETLINE     ;Beyond start of line, reinitialize.
            LDA #$A0        ;*Space, overwrite the backspaced char.
            JSR ECHO
            LDA #$88        ;*Backspace again to get to correct pos.
            JSR ECHO

NEXTCHAR    ;LDA ACIA_SR     ;*See if we got an incoming char
            ;AND #$08        ;*Test bit 3
            ;LDA io_getc    ; For Kowalski simulator use
            ;BEQ NEXTCHAR    ;*Wait for character
            ;LDA ACIA_DAT    ;*Load char
            JSR GETCHAR
            CMP #$60        ;*Is it Lower case
            BMI CONVERT     ;*Nope, just convert it
            AND #$5F        ;*If lower case, convert to Upper case
CONVERT     ORA #$80        ;*Convert it to "ASCII Keyboard" Input
            STA IN,Y        ;Add to text buffer.
            JSR ECHO        ;Display character.
            CMP #$8D        ;CR?
            BNE NOTCR       ;No.
            LDY #$FF        ;Reset text index.
            LDA #$00        ;For XAM mode.
            TAX             ;0->X.
SETSTOR     ASL             ;Leaves $7B if setting STOR mode.
SETMODE     STA MODE        ;$00 = XAM, $7B = STOR, $AE = BLOK XAM.
BLSKIP      INY             ;Advance text index.
NEXTITEM    LDA IN,Y        ;Get character.
            CMP #$8D        ;CR?
            BEQ GETLINE     ;Yes, done this line.
            CMP #$AE        ;"."?
            BCC BLSKIP      ;Skip delimiter.
            BEQ SETMODE     ;Set BLOCK XAM mode.
            CMP #$BA        ;":"?
            BEQ SETSTOR     ;Yes, set STOR mode.
            CMP #$D2        ;"R"?
            BEQ RUN         ;Yes, run user program.
            CMP #$CC        ;* "L"? LOAD Command check
            BEQ SETMODE     ;* Yes, set LOAD mode. NormalLuser addition
            ; CMP #$D0      ;* "P" test?
            ; BEQ PURGE     ;* Yes, Purge Memory.
            STX L           ;$00->L.
            STX H           ; and H.
            STY YSAV        ;Save Y for comparison.
NEXTHEX     LDA IN,Y        ;Get character for hex test.
            EOR #$B0        ;Map digits to $0-9.
            CMP #$0A        ;Digit?
            BCC DIG         ;Yes.
            ADC #$88        ;Map letter "A"-"F" to $FA-FF.
            CMP #$FA        ;Hex letter?
            BCC NOTHEX      ;No, character not hex.
DIG         ASL
            ASL             ;Hex digit to MSD of A.
            ASL
            ASL
            LDX #$04        ;Shift count.
HEXSHIFT    ASL             ;Hex digit left MSB to carry.
            ROL L           ;Rotate into LSD.
            ROL H           ;Rotate into MSD's.
            DEX             ;Done 4 shifts?
            BNE HEXSHIFT    ;No, loop.
            INY             ;Advance text index.
            BNE NEXTHEX     ;Always taken. Check next character for hex.
NOTHEX      CPY YSAV        ;Check if L, H empty (no hex digits).
            BNE NOESCAPE    ;* Branch out of range, had to improvise...
            JMP ESCAPE      ;Yes, generate ESC sequence.

RUN         JSR ACTRUN      ;* JSR to the Address we want to run.
            JMP SOFTRESET   ;* When returned for the program, reset EWOZ.
ACTRUN      JMP (XAML)      ;Run at current XAM index.
;---------------------NormalLuser edit--------------------------
NOESCAPE    LDA #$CC        ; NormalLuser Edit
            CMP MODE        ; Adding a 'L' Load mode.
            BEQ LOADBINARY  ; Match, LOAD a Binary file
;---------------------------------------------------------------              

            ;Back to Woz!
	          BIT MODE        ;Test MODE byte.
            BVC NOTSTOR     ;B6=0 for STOR, 1 for XAM and BLOCK XAM
            LDA L           ;LSD's of hex data.
            STA (STL, X)    ;Store at current "store index".
            INC STL         ;Increment store index.
            BNE NEXTITEM    ;Get next item. (no carry).
            INC STH         ;Add carry to 'store index' high order.
TONEXTITEM  JMP NEXTITEM    ;Get next command item.
NOTSTOR     BMI XAMNEXT     ;B7=0 for XAM, 1 for BLOCK XAM.
            LDX #$02        ;Byte count.
SETADR      LDA L-1,X       ;Copy hex data to
            STA STL-1,X     ;"store index".
            STA XAML-1,X    ;And to "XAM index'.
            DEX             ;Next of 2 bytes.
            BNE SETADR      ;Loop unless X = 0.
NXTPRNT     BNE PRDATA      ;NE means no address to print.
            LDA #$8D        ;CR.
            JSR ECHO        ;Output it.
            LDA #$0A
            JSR ECHO
            LDA XAMH        ;'Examine index' high-order byte.
            JSR PRBYTE      ;Output it in hex format.
            LDA XAML        ;Low-order "examine index" byte.
            JSR PRBYTE      ;Output it in hex format.
            LDA #$BA        ;":".
            JSR ECHO        ;Output it.
PRDATA      LDA #$A0        ;Blank.
            JSR ECHO        ;Output it.
            LDA (XAML,X)    ;Get data byte at 'examine index".
            JSR PRBYTE      ;Output it in hex format.
XAMNEXT     STX MODE        ;0-> MODE (XAM mode).
            LDA XAML
            CMP L           ;Compare 'examine index" to hex data.
            LDA XAMH
            SBC H
            BCS TONEXTITEM  ;Not less, so no more data to output.
            INC XAML
            BNE MOD8CHK     ;Increment 'examine index".
            INC XAMH
MOD8CHK     LDA XAML        ;Check low-order 'exainine index' byte
            ;AND #$0F       ;For MOD 8=0 ** changed to $0F to get 16 values per row **
            AND #$1F        ; For MOD 8=0 ** changed to $0F to get 32 values per row **
            BPL NXTPRNT     ;Always taken.
PRBYTE      PHA             ;Save A for LSD.
            LSR
            LSR
            LSR             ;MSD to LSD position.
            LSR
            JSR PRHEX       ;Output hex digit.
            PLA             ;Restore A.
PRHEX       AND #$0F        ;Mask LSD for hex print.
            ORA #$B0        ;Add "0".
            CMP #$BA        ;Digit?
            BCC ECHO        ;Yes, output it.
            ADC #$06        ;Add offset for letter.
; Rockwell/Non bugged WDC ACIA code 
; ** DO NOT USE with Ben Eater WDC based Serial Kit **
ECHO        PHA             ;*Save A
WAIT:      LDA ACIA_SR     ;*Load status register for ACIA
            AND #$10        ;*Mask bit 4.
            BEQ    WAIT    ;*ACIA not done yet, wait.
            PLA
            PHA
            AND #$7F        ;*Change to "standard ASCII"
            STA ACIA_DAT    ;*Send it.
            ;STA io_putc    ;For Kowalski simulator use
            PLA             ;*Restore A
            RTS             ;*Done, over and out...

LOADBINARY:
; NormalLuser Fast Binary load. With Timeout.
; Quickly Load an program in Binary Format to memory.
; Usage: 2000 L 4000
; Will start load at location $2000 hex and stop at $4000 hex
; 0L9 -or 1 L 200 -or 100.200,L200 all work also with WOZ parsing
; Space can be saved on the messages. 
; Without any messages routine is under 70 bytes.
;
; STH and STL from Woz parser is Start address 
; H and L from Woz parser is End address 
;   
            PHP ; LETS TRY A GRACEFUL RETURN TO WOZ??
            PHA ; Kitchen sink.
            PHY ; Just push/pull everything?
            PHX ; 
            SEI             ; Turn off IRQ's, don't want/need.
            ;LDA #$1A        ; 8-N-1, 2400 baud
            ;LDA #$1C        ; 8-N-1, 4800 baud
            ;LDA #$1E        ; 8-N-1, 9600 baud
            ;LDA #$1F        ; 8-N-1, 19200 baud
            LDA #$1F         ;* Init ACIA to 19200 Baud.
            STA ACIA_CTRL
            LDA #$0B        ;* No Parity. No IRQ
            STA ACIA_CMD
            ;Below is just to display messages.
            JSR NewLine
            LDA #<MSG2
            LDX #>MSG2
            JSR SHWMSG      ; Hello Message.
            JSR NewLine
            LDA #<MSG3      ; Show address start/end for load
            LDX #>MSG3
            JSR SHWMSG      ; Space
            LDA #'$'
            JSR ECHO
            LDA STH
            JSR PRBYTE
            LDA STL
            JSR PRBYTE
            LDA #<MSG3
            LDX #>MSG3
            JSR SHWMSG      ;Space
            LDA #'$'
            JSR ECHO   
            LDA H
            JSR PRBYTE
            LDA L
            JSR PRBYTE
            
            JSR NewLine
            LDA #<MSG4
            LDX #>MSG4
            JSR SHWMSG      ;Start Data Transfer MSG.
            JSR NewLine
            ; Done with messages
            ; Load Address from WOZ
            LDA STL
            STA YSAV;TAY ;Y +  start address 0
            STZ STL
            LDY YSAV             ; Low byte in Y 
            JSR GETCHAR          ; Wait to grab first Byte from ACIA. No Timeout.
            JMP BINARY_LOOP_START; Store and do normal loop.
BINARY_LOOP: ; Could  copy GETCHAR here to save cycles.
            JSR GETCHARTO    ; Grab Byte from ACIA. With Timeout
            BCC BINARYTIMEOUT; It timed out. Exit.
BINARY_LOOP_START:           ; Got data. Did not timeout.
            STA (STL),Y      ; Store it at our memory location
            ; Comment out everything down to the to INY if you don't want status
            ; IF YOU WANT JUST STATUS USE:
            ;  LDA #'X' 
            ;  STA ACIA_DAT ;DON'T CARE IF IT GETS DROPPED JUST SEND
            
            ; Below translates to last HEX char for a nice ASCII output
            ; Not at all needed. It just looks neat.
;PRHEX      ; Move inline and just send only last char of Hex      
            AND #$0F        ;Mask LSD for hex print.
            ORA #$B0        ;Add "0".
            CMP #$BA        ;Digit?
            BCC HECHO        ;Yes, output it.
            ADC #$06        ;Add offset for letter.
HECHO:    
            AND #$7F               ;*Change to "standard ASCII"
            STA     ACIA_DAT;DATA  ; Output character.No wait or check so we don't slow down anything. May show garbage.
            ;sta io_putc           ; For Kowalski simulator use:
            ;Check memory pointer for max and INC
            LDX STH         ; Load our high byte
            CPX H           ; Does it match our max?
            BNE NO_HMATCH   ; Nope, just normal inc
            CPY L           ; Does the low byte match our max?
            BNE NO_HMATCH   ; Nope, just normal inc
            JMP BINARY_DONE ; MATCH! We are done!
NO_HMATCH:
            INY             ; Inc low byte
            BNE BINARY_LOOP ; jump if not a roll-over
            INC STH         ; Roll-over. Inc the high byte.
            JMP BINARY_LOOP ; Get more bytes
 
BINARY_DONE:; Data transfer Done
            JSR NewLine     ;New line.
            LDA #<MSG5
            LDX #>MSG5
            JSR SHWMSG      ;Show Finished msg

BINARYEXTRA:; Care about garbage data at end?
            ; *For Streaming Test,jmp back to top 
            ; JMP LOOPMEMORY -If you want to stream, like to the screen buffer.
            ; Could RTS here, but we could overwrite data.
            ; Could  copy GETCHARTO here to save cycles.
            JSR GETCHARTO    ; Grab Byte from ACIA. With Timeout
            BCC BINARYTIMEOUT; Time out
            LDA #'X'         ; 'Garbage' data past end
            JSR ECHO        
            JMP BINARYEXTRA
 
BINARYTIMEOUT: ; Must be finished sending.
            JSR NewLine     ;New line.
            LDA #<MSG6
            LDX #>MSG6
            JSR SHWMSG      ;Show Finished msg
            JSR NewLine     ;New line.
            ; Restore everything
            CLI
            PLX
            PLY
            PLA
            PLP
            ;RTS ;? ISSUES WITH THIS FOR SOME REASON
            JMP RESET       ;Restart Woz. Works well enough.


GETCHAR:    ; Will wait forever for a char, use for first char of timeout load
            LDA ACIA_SR ;STATUS     ; See if we got an incoming char
            AND #$08        ; Test bit 3
            ;LDA io_getc    ; For Kowalski simulator use
            BEQ GETCHAR     ; Wait for character
            LDA ACIA_DAT;DATA    ; Load char
            RTS

GETCHARTO:  ; Get data with Timeout
  phy ; Need to keep Y
;shell_rx_receive_with_timeout:; Started with mike42.me Xmodem timout routine
  ldy #$0 ; Thanks Mike!
y_loop:
  ldx #$0
x_loop:
  lda ACIA_SR;STATUS              ; Check ACIA status in inner loop
  and #$08                     ; Mask rx buffer status flag
  bne rx_got_char
  dex
  bne x_loop
  dey
  bne y_loop
  ply                          ; Need to keep Y
  clc                          ; No byte received in time. Clear Carry as flag
  rts
rx_got_char:
  lda ACIA_DAT ;DATA                ; Get byte from ACIA data port
  ply                          ; Need to keep Y
  sec                          ; Set Carry bit as flag
  rts


NewLine
            PHA
            LDA #$0D
            JSR ECHO        ;* New line.
            LDA #$0A
            JSR ECHO
            PLA
            RTS
 
SHWMSG      ; Changed msg routine to save some bytes
            ; Loads MSG Low byte A High byte X
            ;LDA #<MSG2
            ;LDX #>MSG2
            STA MSGL
            STX MSGH
            ;PHA ; I only msg when A and Y are unused.
            ;PHY ; Save the bytes
            ;jsr NewLine ;Always do a New Line anyway?
            LDY #$0
PRINT:      LDA (MSGL),Y
            BEQ DONE
            JSR ECHO
            INY 
            BNE PRINT
DONE:       ;PLY
            ;PLA
            RTS 

; Moved above into empty space
; ;MSG1        .byte "Woz FL: EhBasic E54E - BadApple F700",0
; MSG1        .byte "Woz FL: BadApple!! 8000 R ",0
; MSG2        .byte "Load Data Start |  Data End",0
; MSG3        .byte "        ",0
; MSG4        .byte " -Start Binary File Transfer-",0
; MSG5        .byte " All Bytes Imported -Done-",0
; MSG6        .byte "-Timeout- NormalLuser Fast Binary Load",0
WozEnd:

 ;.org $E000
 .byte "FastSD Toon Audio WOZ End"



IRQ: ;ROM Based Audio Buffer
; Small 256 byte buffer code, assumes no use of X
; 22 cycles + 13 for IRQ/RTI = 35 cycles, 165,690 cycles a second at 4,734 samples a second. 
 STA IRQTempA	      ; 3
; Is this needed? I thought storing another byte to VIA_SHIFT also cleared the IRQ? 
 LDA #$04           ; 2
 STA VIA_IFR        ; 4 Clear the IRQ 
 
 LDA AudioBuffer,x  ; 4
 STA VIA_SHIFT      ; 4
 INX                ; 2
 LDA IRQTempA       ; 3
 RTI

; RAM Based Audio Buffer
; 19 cycles + 13 IRQ/RTI = 32 total with IFR clear. Needs testing to see if I need the IFR clear.
; IRQPointer: 
;   LDX #$04      ; 2       
;   STX VIA_IFR   ; 4 Clear the IRQ 
;   LDX $2000     ; 4
;   STX $2001     ; 4
;   INC IRQPointer+1 ; 5


; Large Buffer code
;  STA IRQTmpA 
;  LDA (ABufferRead)
;  STA VIA_SHIFT
;  INC ABufferRead
;  BEQ IncTop ;BNE NoTopInc
;  LDA IRQTmpA
;  RTI ;22 cycles here
; IncTop:
;  INC ABufferReadH
;  LDA ABufferReadH
;  CMP #>ABufferEnd
;  BEQ IRQBufferReset ; 10 to here
;  LDA IRQTmpA
;  RTI
; IRQBufferReset: 
;  LDA #>ABufferStart
;  STA ABufferReadH
;  LDA IRQTmpA
; RTI
 
  

 

NMI: ; 5 cycle plus 13 for NMI/RTI = 18 cycles * 60 Vsync for 1,080 cycles a second (1,085.58 at actual 60.31 Vsync)
    DEC VGAClock ; 5 cycles
    RTI

    .org $FFFA
    .word NMI
    .word RESET
    .word IRQ


