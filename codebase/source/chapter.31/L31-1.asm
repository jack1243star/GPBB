; *** Listing 9.1 ***
;
; Program to demonstrate pixel drawing in 320x400 256-color
; mode on the VGA. Draws 8 lines to form an octagon, a pixel
; at a time. Draws 8 octagons in all, one on top of the other,
; each in a different color set. Although it's not used, a
; pixel read function is also provided.
;
; Assembled with TASM 4.0, linked with TLINK 6.10
; Checked by Jim Mischel 11/21/94
;
VGA_SEGMENT	equ	0a000h
SC_INDEX		equ	3c4h	;Sequence Controller Index register
GC_INDEX		equ	3ceh	;Graphics Controller Index register
CRTC_INDEX	equ	3d4h	;CRT Controller Index register
MAP_MASK		equ	2	;Map Mask register index in SC
MEMORY_MODE	equ	4	;Memory Mode register index in SC
MAX_SCAN_LINE	equ	9	;Maximum Scan Line reg index in CRTC
START_ADDRESS_HIGH equ	0ch	;Start Address High reg index in CRTC
UNDERLINE	equ	14h	;Underline Location reg index in CRTC
MODE_CONTROL	equ	17h	;Mode Control register index in CRTC
READ_MAP		equ	4	;Read Map register index in GC
GRAPHICS_MODE	equ	5	;Graphics Mode register index in GC
MISCELLANEOUS	equ	6	;Miscellaneous register index in GC
SCREEN_WIDTH	equ	320	;# of pixels across screen
SCREEN_HEIGHT	equ	400	;# of scan lines on screen
WORD_OUTS_OK	equ	1	;set to 0 to assemble for
				; computers that can't handle
				; word outs to indexed VGA registers
;
stack	segment para stack 'STACK'
		db	512 dup (?)
stack	ends
;
Data	segment	word 'DATA'
;
BaseColor	db	0
;
; Structure used to control drawing of a line.
;
LineControl	struc
StartX		dw	?
StartY		dw	?
LineXInc		dw	?
LineYInc		dw	?
BaseLength	dw	?
LineColor	db	?
LineControl	ends
;
; List of descriptors for lines to draw.
;
LineList	label	LineControl
	LineControl	<130,110,1,0,60,0>
	LineControl	<190,110,1,1,60,1>
	LineControl	<250,170,0,1,60,2>
	LineControl	<250,230,-1,1,60,3>
	LineControl	<190,290,-1,0,60,4>
	LineControl	<130,290,-1,-1,60,5>
	LineControl	<70,230,0,-1,60,6>
	LineControl	<70,170,1,-1,60,7>
	LineControl	<-1,0,0,0,0,0>
Data	ends
;
; Macro to output a word value to a port.
;
OUT_WORD	macro
if WORD_OUTS_OK
	out	dx,ax
else
	out	dx,al
	inc	dx
	xchg	ah,al
	out	dx,al
	dec	dx
	xchg	ah,al
endif
	endm
;
; Macro to output a constant value to an indexed VGA register.
;
CONSTANT_TO_INDEXED_REGISTER	macro	ADDRESS, INDEX, VALUE
	mov	dx,ADDRESS
	mov	ax,(VALUE shl 8) + INDEX
	OUT_WORD
	endm
;
Code	segment
	assume	cs:Code, ds:Data
Start	proc	near
	mov	ax,Data
	mov	ds,ax
;
; Set 320x400 256-color mode.
;
	call	Set320By400Mode
;
; We're in 320x400 256-color mode. Draw each line in turn.
;
ColorLoop:
	mov	si,offset LineList ;point to the start of the
				; line descriptor list
LineLoop:
	mov	cx,[si+StartX]	;set the initial X coordinate
	cmp	cx,-1
	jz	LinesDone	;a descriptor with a -1 X
				; coordinate marks the end
				; of the list
	mov	dx,[si+StartY]	   ;set the initial Y coordinate,
	mov	bl,[si+LineColor]  ; line color,
	mov	bp,[si+BaseLength] ; and pixel count
	add	bl,[BaseColor]	;adjust the line color according
				; to BaseColor
PixelLoop:
	push	cx		;save the coordinates
	push	dx
	call	WritePixel	;draw this pixel
	pop	dx		;retrieve the coordinates
	pop	cx
	add	cx,[si+LineXInc] ;set the coordinates of the
	add	dx,[si+LineYInc] ; next point of the line
	dec	bp		;any more points?
	jnz	PixelLoop	;yes, draw the next
	add	si,size LineControl ;point to the next line descriptor
	jmp	LineLoop	; and draw the next line
LinesDone:
	call	GetNextKey	;wait for a key, then
	inc	[BaseColor]	; bump the color selection and
	cmp	[BaseColor],8	; see if we're done
	jb	ColorLoop	;not done yet
;
; Wait for a key and return to text mode and end when
; one is pressed.
;
	call	GetNextKey
	mov	ax,0003h
	int	10h	;text mode
	mov	ah,4ch
	int	21h	;done
;
Start	endp
;
; Sets up 320x400 256-color modes.
;
; Input: none
;
; Output: none
;
Set320By400Mode	proc	near
;
; First, go to normal 320x200 256-color mode, which is really a
; 320x400 256-color mode with each line scanned twice.
;
	mov	ax,0013h ;AH = 0 means mode set, AL = 13h selects
 			 ; 256-color graphics mode
	int	10h	 ;BIOS video interrupt
;
; Change CPU addressing of video memory to linear (not odd/even,
; chain, or chain 4), to allow us to access all 256K of display
; memory. When this is done, VGA memory will look just like memory
; in modes 10h and 12h, except that each byte of display memory will
; control one 256-color pixel, with 4 adjacent pixels at any given
; address, one pixel per plane.
;
	mov	dx,SC_INDEX
	mov	al,MEMORY_MODE
	out	dx,al
	inc	dx
	in	al,dx
	and	al,not 08h	;turn off chain 4
	or	al,04h		;turn off odd/even
	out	dx,al
	mov	dx,GC_INDEX
	mov	al,GRAPHICS_MODE
	out	dx,al
	inc	dx
	in	al,dx
	and	al,not 10h	;turn off odd/even
	out	dx,al
	dec	dx
	mov	al,MISCELLANEOUS
	out	dx,al
	inc	dx
	in	al,dx
	and	al,not 02h	;turn off chain
	out	dx,al
;
; Now clear the whole screen, since the mode 13h mode set only
; cleared 64K out of the 256K of display memory. Do this before
; we switch the CRTC out of mode 13h, so we don't see garbage
; on the screen when we make the switch.
;
	CONSTANT_TO_INDEXED_REGISTER SC_INDEX,MAP_MASK,0fh
				;enable writes to all planes, so
				; we can clear 4 pixels at a time
	mov	ax,VGA_SEGMENT
	mov	es,ax
	sub	di,di
	mov	ax,di
	mov	cx,8000h	;# of words in 64K
	cld
	rep	stosw		;clear all of display memory
;
; Tweak the mode to 320x400 256-color mode by not scanning each
; line twice.
;
	mov	dx,CRTC_INDEX
	mov	al,MAX_SCAN_LINE
	out	dx,al
	inc	dx
	in	al,dx
	and	al,not 1fh	;set maximum scan line = 0
	out	dx,al
	dec	dx
;
; Change CRTC scanning from doubleword mode to byte mode, allowing
; the CRTC to scan more than 64K of video data.
;
	mov	al,UNDERLINE
	out	dx,al
	inc	dx
	in	al,dx
	and	al,not 40h	;turn off doubleword
	out	dx,al
	dec	dx
	mov	al,MODE_CONTROL
	out	dx,al
	inc	dx
	in	al,dx
	or	al,40h	;turn on the byte mode bit, so memory is
			; scanned for video data in a purely
			; linear way, just as in modes 10h and 12h
	out	dx,al
	ret
Set320By400Mode	endp
;
; Draws a pixel in the specified color at the specified
; location in 320x400 256-color mode.
;
; Input:
;	CX = X coordinate of pixel
;	DX = Y coordinate of pixel
;	BL = pixel color
;
; Output: none
;
; Registers altered: AX, CX, DX, DI, ES
;
WritePixel	proc	near
	mov	ax,VGA_SEGMENT
	mov	es,ax	;point to display memory
	mov	ax,SCREEN_WIDTH/4
			;there are 4 pixels at each address, so
			; each 320-pixel row is 80 bytes wide
			; in each plane
	mul	dx	;point to start of desired row
	push	cx	;set aside the X coordinate
	shr	cx,1	;there are 4 pixels at each address
	shr	cx,1	; so divide the X coordinate by 4
	add	ax,cx	;point to the pixel's address
	mov	di,ax
	pop	cx	;get back the X coordinate
	and	cl,3	;get the plane # of the pixel
	mov	ah,1
	shl	ah,cl	;set the bit corresponding to the plane
			; the pixel is in
	mov	al,MAP_MASK
	mov	dx,SC_INDEX
	OUT_WORD	        ;set to write to the proper plane for
			; the pixel
	mov	es:[di],bl	;draw the pixel
	ret
WritePixel	endp
;
; Reads the color of the pixel at the specified location in 320x400
; 256-color mode.
;
; Input:
;	CX = X coordinate of pixel to read
;	DX = Y coordinate of pixel to read
;
; Output:
;	AL = pixel color
;
; Registers altered: AX, CX, DX, SI, ES
;
ReadPixel	proc	near
	mov	ax,VGA_SEGMENT
	mov	es,ax	;point to display memory
	mov	ax,SCREEN_WIDTH/4
			;there are 4 pixels at each address, so
			; each 320-pixel row is 80 bytes wide
			; in each plane
	mul	dx	;point to start of desired row
	push	cx	;set aside the X coordinate
	shr	cx,1	;there are 4 pixels at each address
	shr	cx,1	; so divide the X coordinate by 4
	add	ax,cx	;point to the pixel's address
	mov	si,ax
	pop	ax	;get back the X coordinate
	and	al,3	;get the plane # of the pixel
	mov	ah,al
	mov	al,READ_MAP
	mov	dx,GC_INDEX
	OUT_WORD		;set to read from the proper plane for
			; the pixel
	lods	byte ptr es:[si] ;read the pixel
	ret
ReadPixel	endp
;
; Waits for the next key and returns it in AX.
;
; Input: none
;
; Output:
;	AX = full 16-bit code for key pressed
;
GetNextKey	proc	near
WaitKey:
	mov	ah,1
	int	16h
	jz	WaitKey	;wait for a key to become available
	sub	ah,ah
	int	16h	;read the key
	ret
GetNextKey	endp
;
Code	ends
;
	end	Start
