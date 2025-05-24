format elf64
public _start
include 'func.asm'

section '.bss' writable

; константы
.const:
    QUIT = 0x71             ; 'q' + 0
    SIGN_IN = 0x37          ; '7' + 0
    SIGN_UP = 0x38          ; '8' + 0
    CHECK = 0x30            ; '0' + 0
    TRANSFER = 0x31         ; '1' + 0
    DEPOSIT = 0x32          ; '2' + 0
    WITHDRAW = 0x33         ; '3' + 0
    TAKE_CREDIT = 0x34      ; '4' + 0
    PAY_CREDIT = 0x35       ; '5' + 0
    SIGN_OUT = 0x36         ; '6' + 0
    INVALID = 0x39          ; '9' + 0
    BREAK = 0x15
    SUCCESS = '1'

; переменные
.var:
    server_socket dq ? ; дескриптор сокета сервера
    client_socket dq ? ; дескриптор сокета клиента
    sign_flag db 0
    input_buffer rb 100
    buffer rb 100

; сообщения
.msg:
    msg_connect_error db 'Error connect', 0xa, 0
    msg_denied db 'Недопустимая команда', 0xa, 0
    msg_not_found db 'Команда не найдена', 0xa, 0
    msg_enter_login db 'Введите логин:', 0xa, 0
    msg_enter_password db 'Введите пароль:', 0xa, 0
    msg_enter_id db 'Введите номер счета:', 0xa, 0
    msg_enter_number db 'Введите сумму:', 0xa, 0
    msg_sign_out db 'Вы вышли из системы', 0xa, 0
    msg_connected db 'Connected', 0xa, 0
  
struc sockaddr_server 
{
    .sin_family dw 2         ; AF_INET
    .sin_port dw 0x3d9       ; port 55555
    .sin_addr dd 0           ; localhost
    .sin_zero_1 dd 0
    .sin_zero_2 dd 0
}

addrstr_server sockaddr_server 
addrlen_server = $ - addrstr_server

section '.text' executable
_start:

.connection:
    ; создаем сокет клиента
    mov rdi, 2 ; AF_INET - IP v4 
    mov rsi, 1 ; SOCK_STREAM
    mov rdx, 0 ; default
    mov rax, 41
    syscall

    ; сохраняем дескриптор сокета клиента
    mov [client_socket], rax

    ; подключаемся к серверу
    mov rax, 42                 ;sys_connect
    mov rdi, [client_socket]    ;дескриптор
    mov rsi, addrstr_server 
    mov rdx, addrlen_server
    syscall
    cmp rax, 0
    jl  .connect_error

    mov rsi, msg_connected
    call print_str

.main:
    ; выводим варианты доступных для пользователя действий
    call print_options

    ; читаем команду с клавиатуры
    mov rsi, input_buffer
    call input_keyboard
    cmp rax, 0
    je .empty_enter

    ; выход на q
    cmp word[input_buffer], QUIT
    je .exit

    ; обработка введенной команды
    call command_handler

    ; отправляем сообщение на сервер
    mov rsi, input_buffer
    call write_to_server

    ; получаем ответ от сервера
    call read_from_server
    
    cmp [buffer], SUCCESS
    je .success           ; если код 1, значит переходим к выполнению
    mov rsi, msg_fault
    call print_str
    jmp .main

    ; разветвление по коду операции
    .success:
        cmp word[input_buffer], SIGN_IN
        je .sign_in

        cmp word[input_buffer], SIGN_UP
        je .sign_up

        cmp word[input_buffer], CHECK
        je .check

        cmp word[input_buffer], TRANSFER
        je .transfer

        cmp word[input_buffer], DEPOSIT
        je .deposit
        
        cmp word[input_buffer], WITHDRAW
        je .withdraw
        
        cmp word[input_buffer], TAKE_CREDIT
        je .take_credit
        
        cmp word[input_buffer], PAY_CREDIT
        je .pay_credit
            
        cmp word[input_buffer], SIGN_OUT
        je .sign_out

        .sign_in:
            mov rsi, msg_enter_id
            call print_str

            mov rsi, input_buffer
            call input_keyboard
            cmp rax, 0
            je .empty_enter
            call write_to_server

            mov rsi, msg_enter_password
            call print_str

            mov rsi, input_buffer
            call input_keyboard
            cmp rax, 0
            je .empty_enter
            call write_to_server
            
            call read_from_server

            cmp [buffer], SUCCESS
            je @f

            mov rsi, msg_user_not_found
            call print_str
            jmp .main

            @@:
            call read_from_server

            cmp [buffer], SUCCESS
            je @f

            mov rsi, msg_incorrect_password
            call print_str
            jmp .main

            @@:
            mov [sign_flag], 1

            mov rsi, msg_hello
            call print_str
            call read_from_server
            mov rsi, buffer
            call print_str
            call new_line

            jmp .main

        .sign_up:
            mov rsi, msg_enter_name
            call print_str

            mov rsi, input_buffer
            call input_keyboard
            cmp rax, 0
            je .empty_enter
            call write_to_server

            mov rsi, msg_enter_password
            call print_str

            mov rsi, input_buffer
            call input_keyboard
            cmp rax, 0
            je .empty_enter
            call write_to_server
            
            mov rsi, msg_your_id
            call print_str
            call read_from_server
            mov rsi, buffer
            call print_str
            call new_line

            mov [sign_flag], 1

            jmp .main

        .check:
            mov rsi, msg_your_score
            call print_str
            call read_from_server
            mov rsi, buffer
            call print_str
            call new_line

            mov rsi, msg_your_credit
            call print_str
            call read_from_server
            mov rsi, buffer
            call print_str
            call new_line

            jmp .main

        .transfer:
            mov rsi, msg_enter_target_id
            call print_str

            mov rsi, input_buffer
            call input_keyboard
            cmp rax, 0
            je .empty_enter
            call write_to_server

            mov rsi, msg_enter_amount
            call print_str

            mov rsi, input_buffer
            call input_keyboard
            cmp rax, 0
            je .empty_enter
            call write_to_server

            call read_from_server

            cmp [buffer], SUCCESS
            je @f

            mov rsi, msg_target_not_found
            call print_str

            @@:
            call read_from_server

            cmp [buffer], SUCCESS
            je @f

            mov rsi, msg_not_enough_money
            call print_str

            @@:
            jmp .main
        
        .deposit:
            mov rsi, msg_enter_amount
            call print_str

            mov rsi, input_buffer
            call input_keyboard
            cmp rax, 0
            je .empty_enter
            call write_to_server

            jmp .main

        .withdraw:
            mov rsi, msg_enter_amount
            call print_str

            mov rsi, input_buffer
            call input_keyboard
            cmp rax, 0
            je .empty_enter
            call write_to_server

            call read_from_server

            cmp [buffer], SUCCESS
            je @f

            mov rsi, msg_not_enough_money
            call print_str

            @@:
            jmp .main

        .take_credit:
            mov rsi, msg_enter_amount
            call print_str

            mov rsi, input_buffer
            call input_keyboard
            cmp rax, 0
            je .empty_enter
            call write_to_server

            call read_from_server

            cmp [buffer], SUCCESS
            je @f

            mov rsi, msg_unclosed_credit
            call print_str
            
            @@:
            call read_from_server

            cmp [buffer], SUCCESS
            je @f

            mov rsi, msg_credit_denied
            call print_str
            
            @@:
            jmp .main

        .pay_credit:
            mov rsi, msg_enter_amount
            call print_str

            mov rsi, input_buffer
            call input_keyboard
            cmp rax, 0
            je .empty_enter
            call write_to_server

            call read_from_server

            cmp [buffer], SUCCESS
            je @f

            mov rsi, msg_not_enough_money
            call print_str
            
            @@:
            call read_from_server

            cmp [buffer], SUCCESS
            je @f

            mov rsi, msg_overflow
            call print_str
            
            @@:
            jmp .main

        .sign_out:
            mov sign_flag, 0
            mov rsi, msg_sign_out
            call print_str
            jmp .main_loop

.empty_enter:
    mov rsi, msg_empty_enter
    call print_str
    mov rsi, BREAK
    call write_to_server
    jmp .main

.exit:
    ; Закрываем чтение, запись из клиентского сокета
    mov rax, 48
    mov rdi, [client_socket]
    mov rsi, 2
    syscall
          
    ; Закрываем клиентский сокет
    mov rdi, [client_socket]
    mov rax, 3
    syscall
    
    call exit
 
.connect_error:
    mov rsi, msg_connect_error
    call print_str
    jmp .exit

; функции
read_from_server:
    mov rax, 0               ;номер системного вызова чтения
    mov rdi, [client_socket] ;загружаем файловый дескриптор
    mov rsi, buffer          ;указываем, куда помещать прочитанные данные
    mov rdx, 20              ;устанавливаем количество считываемых данных
    syscall
    ret

; в rsi указываем, откуда брать данные
write_to_server:
    mov rdi, [client_socket] ;загружаем файловый дескриптор
    mov rax, rsi
    call len_str             ;получаем длину сообщения
    mov rdx, rax
    mov rax, 1               ;номер системного вызова записи
    syscall
    ret

; выводит список доступных пользователю команд в зависимости от sign_flag
print_options:
    cmp sign_flag, 1
    je .signed

    mov rsi, msg_outer_options
    call print_str
    ret

    .signed:
    mov rsi, msg_inner_options
    call print_str
    ret

; проверка команды на допустимость и преобразование в код команды
; в input_buffer - результат, код команды, если допустимо, иначе INVALID
command_handler:
    cmp [sign_flag], 1
    je .inner_options

    cmp word[input_buffer], SIGN_IN
    jl .invalid
    cmp word[input_buffer], SIGN_UP
    jg .invalid
    mov al, [input_buffer]
    mov rbx, 6
    add rax, rbx
    jmp .valid

    .inner_options:
    cmp word[input_buffer], TRANSFER
    jl .invalid
    cmp word[input_buffer], SIGN_OUT
    jg .invalid

    .valid:
        ret

    .invalid:
        mov word[input_buffer], INVALID
        ret
