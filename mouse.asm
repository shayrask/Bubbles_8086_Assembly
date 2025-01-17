;==================================================
;This procedure handles the mouse interrupt
;==================================================
check_mouse proc uses ax bx cx dx
    ; Check for mouse click and get mouse position
    mov ax, 3
    int 33h
    test bx, 1          ; Check left button
    jz no_click         ; If not clicked, skip to no_click

    shr cx, 1           ; Divide CX by 2 to convert from 640x200 to 320x200
    mov mouse_x, cx
    mov mouse_y, dx

    wait_release:
    mov ax, 3
    int 33h
    test bx, 1          ; Check if the button is still pressed
    jnz wait_release    ; If pressed, wait for release

    ; Check bounds (assuming 320x200 resolution)
    cmp mouse_x, 246    
    jae no_click
    cmp mouse_y, 173
    jae no_click

    ;stop counting time
    call IVT_return
    ;hide cursor
    mov ax, 2
    int 33h
    ;do function
    sub mouse_x, 6d     ;Designed for the center of the bubble to come to a point
    sub mouse_y, 6d     ;Designed for the center of the bubble to come to a point
    call shoot
    ;scan
    mov scan_counter, 0
    call init_balls_2_explo     ;initialization of the array
    mov ax, player_x
    mov dx, player_y
    ;Calculate the offset: (Y * 320) + X
    call loc_incode
    ;AX = Y * 320 + X
    call scan
    ;call explosion function 
    cmp scan_counter, 3
    jb no_explosion
    call explosion
    mov last_explo_T_F, 1
    jmp update_player_color
    no_explosion:               ;In case no recursion was counted, a sequence of 3 or more bubbles
    call update_lifes
    mov last_explo_T_F, 0       ;Initialize this boolean variable for the double score

    update_player_color:
    call get_currBall_nxtBall
    ;Draw Player
    mov location_x, init_player_x
    mov location_y, init_player_y
    mov bl,current_ball
    call draw_ball
    ;Draw Next Ball
    mov location_x, 278d
    mov location_y, 100d
    mov bl,next_ball
    call draw_ball
    ;reset player_x and player_y location
    mov player_x, init_player_x
    mov player_y, init_player_y
    ;continue time check
    call IVT_change
    call end_game_chck
    ;show cursor
    mov ax, 1
    int 33h

    no_click:
    ret
check_mouse endp

;==================================================
;This procedure creates the shoot animation
;==================================================
shoot proc uses ax bx cx dx si di
    ; Assume:
    ; player_x and player_y contain the current ball position
    ; mouse_x and mouse_y contain the mouse target position

    ;Calculate differences
    mov ax, mouse_x
    sub ax, player_x  ; AX = dx
    ;player_y >= mouse_y for evert y.
    mov bx, player_y
    sub bx, mouse_y   ; BX = dy (note the reversal here)

    ; Get absolute value of dx
    mov cx, ax
    cmp cx, 0
    jge abs_done
    neg cx
    abs_done:

    ; Compare |dx| with dy to find the larger difference
    cmp cx, bx
    jge use_cx
    mov cx, bx    ; If dy is larger, use it for normalization
    use_cx:
    ; CX = max{|dx|,|dy|}
    
    ; Normalize dx and dy to produce fractional steps
    ; Calculate si = dx * 256 / max{|dx|, |dy|}
    ; Calculate di = dy * 256 / max{|dx|, |dy|}
    mov di, 256  ; formatting to 8.8 float foramt
    
    ; Calculate dx step
    imul di    ; dx * 256
    idiv cx    ; dx_step = (dx * 256) / max_diff
    mov si, ax ; Save the dx step

    ; Calculate dy step
    mov ax, bx
    imul di    ; dy * 256
    idiv cx    ; dy_step = (dy * 256) / max_diff
    mov di, ax ; Save the dy step

    ;foramting to 8.8 AX and DX
    mov cl, 8
    mov ax, player_x
    shl ax, cl
    mov dx, player_y
    shl dx, cl
    mov player_x, ax
    mov player_y, dx

    move_ball:                  ;Loop of the displacement of the bubble on the screen until it collides
    mov ax, player_x
    add ax, si
    mov dx, player_y
    sub dx, di
    ;AX = player_x + dx foramt 8.8
    ;DX = player_y + dy foramt 8.8
    
    ;check collision
    push ax
    push dx
    ;convert to normal
    mov cl, 8
    shr ax, cl
    shr dx, cl
    ;check collision
    call check_collision
    cmp colli_stat, 2
    jne no_wall_colli
    neg si  ; Reverse direction if collision with a wall detected
 
    no_wall_colli:
    cmp colli_stat, 1
    je end_anim
    call erase_current_ball
    cmp dx, 161d
    jb no_line_need             ;When the ball passes or cuts the line, it is necessary to redraw
    call draw_limit_line
    no_line_need:
    mov location_x, ax
    mov location_y, dx
    mov bl, current_ball
    call draw_ball
    pop dx
    pop ax
    ;update player location
    mov player_x, ax
    mov player_y, dx

    ; Optional: Delay for the next frame
    mov cx,07FFFh
    delay:
    loop delay
    
    ; Loop to continue the animation
    jmp move_ball
    
    end_anim:
    ;baby step check
    push ax
    push dx
    mov ax, si
    mov dx, di
    ;dx check
    cmp ah, 0
    jl baby_step_dx_n
    ;positive
    cmp ah, 2
    jb no_baby_step_dx
        dec ah
        mov colli_stat, 0
    jmp no_baby_step_dx
    ;negative
    baby_step_dx_n:
    cmp ah, -2
    jg no_baby_step_dx
        inc ah
        mov colli_stat, 0
    no_baby_step_dx:
    ;dy check
    cmp dh, 2
    jb no_baby_step_dy
    dec dh
    mov colli_stat, 0
    no_baby_step_dy:
    mov si, ax
    mov di, dx
    pop dx
    pop ax
    cmp colli_stat, 0
    je move_ball
    ; Animation ends
    pop dx
    pop ax
    mov ax, player_x
    mov dx, player_y
    ;convert to normal
    mov cl, 8
    shr ax, cl
    shr dx, cl
    mov player_x, ax
    mov player_y, dx
    ret
shoot endp

;==================================================
; Input: AX = X coordinate, DX = Y coordinate
; Output: colli_stat = 1 if there is collision with bubles and 2 if there is collision with wall 0 if not (bool func)
;==================================================
check_collision proc uses di es si cx
    ;Stage a collision check with the wall and update the variable accordingly
    mov colli_stat, 0
    cmp ax, 4      
    jbe out_of_range  
    cmp ax, 234   
    jae out_of_range 

    jmp end_wall_check

    out_of_range:
    mov colli_stat, 2
    jmp wall_end
 

    end_wall_check:
    ; Load the base segment for video memory
    push bx
    mov bx, 0A000h
    mov es, bx
    pop bx
    ; Calculate the offset: (Y * 320) + X
    push ax
    push dx
    call loc_incode
    mov space_point, ax
    pop dx
    pop ax
    

    ; save DX and AX 
    push ax
    push dx
    ;convert to 8.8 foramt
    mov cl, 8d
    mov si, player_x
    shr si, cl
    sub ax, si
    mov di, player_y
    shr di, cl
    sub di, dx
    mov dx, di
    ;result: 
    ;ax = number of pixels moved in X axis
    ;dx = number of pixels moved in Y axis
    mov di, space_point
    ;row check
    cmp dx, 0
    je cornerchck       ;In a situation where the bubble only moves along the X axis and you only need to check it's sides for collision
    add di, 2d
    mov cx, 8d
    xor si, si
    row_check:
        push di
        add di, si
        mov bl, es:[di]   ; BL = color at (AX, DX)
        pop di
        cmp bl, 48d
        jbe bubble_collision
        inc si
    loop row_check
    mov di, space_point
    cmp ax, 0
    jne cornerchck  
    ;In a situation where the bubble only moves along the Y axis and you only need to check it's sides for collision
    add di, 321d
    mov cx, 2d
    xor si, si
    two_corner1chck:
        push di
        add di, si
        mov bl, es:[di]   ; BL = color at (AX, DX)
        pop di
        cmp bl, 48d
        jbe bubble_collision
        add si, 9
    loop two_corner1chck
    add di, 319d
    mov cx, 2d
    xor si, si
    two_corner2chck:
        push di
        add di, si
        mov bl, es:[di]   ; BL = color at (AX, DX)
        pop di
        cmp bl, 48d
        jbe bubble_collision
        add si, 11
    loop two_corner2chck

    mov di, space_point
    ;corners check
    cornerchck:
    add di, 321d
    cmp ax, 0
    jl left_corner_check
    add di, 9
    left_corner_check:
        mov bl, es:[di]   ; BL = color at (AX, DX)
        cmp bl, 48d
        jbe bubble_collision
    
    mov di, space_point
    ; column check
    cmp ax, 0
    je end_colli_chck
    jl left_col_check
    add di, 11
    left_col_check:
    add di, 640d
    mov cx, 8d
    xor si,si
    col_check:
        push di
        add di, si
        mov bl, es:[di]   ; BL = color at (AX, DX)
        pop di
        cmp bl, 48d
        jbe bubble_collision
        add si, 320d
    loop col_check
    

    cmp colli_stat, 1
    jne end_colli_chck

    bubble_collision:
    mov colli_stat, 1

    end_colli_chck:
    pop dx
    pop ax
    wall_end:
    ret
check_collision endp

;==================================================
;This procedure earase the 12x12 pixels in location:
;player_x and player_y in 8.8 foramt
;==================================================
erase_current_ball proc uses cx di ax dx
    ; Load the base segment for video memory
    push player_y
    push player_x
    mov cl, 8
    mov ax, player_x
    mov dx, player_y
    shr ax ,cl
    shr dx ,cl
    mov player_x ,ax
    mov player_y ,dx
    xor di, di          ; Initialize di (result index)
    mov cx, 12       
    erase_col:
        push cx             ; Preserve cx (inner loop count)
        push player_x
        mov cx,12  
        erase_row:
            mov al, ball[di]       
            cmp al,99
            je erase_continiue
            ;When we got to a pixel that is not the background at the edges
            mov al, background_color  
            push cx
            mov ah,0Ch 
            mov cx,player_x
            mov dx,player_y
            int 10h
            pop cx
            erase_continiue:
            inc di                ; Move to next pixal in result matrix
            inc player_x
        loop erase_row
        pop player_x
        inc player_y
        pop cx                  ; Restore cx (inner loop count)
    loop erase_col
    pop player_x 
    pop player_y
    ret
erase_current_ball endp
