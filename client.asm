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
    CANCEL = 0x15
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
    msg_connected db 'Connected', 0xa, 0
    msg_inner_options db    'Вы авторизованы. Нажмите:',0xa,\
                            '0 для проверки состояния счета', 0xa,\
                            '1 для совершения перевода', 0xa,\
                            '2 для вноса средств', 0xa,\
                            '3 для снятия средств', 0xa,\
                            '4 для получения кредита', 0xa,\
                            '5 для оплаты кредита', 0xa,\
                            '6 для выхода из системы', 0xa,\
                            'q для завершения работы', 0xa, 0
    msg_outer_options db    'Вы не авторизованы. Нажмите:',0xa,\
                            '1 для авторизации', 0xa,\
                            '2 для регистрации', 0xa,\
                            'q для завершения работы', 0xa, 0
    msg_fault db 'Введите команду из списка доступных', 0xa, 0
    msg_user_not_found db 'Пользователь не найден', 0xa, 0
    msg_target_not_found db 'Получатель не найден', 0xa, 0
    msg_not_enough_money db 'Недостаточно средств', 0xa, 0
    msg_unclosed_credit db 'У Вас уже есть кредит. Для получения нового, погасите старый', 0xa, 0
    msg_credit_denied db 'В кредите отказано', 0xa, 0
    msg_overflow db 'Платеж превышает сумму кредита', 0xa, 0
    msg_incorrect_password db 'Пароль неверный', 0xa, 0
    msg_hello db 'Здравствуйте, ', 0
    msg_create_password db 'Придумайте пароль:', 0xa, 0
    msg_your_id db 'Ваш номер счета: ', 0
    msg_your_score db 'Ваш счет: ', 0
    msg_your_credit db 'Ваш кредит: ', 0
    msg_connect_error db 'Error connect', 0xa, 0
    msg_denied db 'Недопустимая команда', 0xa, 0
    msg_not_found db 'Команда не найдена', 0xa, 0
    msg_enter_name db 'Введите Ваше имя (до 20 символов):', 0xa, 0
    msg_enter_password db 'Введите пароль:', 0xa, 0
    msg_enter_id db 'Введите номер Вашего счета:', 0xa, 0
    msg_enter_target_id db 'Введите номер счета получателя:', 0xa, 0
    msg_enter_amount db 'Введите сумму:', 0xa, 0
    msg_sign_out db 'Вы вышли из системы', 0xa, 0
    msg_empty_enter db 'Отмена операции', 0xa, 0
  
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
            cmp rax, 1
            je .empty_enter
            call write_to_server

            call read_from_server

            mov rsi, msg_enter_password
            call print_str

            mov rsi, input_buffer
            call input_keyboard
            cmp rax, 1
            je .empty_enter
            call write_to_server
            
            call read_from_server

            cmp [buffer], SUCCESS
            je @f

            mov rsi, msg_user_not_found
            call print_str
            jmp .main

            @@:
            call write_to_server
            call read_from_server

            cmp [buffer], SUCCESS
            je @f

            mov rsi, msg_incorrect_password
            call print_str
            jmp .main

            @@:
            mov [sign_flag], 1

            call write_to_server
            call read_from_server

            mov rsi, msg_hello
            call print_str
            mov rsi, buffer
            call print_str
            call new_line

            jmp .main

        .sign_up:
            mov rsi, msg_enter_name
            call print_str

            mov rsi, input_buffer
            call input_keyboard
            cmp rax, 1
            je .empty_enter
            call write_to_server

            call read_from_server

            mov rsi, msg_create_password
            call print_str

            mov rsi, input_buffer
            call input_keyboard
            cmp rax, 1
            je .empty_enter
            call write_to_server
            
            call read_from_server

            mov rsi, msg_your_id
            call print_str
            mov rsi, buffer
            call print_str
            call new_line

            mov [sign_flag], 1

            jmp .main

        .check:
            call write_to_server
            
            call read_from_server
            
            mov rsi, msg_your_score
            call print_str
            mov rsi, buffer
            call print_str
            call new_line

            call write_to_server

            call read_from_server

            mov rsi, msg_your_credit
            call print_str
            mov rsi, buffer
            call print_str
            call new_line

            jmp .main

        .transfer:
            mov rsi, msg_enter_target_id
            call print_str

            mov rsi, input_buffer
            call input_keyboard
            cmp rax, 1
            je .empty_enter
            call write_to_server

            call read_from_server

            mov rsi, msg_enter_amount
            call print_str

            mov rsi, input_buffer
            call input_keyboard
            cmp rax, 1
            je .empty_enter
            call write_to_server

            call read_from_server

            cmp [buffer], SUCCESS
            je @f

            mov rsi, msg_target_not_found
            call print_str
            jmp .main

            @@:
            call write_to_server
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
            cmp rax, 1
            je .empty_enter
            call write_to_server

            call read_from_server

            jmp .main

        .withdraw:
            mov rsi, msg_enter_amount
            call print_str

            mov rsi, input_buffer
            call input_keyboard
            cmp rax, 1
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
            cmp rax, 1
            je .empty_enter
            call write_to_server

            call read_from_server

            cmp [buffer], SUCCESS
            je @f

            mov rsi, msg_unclosed_credit
            call print_str
            jmp .main
            
            @@:
            call write_to_server

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
            cmp rax, 1
            je .empty_enter
            call write_to_server

            call read_from_server

            cmp [buffer], SUCCESS
            je @f

            mov rsi, msg_not_enough_money
            call print_str
            jmp .main
            
            @@:
            call write_to_server

            call read_from_server

            cmp [buffer], SUCCESS
            je @f

            mov rsi, msg_overflow
            call print_str
            
            @@:
            jmp .main

        .sign_out:
            mov [sign_flag], 0
            mov rsi, msg_sign_out
            call print_str
            jmp .main

.empty_enter:
    mov rsi, msg_empty_enter
    call print_str
    mov rsi, input_buffer
    mov word[input_buffer], CANCEL
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
    mov byte[buffer+rax], 0
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
    cmp [sign_flag], 1
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

    mov al, [input_buffer]
    add al, 6
    mov [input_buffer], al
    cmp word[input_buffer], SIGN_IN
    jl .invalid
    cmp word[input_buffer], SIGN_UP
    jg .invalid
    
    jmp .valid

    .inner_options:
    cmp word[input_buffer], CHECK
    jl .invalid
    cmp word[input_buffer], SIGN_OUT
    jg .invalid

    .valid:
        ret

    .invalid:
        mov word[input_buffer], INVALID
        ret
