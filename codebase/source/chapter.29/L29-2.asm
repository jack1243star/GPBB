;
; *** Listing 7.2 ***
;
; Program to restore a mode 10h EGA graphics screen from
; the file SNAPSHOT.SCR.
;
; Assembled with TASM 4.0, linked with TLINK 6.10
; Checked by Jim Mischel 11/21/94
;
VGA_SEGMENT	equ	0a000h
SC_INDEX		equ	3c4h	;Sequence Controller Index register
MAP_MASK		equ	2	;Map Mask register index in SC
DISPLAYED_SCREEN_SIZE equ (640/8)*350
				;# of displayed bytes per plane in a
				; hi-res graphics screen
;
stack	segment para stack 'STACK'
	db	512 dup (?)
stack	ends
;
Data	segment	word 'DATA'
Filename db	'SNAPSHOT.SCR',0 ;name of file we're restoring from
ErrMsg1	db	'*** Couldn''t open SNAPSHOT.SCR ***',0dh,0ah,'$'
ErrMsg2	db	'*** Error reading from SNAPSHOT.SCR ***',0dh,0ah,'$'
WaitKeyMsg db	0dh, 0ah, 'Done. Press any key to end...',0dh,0ah,'$'
Handle	dw	?	;handle of file we're restoring from
Plane	db	?	;plane being written
Data	ends
;
Code	segment
	assume	cs:Code, ds:Data
Start	proc	near
	mov	ax,Data
	mov	ds,ax
;
; Go to hi-res graphics mode.
;
	mov	ax,10h		;AH = 0 means mode set, AL = 10h selects
				; hi-res graphics mode
	int	10h		;BIOS video interrupt
;
; Open SNAPSHOT.SCR.
;
	mov	ah,3dh		;DOS open file function
	mov	dx,offset Filename
	sub	al,al		;open for reading
	int	21h
	mov	[Handle],ax	;save the handle
	jnc	RestoreTheScreen ;we're ready to restore if no error
	mov	ah,9		;DOS print string function
	mov	dx,offset ErrMsg1
	int	21h		;notify of the error
	jmp	short Done	;and done
;
; Loop through the 4 planes, making each writable in turn and
; reading it from disk. Note that all 4 planes are writable at
; A000:0000; the Map Mask register selects which planes are readable
; at any one time. We only make one plane readable at a time.
;
RestoreTheScreen:
	mov	[Plane],0	;start with plane 0
RestoreLoop:
	mov	dx,SC_INDEX
	mov	al,MAP_MASK	;set SC Index to Map Mask register
	out	dx,al
	inc	dx
	mov	cl,[Plane]	;get the # of the plane we want
				; to restore
	mov	al,1
	shl	al,cl		;set the bit enabling writes to
				; only the one desired plane
	out	dx,al		;set to read from the desired plane
	mov	ah,3fh		;DOS read from file function
	mov	bx,[Handle]
	mov	cx,DISPLAYED_SCREEN_SIZE ;# of bytes to read
	sub	dx,dx		;start loading bytes at A000:0000
	push	ds
	mov	si,VGA_SEGMENT
	mov	ds,si
	int	21h		;read the displayed portion of this plane
	pop	ds
	jc	ReadError
	cmp	ax,DISPLAYED_SCREEN_SIZE ;did all bytes get read?
	jz	RestoreLoopBottom
ReadError:
	mov	ah,9		;DOS print string function
	mov	dx,offset ErrMsg2
	int	21h		;notify about the error
	jmp	short DoClose	;and done
RestoreLoopBottom:
	mov	al,[Plane]
	inc	ax		;point to the next plane
	mov	[Plane],al
	cmp	al,3		;have we done all planes?
	jbe	RestoreLoop 	;no, so do the next plane
;
; Close SNAPSHOT.SCR.
;
DoClose:
	mov	ah,3eh		;DOS close file function
	mov	bx,[Handle]
	int	21h
;
; Wait for a keypress.
;
	mov	ah,8		;DOS input without echo function
	int	21h
;
; Restore text mode.
;
	mov	ax,3
	int	10h
;
; Done.
;
Done:
	mov	ah,4ch		;DOS terminate function
	int	21h
Start	endp
Code	ends
	end	Start
