LF	equ	0AH		;line feed
CR	equ	0DH		;carriage RETurn
DOT equ     '.'
CONOUT equ 2
BDOS equ 5

    org 0100H
    jp START

    include "ch376s.asm"

START:
    CALL	printInline
    DB "Check CH376s communication."
    DB CR,LF,0

    ;CALL	printInline
    ;DB "Send the inverse alphabet and retrieve the right one back"
    ;DB CR,LF,0

    ld a, CH_CMD_RESET_ALL
    CH_SEND_COMMAND   
    CH_END_COMMAND 
    ld bc, WAIT_ONE_SECOND/5
	call WAIT

    ; make MISO the INT line
	call CH_SET_SD0_INT    

    ;jr SKIP

ilikeit:
    ld b, 26
    ld de, BUFFER
again:
    ; send command
    ; ============
    ld a,CH_CMD_CHECK_EXIST
    CH_SEND_COMMAND
    
    ; send and print value
    ; ============
    ld a, b 
    add a,0beh-26
    CH_SEND_DATA

    ; get inverse value back from CH376s
    ; ============    
    CH_RECEIVE_DATA
    ; store result in buffer
    ld (de),a ; complement should A-Z
    inc de
    
    CH_END_COMMAND
    djnz again
    
    call CH_CHECK_INT_IS_ACTIVE
    jr z,.NO_INT
    ld a, '1'
    jr .NEXT
.NO_INT
    ld a, '0'
.NEXT
    ld (de),a

    call printbuffer

SKIP:
    ; reset USB bus and device
    call USB_HOST_BUS_RESET

    ; DEBUG
    push af
	ld a, 0
	out 2fh, a
    pop af
	; DEBUG

    ld d, 0 ; from reset device
    ld hl, DEVICE_DESCRIPTOR
	call CH_GET_DEVICE_DESCRIPTOR
    jr nc, .disk_connected
    push af
    CALL	printInline
    DB "Disk NOT connected: ",0
    pop af
    call print_a_decimal
    DB CR,LF,0

    ; DEBUG
    push af
	ld a, 1
	out 2fh, a
    pop af
	; DEBUG

    ret

.disk_connected
    CALL	printInline
    DB "Disk connected: ",0
    ld hl, DEVICE_DESCRIPTOR
    ld a, (hl)
    call print_a_decimal
    call printInline
    DB CR,LF,0

    ; DEBUG
    push af
	ld a, 1
	out 2fh, a
    pop af
	; DEBUG

    ld a, (DEVICE_DESCRIPTOR+7)
    push af
    CALL	printInline
    DB "USB packetsize: ",0
    pop af
    push af
    call print_a_decimal
    CALL	printInline
    DB CR,LF,0
    pop af
    ld b, a
    ld a, 1
    call CH_SET_ADDRESS
    jr nc, .usb_address

    push af
    CALL	printInline
    DB "USB address NOT set: ",0
    pop af
    call print_a_decimal
    CALL	printInline
    DB CR,LF,0
    ret

.usb_address
    CALL	printInline
    DB "USB address set",CR,LF,0

    ld a, (DEVICE_DESCRIPTOR+7)
    ld b, a
    ld c, 100
    ld d, 1
    ld a, 0
    ld hl, CONFIG_DESCRIPTOR
    call CH_GET_CONFIG_DESCRIPTOR ; call first with max packet size to discover real size
    jr nc, .config
    push af
    call printInline
    db "configuration not read: ",0
    pop af
    call print_a_decimal
    call printInline
    DB CR,LF,0
    ret

.config
    CALL	printInline
    DB "USB configuration: ",0
    ld hl, CONFIG_DESCRIPTOR
    ld a, (hl)
    call print_a_decimal
    call printInline
    DB CR,LF,0

    ret

; --------------------------------------
; CH_GET_CONFIG_DESCRIPTOR
;
; Input: HL=pointer to memory to receive config descriptor
;        A=configuration index starting with 0 to DEVICE_DESCRIPTOR.bNumConfigurations
;        B=max_packetsize
;        C=config_descriptor_size
;        D=device address 
; Output: Cy=0 no error, Cy=1 error
CH_GET_CONFIG_DESCRIPTOR:
    push iy,ix,hl,de,bc
    ld iy, hl ; Address of the input or output data buffer

    ; get SLTWRK in HL for this ROM page
    ld hl, CMD_GET_CONFIG_DESCRIPTOR
    
    ld ix, hl
    ld (ix+2), a
    ld (ix+6), c
    ld a, d ; device address
    ld de, iy ; Address of the input or output data buffer
    call HW_CONTROL_TRANSFER
    pop bc,de,hl,ix,iy
    cp CH_USB_INT_SUCCESS
    ret z ; no error
    scf ; error
    ret

; --------------------------------------
; CH_SET_ADDRESS
;
; Input: A=address to assign to connected USB device
;        B=packetsize
; Output: Cy=0 no error, Cy=1 error
CH_SET_ADDRESS:
    push ix,hl,de
    ld de, hl ; Address of the input or output data buffer
    ld hl, CMD_SET_ADDRESS
    ld ix, hl
    ld (ix+2),a
    ld a, 0 ; device address
    call HW_CONTROL_TRANSFER
    pop de,hl,ix
    cp CH_USB_INT_SUCCESS
    ret z ; no error
    scf ; error
    ret

; --------------------------------------
; CH_GET_DEVICE_DESCRIPTOR
;
; Input: HL=pointer to memory to receive device descriptor
;        D =device address
; Output: Cy=0 no error, Cy=1 error
;         A  = USB error code
;         BC = Amount of data actually transferred (if IN transfer and no error)
CH_GET_DEVICE_DESCRIPTOR:
    push ix,hl,de,bc
    ld a, d ; device address
    ld de, hl ; Address of the input or output data buffer
    ; return USB descriptor stored in WRKAREA
    ld hl, CMD_GET_DEVICE_DESCRIPTOR
    ld b, 8 ; length in bytes
    call HW_CONTROL_TRANSFER
    pop bc,de,hl,ix
    cp CH_USB_INT_SUCCESS
    ret z ; no error
    scf ; error
    ret

wait_for_insert:
    jr wait_for_insert_start
wait_for_insert_again:
    ld a, '.'
    call printa
    ld bc, WAIT_ONE_SECOND/2
	call WAIT
wait_for_insert_start:
    call CH_GET_STATUS
    cp CH_USB_INT_CONNECT
    jr nz,wait_for_insert_again

    ld a, "\r"
	call printa
    ld a, "\n"
	call printa
    ret

USB_HOST_BUS_RESET:
    ld a, CH_MODE_HOST
    call CH_SET_USB_MODE
    call wait_for_insert
	; reset BUS
   	ld a, CH_MODE_HOST_RESET ; HOST, reset bus
    call CH_SET_USB_MODE
	; wait a bit longer
	ld bc, WAIT_ONE_SECOND
	call WAIT
	; reset DEVICE
    ld a, CH_MODE_HOST
    call CH_SET_USB_MODE
    ret c
	; wait ~250ms
	ld bc, WAIT_ONE_SECOND/4
	call WAIT

    ; check IC version
    CALL	printInline
    DB "Device version: ",0
    ld a, CH_CMD_GET_IC_VER
    CH_SEND_COMMAND
    CH_RECEIVE_DATA
    CH_END_COMMAND
    and 1fh
    push af
    call print_a_decimal
    CALL	printInline
    DB CR,LF,0
    pop af
    ; ONLY WHEN VERSION 3?
    cp 3
    jr nz, .not_three
    CALL	printInline
    DB "Unstalling device",CR,LF,0
    ld a, CH_CMD_CLR_STALL
    CH_SEND_COMMAND
    ld a, 80h
    CH_SEND_DATA
    CH_END_COMMAND
.not_three
    or a ; clear Cy
	ret

WAIT_ONE_SECOND	equ 60 ; max 60Hz

;-----------------------------------------------------------------------------
;
; Wait a determined number of interrupts
; Input: BC = number of 1/framerate interrupts to wait
; Output: (none)
WAIT:
	halt
	dec bc
	ld a,b
	or c
	jr nz, WAIT
	ret


; printing routines
; -----------------
print_a_decimal:
    and 7fh
    ld b,0
.noemer
    cp 0Ah
    jr nc,.above_nine
    jr .below_ten
.above_nine
    sub 0Ah
    inc b
    jr .noemer
.below_ten
    push af
    ld a, b
    add 0x30
    call printa
    pop af
    add 0x30
    call printa
    CALL	printInline
    DB CR,LF,0
    ret
printa:
    push bc,de,hl
    ld e, a
    ld c, CONOUT
    call BDOS
    pop hl,de,bc
    ret

printInline:
    EX 	(SP),HL 	; PUSH HL and put RET ADDress into HL
    push af
nextILChar:	LD 	A,(HL)
    CP	0
    JR	Z,endOfPrint
    ;
    call printa
    ;
    INC HL
    JR	nextILChar
endOfPrint:	INC 	HL 		; Get past "null" terminator
    pop af
    EX 	(SP),HL 	; PUSH new RET ADDress on stack and restore HL
    RET

printbuffer:
    CALL	printInline

BUFFER:
    DS 27,0
    DB CR,LF,0
    RET

DEVICE_DESCRIPTOR:
    DS 18,0

CONFIG_DESCRIPTOR:
    DS 50,0