format ELF64 ;linux 64-bit executable

define STDOUT            1
define SYSCALL_MMAP      9
define MAP_ANON       0x20
define PROT_READ         1
define PROT_WRITE        2
define SYSCALL_WRITE     1
define SYSCALL_EXIT      60

define BLOCK    0xe28896e2 ; intel is little indian (R->L, 2 hex digits / byte)
define SPACE    0xe28280e2 ; add an extra e2 on the end (ie beginning)
define PIPE     0xe28294e2 ; because each next char begins with e2
define DASH     0xe28094e2
define BOTTOM   0xe2b494e2 ; get the pun (it's a domain thoery joke)?

define tower_pad 4  ; padding between towers for pretty printing
define char_bytes 3 ; bytes per char in pretty printing

define state           r15  ; 64-bit
define state_tmp       r9   ; 64-bit
define m               r14
define max_moves       r13
define disk            r12d
define bits            r11
define tower_assign   r10
define buf_start       rbp
define position        r8d
define tower_width     ebx ; 32-bit for imul
define line_width      eax ; 32-bit for imul
define N               ecx  ; TODO
define buf_len         edx
define x               eax  ; TODO
define i               eax  ; TODO
define buf             rsp ; TODO

;;;

macro push_registers { ; push all non-preserved registers for syscall
	push rax
	push rcx
	push rdx
	push rsi
	push rdi
	push r8
	push r9
	push r10
	push r11
}

macro pop_registers {
	pop r11
	pop r10
	pop r9
	pop r8
	pop rdi
	pop rsi
	pop rdx
	pop rcx
	pop rax
}

;;;

public _start
_start:
    ; Initializations
	xor state, state ; every disk starts at tower 0
	xor m, m ; start at move 0
	; iniialize max_moves, which is 2^n (shift 1 n left)
	mov max_moves, 1
	mov ecx, [n]
	shl max_moves, cl
	
    ; Calculate pretty printing sizes to allocate buffer
	lea tower_width, [N*2 + 3 + tower_pad]
	; get line_width
	mov line_width, char_bytes*6 ; 3 byte chars * ( 3 Ts * 2/symmetry * N
			             ; 	              + 2 padding instances * towerpad
			             ;                + 3 towers * 3 padding/tower)
			             ; + 1 for \n
	imul line_width, N
	mov x, tower_pad
	imul x, 6
	lea line_width, [line_width + x + 28] ; x is 6*tower_pad
	; get total bytes to allocate = (N+2) * linewidth
	mov buf_len, 2   ; first and last line are special
	add buf_len, N
	imul buf_len, line_width
    ; Allocate buf_start with buf_len bytes
	push_registers
      ; call mmap() 
	mov eax, SYSCALL_MMAP  ; syscall needs syscall number in eax
	xor edi, edi           ; at what memory location should it allocate mem
	mov edx, PROT_READ or PROT_WRITE  ; read and write from this memory
	mov rsi, buf_len       ; number of bytes to allocate
	mov r8, -1             ; file descriptor
	xor r9, r9             ; file offset
	mov r10, MAP_ANON      ; anonymous, not tied to another mmap
	syscall
	mov buf_start, rax     ; allocated buffer ;~TODO: check it's not an err
	pop_registers
	
; 1st & last lines
macro char_loop nchars, char {
	lea i, nchars
@@: ; copy each character into buffer
	mov dword [buf], char ; copies 4 bytes of char to position buf
			       ; note: hardcoded dword works for char_bytes=3|4
	add buf, char_bytes    ; advances buf ptr by char_bytes
	dec i   ; sets flag for jns
	jns @b  ; if not neg, jump to previous anon label
}
	
macro 1char char {
	mov dword [buf], char
	add buf, char_bytes
	}

macro tower outer, center {
	char_loop [N+1], outer
	1char center
	char_loop [N+1], outer
}

macro tower_line tower_constructor {
	tower_constructor
	char_loop [tower_pad], SPACE
	tower_constructor
	char_loop [tower_pad], SPACE
	tower_constructor
	; add newline char
	mov byte [buf], NEWLINE
}

    ; 1st line
	; initialize location of buf ptr
	mov buf, buf_start     ; starts at the very beginning

	; write 1st line	
macro tower_top { tower SPACE, PIPE }
	tower_line tower_top   ; note: minor inefficiency (2 inst) at runtime
                               ; does 3 loops that are for SPACES (init each)

     ; Last line
	; initialize buf ptr to beginning of last line: buf = N*line_width
	lea buf, [N+1]
	imul esp, line_width    ;*TODO: actual reg for buf 
	add buf, buf_start      ; move buf ptr to absolute location

	;write last line
macro tower_bottom { tower DASH, BOTTOM }
	tower_line tower_bottom

move_loop: ;TODO: figure out branching
  ; Render state as buffer that's ready to print
	; TODO: copy first line to each line from 1 to N

    ; Initialize render loop
	lea disk, [N - 1]     ; start at largest disk (because it's on bottom)
	mov state_tmp, state  ; copy of state that's clobbered in loop
	; State has 2-bit disk tower assignments, with disk 0 at the MSB
	; Shift away all the non-data LSB zeros, of which there are 64-2*N
	mov x, 2
	imul x, N
	mov ecx, 64
	sub ecx, x
	shr state_tmp, cl

    ; Render loop
	; Iterate through disks in state from largest; put each in buffer spot
	mov r8, state_tmp ; r8 is 64-bit version of position (which tower)
	mov bits, 11b  ; position of disk is in last two bits
	and r8, bits  ; extract position
	
      ; Calculate the right spot in buffer to put the disk
	; get horizontal offset, in line = (tower assigned*tower_width)+(N-disk)
	imul position, tower_width
	add position, N    ; smallest disk starts furthest in
	sub position, disk ; position is offset within line
	; get vertical index (which line the disk goes on) ;TODO: put disk at proper height
	lea line_num, [disk+1]
	; get vertical addr in buffer: buf = (line_num * line_width) + buf_start
				       ; ^ flatten matrix
	imul line_num, line_width
	mov buf, buf_start  ; will write at buf; so save buf_start ptr
	add buf, line_num
	; get writing addr (combine "offsets") 
	;     = char_bytes*(horizontal offset) + vertical addr [=buf_start+vertical_offset]
	imul position, char_bytes
	add position, buf
	
      ; Loop: write the blocks into this spot 
	; initialize; will add 2*disk+3 blocks to buffer for each disk
	lea i, [2*disk+3-1]
blocks: ; copy BLOCK for each character
	mov dword [buf], BLOCK ; copies 4 bytes of BLOCK to position buf
			       ; note: hardcoded dword works for char_bytes=3|4
	add buf, char_bytes    ; advances buf ptr by char_bytes
	dec i
	jns blocks

  ; Print buffer
	push_registers
      ; call write() 
	mov eax, SYSCALL_WRITE ; syscall needs syscall number in eax
	mov edi, STDOUT        ; file descriptor is stdout
	mov edx, buf_len       ; length of buffer to print
	mov rsi, buf_start     ; ptr of buffer to printer
	syscall	
	pop_registers

  ; Make the move in the state
	; get index of disk to move	
	tzcnt disk, m ; disk to move is # of trailing 0s in move number
	
      ; calculate tower assignment that disk will move to
	blsi x, m   ; x = m&-m
	add x, m
        ; %3, from godbolt compiler, using a magic number
          ; TODO: x is eax as of now
	mov tower_assign, x
        mov edx, -1431655765
        mul edx
        mov eax, edx
        shr eax
        lea eax, [rax+rax*2]
        sub tower_assign, eax
	
	mov bits, 11b ; TODO: check usage of bits  ; need to change 2 bits
	; shift left to position for inserting data; backwards so 62-2*disk
	mov x, 2
	imul x, disk
	mov ecx, 62
	sub ecx, x ; ecx is 62-2*disk now
	shl bits, cl ; put 2-bit mask in correct spot
	andn state, bits ; zero out covered bits
	mov bits, tower_assign ; set desired bits to new assignment
	shl bits, cl  ; shift desired bits into correct spot (same spot)
	or state, bits  ; merge new bits with previous state



n dd 5 ; number of disks to transfer, which can go up to 32 (fits in 1 byte) but we allocate 4 for easy loading
;msg db 'Hello world!',0xA   ; assemble these bytes into binary with ptr to beg: msg
;msg_size = $-msg    ; $ gets the current index of bytes, subtract from that the ptr to beginning for length
