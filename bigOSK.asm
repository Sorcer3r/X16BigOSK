.cpu _65c02
#importonce 

// No self modifying code is used in this program

#import "Lib\constants.asm"
#import "Lib\macro.asm"

*=$22 "zeropage" virtual
currentCharacter:       .word 0     
characterDataPointer:   .word 0
CharacterAddressInRom:  .word 0
activeRom: .byte 0
// 8 bytes of data for each of the characters to be displayed
character1: .fill 8,0
character2: .fill 8,0
character3: .fill 8,0

messagePosition: .byte 0
messagepointer:  .byte 0
CharacterColour: .byte 0
cycleDirection:  .byte 0
char1Colour:     .byte 0
char2Colour:     .byte 0
char3Colour:     .byte 0

*=$0801
	BasicUpstart2(bigOSK)

bigOSK:{
    jsr setDisplay
	jsr clearScreen
    // save current rom selection and switch to Character Rom
    lda ROM_BANK
    sta activeRom
	lda #CHARSET_BANK
	sta ROM_BANK

    lda #character1
    sta currentCharacter    //pointer to character data
    ldx #$00
    stx messagePosition     // pointer to position in message
    // copy the character data for the 3 characters in the message
    // to storage in character1-3
loopThroughMessage:
    // calculate position of character x of message in character rom
    jsr calculateCharAddressInRom
	ldy #7                  // we want to copy 8 bytes of data
characterDataLoop:
	lda (CharacterAddressInRom),y    // get character data
	sta (currentCharacter),y         // save it in our table
    dey
	bpl characterDataLoop          // do it 8 times (Until counter goes below 0)
    lda currentCharacter
    clc
    adc #8
    sta currentCharacter    // move pointer to next 8 bytes in table
    inc messagePosition     // point to next character in message
    ldx messagePosition
    cpx #3
    bne loopThroughMessage  // if we havent done 3 characters do it again
	
    //switch rom selection back to what it was (probably not needed but keeps things neat)
    lda activeRom
    sta ROM_BANK

    //setup vera parameters and set colour 2 and 3 to white
    addressRegister(0, VRAMPalette+4,1,0)
    sta VERADATA0
    sta VERADATA0
    sta VERADATA0
    sta VERADATA0

    // lets draw OSK in Black
    lda #$04            // use secondary position to draw shadow
    sta messagePosition
    stz messagepointer
    jsr DrawMessage

    // now draw OSK in white
    stz messagePosition     // use primary position 
    stz messagepointer
    jsr DrawMessage

    // now do things with colours
    // initialise everything for the colour cycling
    lda #$fa
    sta VERAAddrHigh        // point data0 to palette
    lda #$00                // point to 3 different start points in the colour list
    sta char1Colour
    lda #$03
    sta char2Colour
    lda #$06
    sta char3Colour

colourCycle:
    wai
    wai
    wai         // wait a while
    lda #$02
    sta VERAAddrLow     // pint to color 1 in palette
    tay                 // and put 2 in Y while we have it :)
colourLoop:
    ldx char1Colour,y   // get character colour pointer
    lda colourTableGB,x // get GB colour
    sta VERADATA0
    lda colourTableR,x  // get R part of colour
    sta VERADATA0
    dey                 // do it for all 3 characters
    bpl colourLoop
    ldx #$02
updateColours:
    lda char1Colour,x   // increment each of the colour table pointers
    inc
    and #$1f            // but keep them in range 0-31
    sta char1Colour,x
    dex
    bpl updateColours    
    bra colourCycle     // do it all again, forever!

DrawMessage:{
    ldx messagePosition
    lda characterPositionsY,x  // get row to start drawing character at
    clc
    adc #$B0                    // calculate vera high byte
    sta VERAAddrHigh
    lda characterPositionsX,x   // get column to draw character at
    asl                         // double it because 2 bytes per character position (Character,Colour)
    sta VERAAddrLow
    lda colourList,x
    sta CharacterColour
    jsr drawCharacter
    inc messagePosition         // move to next position in table
    inc messagepointer          // move to next character
    lda messagepointer          
    cmp #3                      // have we drawn all 3?
    bne DrawMessage
    rts
}

drawCharacter:{	
    lda messagepointer      // which character are we drawing (0-2)
    asl 
    asl
    asl                     // *8 to point to correct set of data
    clc
    adc #character1         //calculate which character data to use
    sta characterDataPointer
    ldx #$08                // row counter
Row:
    lda (characterDataPointer)  // get data for this row of the character
    ldy #$08                // there are 8 bits
Line:
    asl                     // move bit 7 into carry
    sta currentCharacter    // save it for next time round
    bcs drawBlock           // if carry then we need to draw a character
    lda VERADATA0
    lda VERADATA0           // otherwise skip 2 bytes since bit is not set
    bra nextBlock
drawBlock:
	lda #$A0                // character to draw on screen (White Block)
    sta VERADATA0
    lda CharacterColour     // get colour for this character
	sta VERADATA0
nextBlock:
    lda currentCharacter    //get currentcharacter data back
    dey
	bne Line                // repeat for all 8 bits of the row
    lda VERAAddrLow
    sec
    sbc #16                 // move X back 8 characters
    sta VERAAddrLow
    inc VERAAddrHigh        // move Y down 1 row
    inc characterDataPointer
    dex
    bne Row                 // repeat for 8 rows 
    rts
}

// set display to 40*30 chars
setDisplay:{
	setDCSel(0)
	lda #$40			//64 double H,V
	sta VERA_DC_hscale
	sta VERA_DC_vscale
	rts
}

// clear screen
clearScreen:{
	ldx #30     // 30 lines
	addressRegister(0,VRAM_layer1_map,1,0)
rows:
	ldy #80		// 40 char+40colour
columns:
    lda #$20    // Space character
	sta VERADATA0
    lda #$61    // Blue background (6), White Foreground (1)
	sta VERADATA0
	dey         
	bne columns     // repeat for all of this row
	stz VERAAddrLow
	inc VERAAddrHigh
	dex
	bne rows    // repeat for all 30 rows
	rts
}

// x = character position in message
// multiply character by 8 to calculate 16 bit address pointer to Rom data
// returns with address of character data in CharacterAddressInRom
calculateCharAddressInRom:{
    stz CharacterAddressInRom+1 // zero high byte of address pointer
    lda message,x               // get the character we want the pattern for
    asl                         // Multiply by 2
    rol CharacterAddressInRom+1 // move any carry into high byte
    asl                         // Multiply by 2 (*4)
    rol CharacterAddressInRom+1 // move any carry bit into high byte
    asl                         // Multiply by 2 (*8)
    rol CharacterAddressInRom+1 // move any carry bit into high byte
    sta CharacterAddressInRom
    lda #>ROM_BASE              // get high byte of Rom base
    clc
    adc CharacterAddressInRom+1 // add it to the high byte
    sta CharacterAddressInRom+1 // store high byte of character address
    rts
}

.encoding "screencode_upper"
message:
    .text "OSK"
characterPositionsX:    // Col
    .byte 8,16,24,0,9,17,25,0
characterPositionsY:    // Row
    .byte 11,11,11,0,12,12,12,0
colourList:             // colours to use for characters
    .byte $61,$62,$63,$00,$60,$60,$60,$60

// colour tables for updating palette
colourTableGB:
.byte $33, $46, $59, $6C, $7F, $AE, $BD, $CC
.byte $DB, $EA, $FA, $FB, $FC, $FD, $FE, $FF
.byte $FF, $E6, $D5, $C4, $B3, $A2, $91, $80
.byte $70, $60, $50, $40, $30, $20, $10, $00

colourTableR:
.byte $03, $03, $03, $03, $03, $04, $05, $06
.byte $07, $08, $09, $0A, $0B, $0C, $0D, $0E
.byte $0F, $0F, $0F, $0F, $0F, $0E, $0D, $0C
.byte $0B, $0A, $09, $08, $07, $06, $05, $04

}