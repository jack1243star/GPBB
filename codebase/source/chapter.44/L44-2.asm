; Low-level animation routines.
; Tested with TASM 4.0 by Jim Mischel 12/16/94.

SCREEN_WIDTH    equ     80      ;screen width in bytes
INPUT_STATUS_1  equ     03dah   ;Input Status 1 register
CRTC_INDEX      equ     03d4h   ;CRT Controller Index reg
START_ADDRESS_HIGH equ  0ch     ;bitmap start address high byte
START_ADDRESS_LOW equ   0dh     ;bitmap start address low byte
GC_INDEX        equ     03ceh   ;Graphics Controller Index reg
SET_RESET       equ     0       ;GC index of Set/Reset reg
G_MODE          equ     5       ;GC index of Mode register

        .model  small
        .data
BIOS8x8Ptr dd   ?       ;points to BIOS 8x8 font
; Tables used to look up left and right clip masks.
LeftMask db     0ffh, 07fh, 03fh, 01fh, 00fh, 007h, 003h, 001h
RightMask db    080h, 0c0h, 0e0h, 0f0h, 0f8h, 0fch, 0feh, 0ffh

        .code
; Draws the specified filled rectangle in the specified color.
; Assumes the display is in mode 12h. Does not clip and assumes
; rectangle coordinates are valid.
;
; C near-callable as: void DrawRect(int LeftX, int TopY, int RightX,
;       int BottomY, int Color, unsigned int ScrnOffset,
;       unsigned int ScrnSegment);

DrawRectParms   struc
        dw      2 dup (?) ;pushed BP and return address
LeftX   dw      ?       ;X coordinate of left side of rectangle
TopY    dw      ?       ;Y coordinate of top side of rectangle
RightX  dw      ?       ;X coordinate of right side of rectangle
BottomY dw      ?       ;Y coordinate of bottom side of rectangle
Color   dw      ?       ;color in which to draw rectangle (only the
                        ; lower 4 bits matter)
ScrnOffset dw   ?       ;offset of base of bitmap in which to draw
ScrnSegment dw  ?       ;segment of base of bitmap in which to draw
DrawRectParms   ends

        public  _DrawRect
_DrawRect       proc    near
        push    bp      ;preserve caller's stack frame
        mov     bp,sp   ;point to local stack frame
        push    si      ;preserve caller's register variables
        push    di

        cld
        mov     dx,GC_INDEX
        mov     al,SET_RESET
        mov     ah,byte ptr Color[bp]
        out     dx,ax   ;set the color in which to draw
        mov     ax,G_MODE + (0300h)
        out     dx,ax   ;set to write mode 3
        les     di,dword ptr ScrnOffset[bp] ;point to bitmap start
        mov     ax,SCREEN_WIDTH
        mul     TopY[bp]        	;point to the start of the top scan
        add     di,ax           	; line to fill
        mov     ax,LeftX[bp]
        mov     bx,ax
        shr     ax,1    		;/8 = byte offset from left of screen
        shr     ax,1
        shr     ax,1
        add     di,ax   		;point to the upper left corner of fill area
        and     bx,7    		;isolate intrapixel address
        mov     dl,LeftMask[bx] 	;set the left-edge clip mask
        mov     bx,RightX[bp]
        mov     si,bx
        and     bx,7    		;isolate intrapixel address of right edge
        mov     dh,RightMask[bx] ;set the right-edge clip mask
        mov     bx,LeftX[bp]
        and     bx,NOT 7 	;intrapixel address of left edge
        sub     si,bx
        shr     si,1
        shr     si,1
        shr     si,1    		;# of bytes across spanned by rectangle - 1
        jnz     MasksSet 	;if there's only one byte across,
        and     dl,dh   		; combine the masks
MasksSet:
        mov     bx,BottomY[bp]
        sub     bx,TopY[bp] 	;# of scan lines to fill - 1
FillLoop:
        push    di      		;remember line start offset
        mov     al,dl   		;left edge clip mask
        xchg    es:[di],al 	;draw the left edge
        inc     di      		;point to the next byte
        mov     cx,si   		;# of bytes left to do
        dec     cx      		;# of bytes left to do - 1
        js      LineDone 	;that's it if there's only 1 byte across
        jz      DrawRightEdge 	;no middle bytes if only 2 bytes across
        mov     al,0ffh 		;non-edge bytes are solid
        rep     stosb   		;draw the solid bytes across the middle
DrawRightEdge:
        mov     al,dh   		;right edge clip mask
        xchg    es:[di],al 	;draw the right edge
LineDone:
        pop     di      		;retrieve line start offset
        add     di,SCREEN_WIDTH 	;point to the next line
        dec     bx      		;count off scan lines
        jns     FillLoop

        pop     di      		;restore caller's register variables
        pop     si
        pop     bp      		;restore caller's stack frame
        ret
_DrawRect       endp

; Shows the page at the specified offset in the bitmap. Page is
; displayed when this routine returns.
;
; C near-callable as: void ShowPage(unsigned int StartOffset);

ShowPageParms   struc
        dw      2 dup (?) 	;pushed BP and return address
StartOffset dw  ?       		;offset in bitmap of page to display
ShowPageParms   ends

        public  _ShowPage
_ShowPage       proc    near
        push    bp      		;preserve caller's stack frame
        mov     bp,sp   		;point to local stack frame
; Wait for display enable to be active (status is active low), to be
; sure both halves of the start address will take in the same frame.
        mov     bl,START_ADDRESS_LOW	    	;preload for fastest
        mov     bh,byte ptr StartOffset[bp] 	; flipping once display
        mov     cl,START_ADDRESS_HIGH	    	; enable is detected
        mov     ch,byte ptr StartOffset+1[bp]
        mov     dx,INPUT_STATUS_1
WaitDE:
        in      al,dx
        test    al,01h
        jnz     WaitDE  		;display enable is active low (0 = active)
; Set the start offset in display memory of the page to display.
        mov     dx,CRTC_INDEX
	mov	ax,bx
        out     dx,ax		;start address low
	mov	ax,cx
        out     dx,ax		;start address high
; Now wait for vertical sync, so the other page will be invisible when
; we start drawing to it.
        mov     dx,INPUT_STATUS_1
WaitVS:
        in      al,dx
        test    al,08h
        jz      WaitVS  		;vertical sync is active high (1 = active)
        pop     bp      		;restore caller's stack frame
        ret
_ShowPage       endp

; Displays the specified image at the specified location in the
; specified bitmap, in the desired color.
;
; C near-callable as: void DrawImage(int LeftX, int TopY,
;       image **RotationTable, int Color, unsigned int ScrnOffset,
;       unsigned int ScrnSegment);

DrawImageParms  struc
        dw      2 dup (?) 	;pushed BP and return address
DILeftX dw      ?       		;X coordinate of left side of image
DITopY  dw      ?       		;Y coordinate of top side of image
RotationTable dw ?      		;pointer to table of pointers to image
                        		; rotations
DIColor dw      ?       		;color in which to draw image (only the
                       	 	; lower 4 bits matter)
DIScrnOffset dw ?       		;offset of base of bitmap in which to draw
DIScrnSegment dw ?      		;segment of base of bitmap in which to draw
DrawImageParms  ends

image struc
WidthInBytes    dw      ?
Height          dw      ?
BitPattern      dw      ?
image ends

        public  _DrawImage
_DrawImage      proc    near
        push    bp      		;preserve caller's stack frame
        mov     bp,sp   		;point to local stack frame
        push    si      		;preserve caller's register variables
        push    di

        cld
        mov     dx,GC_INDEX
        mov     al,SET_RESET
        mov     ah,byte ptr DIColor[bp]
        out     dx,ax   		;set the color in which to draw
        mov     ax,G_MODE + (0300h)
        out     dx,ax   		;set to write mode 3
        les     di,dword ptr DIScrnOffset[bp] ;point to bitmap start
        mov     ax,SCREEN_WIDTH
        mul     DITopY[bp]      	;point to the start of the top scan
        add     di,ax           	; line on which to draw
        mov     ax,DILeftX[bp]
        mov     bx,ax
        shr     ax,1    		;/8 = byte offset from left of screen
        shr     ax,1
        shr     ax,1
        add     di,ax   		;point to the upper left corner of draw area
        and     bx,7    		;isolate intrapixel address
        shl     bx,1    		;*2 for word look-up
        add     bx,RotationTable[bp] ;point to the image structure for
        mov     bx,[bx]              ; the intrabyte rotation
        mov     dx,[bx].WidthInBytes ;image width
        mov     si,[bx].BitPattern   ;pointer to image pattern bytes
        mov     bx,[bx].Height       ;image height
DrawImageLoop:
        push    di      		;remember line start offset
        mov     cx,dx   		;# of bytes across
DrawImageLineLoop:
        lodsb           		;get the next image byte
        xchg    es:[di],al 	;draw the next image byte
        inc     di      		;point to the following screen byte
        loop    DrawImageLineLoop
        pop     di      		;retrieve line start offset
        add     di,SCREEN_WIDTH 	;point to the next line
        dec     bx      		;count off scan lines
        jnz     DrawImageLoop

        pop     di      		;restore caller's register variables
        pop     si
        pop     bp      		;restore caller's stack frame
        ret
_DrawImage      endp

; Draws a 0-terminated text string at the specified location in the
; specified bitmap in white, using the 8x8 BIOS font. Must be at an X
; coordinate that's a multiple of 8.
;
; C near-callable as: void TextUp(char *Text, int LeftX, int TopY,
;       unsigned int ScrnOffset, unsigned int ScrnSegment);

TextUpParms     struc
        dw      2 dup (?) 	;pushed BP and return address
Text    dw      ?       		;pointer to text to draw
TULeftX dw      ?       		;X coordinate of left side of rectangle
                        		; (must be a multiple of 8)
TUTopY  dw      ?       		;Y coordinate of top side of rectangle
TUScrnOffset dw ?       		;offset of base of bitmap in which to draw
TUScrnSegment dw ?      		;segment of base of bitmap in which to draw
TextUpParms     ends

        public  _TextUp
_TextUp proc    near
        push    bp      		;preserve caller's stack frame
        mov     bp,sp   		;point to local stack frame
        push    si      		;preserve caller's register variables
        push    di

        cld
        mov     dx,GC_INDEX
        mov     ax,G_MODE + (0000h)
        out     dx,ax   		;set to write mode 0
        les     di,dword ptr TUScrnOffset[bp] ;point to bitmap start
        mov     ax,SCREEN_WIDTH
        mul     TUTopY[bp]      	;point to the start of the top scan
        add     di,ax           	; line the text starts on
        mov     ax,TULeftX[bp]
        mov     bx,ax
        shr     ax,1    		;/8 = byte offset from left of screen
        shr     ax,1
        shr     ax,1
        add     di,ax   		;point to the upper left corner of first char
        mov     si,Text[bp] 	;point to text to draw
TextUpLoop:
        lodsb           		;get the next character to draw
        and     al,al
        jz      TextUpDone 	;done if null byte
        push    si      		;preserve text string pointer
        push    di      		;preserve character's screen offset
        push    ds      		;preserve default data segment
        call    CharUp  		;draw this character
        pop     ds      		;restore default data segment
        pop     di      		;retrieve character's screen offset
        pop     si      		;retrieve text string pointer
        inc     di      		;point to next character's start location
        jmp     TextUpLoop

TextUpDone:
        pop     di      		;restore caller's register variables
        pop     si
        pop     bp      		;restore caller's stack frame
        ret

CharUp:                 		;draws the character in AL at ES:DI
        lds     si,[BIOS8x8Ptr] 	;point to the 8x8 font start
        mov     bl,al
        sub     bh,bh
        shl     bx,1
        shl     bx,1
        shl     bx,1    		;*8 to look up character offset in font
        add     si,bx   		;point DS:SI to character data in font
        mov     cx,8    		;characters are 8 high
CharUpLoop:
        movsb           		;copy the next character pattern byte
        add     di,SCREEN_WIDTH-1 ;point to the next dest byte
        loop    CharUpLoop
        ret
_TextUp endp

; Sets the pointer to the BIOS 8x8 font.
;
; C near-callable as: extern void SetBIOS8x8Font(void);

        public  _SetBIOS8x8Font
_SetBIOS8x8Font proc    near
        push    bp      		;preserve caller's stack frame
        push    si      		;preserve caller's register variables
        push    di      		; and data segment (don't assume BIOS
        push    ds      		; preserves anything)
        mov     ah,11h  		;BIOS character generator function
        mov     al,30h  		;BIOS information subfunction
        mov     bh,3    		;request 8x8 font pointer
        int     10h     		;invoke BIOS video services
        mov     word ptr [BIOS8x8Ptr],bp ;store the pointer
        mov     word ptr [BIOS8x8Ptr+2],es
        pop     ds
        pop     di      		;restore caller's register variables
        pop     si
        pop     bp      		;restore caller's stack frame
        ret
_SetBIOS8x8Font endp
        end

