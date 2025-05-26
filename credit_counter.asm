format elf64
public _start
include 'func.asm'

section '.bss' writable

users db './users', 0   ; расположение каталога пользователей
KOEF = 5                ; ставка - 20%
QUIT = 0x71             ; 'q' + 0

buffer rb 20

msg_user_not_found db 'Пользователь не найден', 0xa, 0

; структура пользователя
struc User
{
    .id rb 20
    .name rb 20
    .password rb 20
    .score dq ?
    .credit dq ?
    .descriptor dq ?
}

user User       ; пользователь

section '.text' executable
_start:

; переходим в директорию 'users'
mov rax, 80     ; sys_chdir
mov rdi, users  ; path
syscall

.loop:
    ; Считываем ID пользователя с клавиатуры
    mov rsi, user.id
    call input_keyboard
    cmp rax, 1              ; проверка на пустой ввод
    je .loop
    cmp word[user.id], QUIT    ; выход на q
    je .exit

    ; Пытаемся прочитать файл
    mov rsi, user
    call read_file
    cmp rax, 0              ; проверка на успешное прочтение
    jl .loop

    ; Начисляем процент
    mov rax, [user.credit]
    mov rbx, KOEF
    div rbx
    add [user.credit], rax

    ; Записываем изменения в файл
    mov rsi, user
    call write_file

    jmp .loop

.exit:
call exit

; ФУНКЦИИ

; чтение из файла пользователя
; ввод: rsi - место для данных
; вывод: rax - 0 в случае успеха, иначе -1
read_file:
    mov r9, rsi

    mov rax, 2
    mov rdi, r9
    mov rsi, 0
    syscall
    cmp rax, 0
    jl .fault_read

    mov rdi, rax
    mov rsi, r9
    add rsi, 20
    call readline

    mov rsi, r9
    add rsi, 40
    call readline

    mov rsi, buffer
    call readline
    xor rax, rax
    call str_number
    mov qword[r9+60], rax

    mov rsi, buffer
    call readline
    xor rax, rax
    call str_number
    mov qword[r9+68], rax

    mov rax, 3
    syscall

    xor rax, rax
    .fault_read:
    ret

; запись в файл пользователя
; ввод: rsi - источник данных
; вывод: нет
write_file:
    mov r9, rsi

    mov rax, 2
    mov rdi, r9
    mov rsi, 1001o
    syscall
    mov rdi, rax

    mov rsi, r9
    add rsi, 20
    call writeline
    
    mov rsi, r9
    add rsi, 40
    call writeline

    mov rax, qword[r9+60]
    mov rsi, buffer
    call number_str
    call writeline

    mov rax, qword[r9+68]
    call number_str
    call writeline

    mov rax, 3
    syscall
    ret
