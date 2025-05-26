;Function exit
exit:
    mov rax, 0x3c
    mov rdi, 0
    syscall

;Function printing of string
;input rsi - place of memory of begin string
print_str:
    push rdi
    push rsi

    mov rax, rsi
    call len_str
    mov rdx, rax
    mov rax, 1
    mov rdi, 1
    syscall

    pop rsi
    pop rdi
    ret

;The function makes new line
new_line:
    push rdi
    push rsi
    push rcx

    mov rax, 0xA
    push rax
    mov rdi, 1
    mov rsi, rsp
    mov rdx, 1
    mov rax, 1
    syscall
    pop rax

    pop rcx
    pop rsi
    pop rdi
    ret

;The function finds the length of a string
;input rax - place of memory of begin string
;output rax - length of the string
len_str:
    mov rdx, rax
    .iter:
        cmp byte [rax], 0
        je .next
        inc rax
        jmp .iter
    .next:
        sub rax, rdx
        ret

;Function converting the string to the natural number
;input rsi - place of memory of begin string
;output rax - the natural number from the string
str_number:
    push rsi
    push rdi

    xor rax,rax
    xor rcx,rcx
    .loop:
        xor rbx, rbx
        mov bl, byte [rsi+rcx]
        cmp bl, 48
        jl @f
        cmp bl, 57
        jg @f

        sub bl, 48
        add rax, rbx
        mov rbx, 10
        mul rbx
        inc rcx
        jmp .loop

    @@:
    cmp byte[rsi+rcx], 0
    je .success
    xor rax, rax

    .success:
    mov rbx, 10
    div rbx

    pop rdi
    pop rsi
    ret

;The function converts the number to string
;input rax - number
;rsi -address of begin of string
number_str:
    push rdi
    push rsi

    xor rcx, rcx
    mov rbx, 10
    .loop_1:
        xor rdx, rdx
        div rbx
        add rdx, 48
        push rdx
        inc rcx
        cmp rax, 0
        jne .loop_1
    xor rdx, rdx
    .loop_2:
        pop rax
        mov byte [rsi+rdx], al
        inc rdx
        dec rcx
        cmp rcx, 0
        jne .loop_2
    mov byte [rsi+rdx], 0 

    pop rsi
    pop rdi
    ret

;The function realizates user input from the keyboard
;input: rsi - place of memory saved input string 
input_keyboard:
    mov rax, 0
    mov rdi, 0
    mov rdx, 20
    syscall
    
    dec rax
    mov byte[rsi+rax], 0
    inc rax
    ret

;Function reading of string from file
;input rsi - place of memory to place string,
; rdi - descriptor
;output rsi - string, rax - length
readline:
    push rdi
    push rsi

    xor rcx, rcx
    .loop:
        push rcx
        mov rax, 0
        mov rdx, 1
        syscall
        pop rcx
        cmp rax, 0
        je .end
        cmp byte[rsi], 0xA
        je .end
        cmp byte[rsi], 0
        je .end
        inc rsi
        inc rcx
        jmp .loop
    .end:
    mov byte[rsi], 0
    sub rsi, rcx
    mov rax, rcx

    pop rsi
    pop rdi
    ret

;Function writing string to file
;input rsi - place of string in memory,
; rdi - descriptor
writeline:
    push rdi
    push rsi

    mov rax, rsi
    call len_str
    mov rdx, rax
    mov rax, 1
    syscall

    mov rax, 0xA
    push rax
    mov rsi, rsp
    mov rdx, 1
    mov rax, 1
    syscall
    pop rax

    pop rsi
    pop rdi
    ret
