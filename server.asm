format elf64
public _start
include 'func.asm'

section '.bss' writable

f db "/dev/urandom", 0   ; расположение ГСЧ
users db './users', 0   ; расположение каталога пользователей

; константы
.const:
    SIGN_IN = 0x37          ; '7' + 0
    SIGN_UP = 0x38          ; '8' + 0
    CHECK = 0x30            ; '0' + 0
    TRANSFER = 0x31         ; '1' + 0
    DEPOSIT = 0x32          ; '2' + 0
    WITHDRAW = 0x33         ; '3' + 0
    TAKE_CREDIT = 0x34      ; '4' + 0
    PAY_CREDIT = 0x35       ; '5' + 0
    SIGN_OUT = 0x36         ; '6' + 0
    CANCEL = 0x15
    M = 1000000
    KOEF = 100
    LIM = 3

; переменные
.var:
    active_connections dq 0 ; количество подключений
    container rb 20         ; контейнер
    buffer rb 20            ; буфер
    rand dq ?               ; дескриптор ГСЧ
    server_socket dq ?      ; дескриптор сокета сервера
    client_socket dq ?      ; дескриптор сокета клиента
    client_adress rb 16     ; адрес клиента
    len_client rq 1         ; длина адреса
    client_port rb 10       ; порт клиента

; сообщения
.msg:
    msg_success db '1', 0
    msg_fault db '0', 0
    msg_listen_error db 'Error listen', 0xa, 0
    msg_bind_error db 'Error bind', 0xa, 0
    msg_fork_error db 'Error fork', 0xa, 0
    msg_accept_error db 'Error accept', 0xa, 0
    msg_socket_created db 'Socket created', 0xa, 0
    msg_socket_binded db 'Socket binded', 0xa, 0
    msg_listening db 'Listening...', 0xa, 0
    msg_connected db 'Connection on port ', 0
    msg_disconnected db 'Disconnection on port ', 0

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

user User       ; авторизованный пользователь
target User     ; получатель перевода

; структура адреса сокета
struc sockaddr
{
  .sin_family dw 2   ; AF_INET
  .sin_port dw 0x3d9 ; port 55555
  .sin_addr dd 0     ; localhost
  .sin_zero_1 dd 0
  .sin_zero_2 dd 0
}

addrstr sockaddr        ; адрес сокета
addrlen = $ - addrstr   ; длина  структуры адреса сокета
	
section '.text' executable
_start:

.preparation:
    ; переходим в директорию 'users'
    mov rax, 80     ; sys_chdir
    mov rdi, users  ; path
    syscall

    ; создаем сокет сервера
    mov rdi, 2                  ; AF_INET - IP v4 
    mov rsi, 1                  ; seq_packet
    mov rdx, 0                  ; default
    mov rax, 41                 ; sys_socket
    syscall
    mov [server_socket], rax    ; fd

    ; печатаем сообщение о создании сокета
    mov rsi, msg_socket_created
    call print_str

    ; привязываем адрес к сокету
    mov rax, 49                 ; SYS_BIND
    mov rdi, [server_socket]    ; дескриптор сокета
    mov rsi, addrstr            ; sockaddr_in struct
    mov rdx, addrlen            ; длина sockaddr_in
    syscall
    cmp rax, 0
    jl .bind_error

    ; печатаем сообщение о привязке адреса к сокету
    mov rsi, msg_socket_binded
    call print_str

    ; начинаем ожидание запросов на подключение
    mov rax, 50                 ; SYS_LISTEN
    mov rdi, [server_socket]    ; дескриптор сокета
    mov rsi, 10                 ; количество клиентов
    syscall
    cmp rax, 0
    jl .listen_error

    ; печатаем сообщение о начале ожидания подключений
    mov rsi, msg_listening
    call print_str

.accept_loop:
    ; Проверяем лимит подключений
    cmp qword [active_connections], 10
    jl @f

    ; Ждем завершения любого дочернего процесса
    mov rax, 61                 ; SYS_WAIT4
    mov rdi, -1                 ; Любой дочерний процесс
    xor rsi, rsi                ; Не сохранять статус
    mov rdx, 0                  ; WNOHANG (блокировать)
    xor r10, r10                ; Не нужны rusage
    syscall

    ; Если не нашли завершенный процесс
    cmp rax, 0
    jng .accept_loop

    dec qword[active_connections]

    @@:
    ; Принимаем новое подключение
    mov rax, 43                 ; SYS_ACCEPT
    mov rdi, [server_socket]
    mov rsi, client_adress
    mov rdx, len_client
    syscall
    cmp rax, 0
    jl .accept_error
    mov [client_socket], rax

    ; Увеличиваем счетчик
    inc qword [active_connections]

    mov rsi, msg_connected
    call print_str

    xor rax, rax
    mov ax, word [client_adress+2]
    mov dh, ah
    mov dl, al
    mov ah, dl
    mov al, dh
    mov rsi, client_port
    call number_str
    call print_str
    call new_line

    ; Создаем новый процесс
    mov rax, 57                 ; SYS_FORK
    syscall
    cmp rax, 0
    jl .fork_error
    je .pre_main_loop               ; Дочерний процесс

    ; Родительский процесс
    mov rdi, [client_socket]
    mov rax, 3                  ; SYS_CLOSE
    syscall

    ; Неблокирующая проверка завершенных процессов
    mov rax, 61                 ; SYS_WAIT4
    mov rdi, -1
    xor rsi, rsi
    mov rdx, 1                  ; WNOHANG
    xor r10, r10
    syscall
    cmp rax, 0
    jng .accept_loop
    
    dec qword[active_connections]
    jmp .accept_loop


.pre_main_loop:
call send_success

.main_loop:
    mov rsi, buffer
    call recieve
    cmp rax, 0
    je .client_disconnected
    
    cmp word[buffer], SIGN_IN
    je .sign_in

    cmp word[buffer], SIGN_UP
    je .sign_up

    cmp word[buffer], CHECK
    je .check

    cmp word[buffer], TRANSFER
    je .transfer
    
    cmp word[buffer], DEPOSIT
    je .deposit
    
    cmp word[buffer], WITHDRAW
    je .withdraw
    
    cmp word[buffer], TAKE_CREDIT
    je .take_credit
    
    cmp word[buffer], PAY_CREDIT
    je .pay_credit

    cmp word[buffer], SIGN_OUT
    je .sign_out

    call send_fault
    jmp .main_loop

    .sign_in:
        call send_success

        mov rsi, user.id        ; получение id
        call recieve
        cmp rax, 0
        je .client_disconnected
        cmp word[rsi], CANCEL
        je .main_loop

        call send_success

        mov rsi, container         ; получение пароля
        call recieve
        cmp rax, 0
        je .client_disconnected
        cmp word[rsi], CANCEL
        je .main_loop

        mov rsi, user
        call read_file          ; попытка прочитать файл с полученным id
        cmp rax, 0
        jl @f

        call send_success

        call check_password     ; проверка пароля
        cmp rax, 0
        jne @f

        mov rsi, buffer
        call recieve
        cmp rax, 0
        je .client_disconnected

        call send_success

        mov rsi, buffer
        call recieve
        cmp rax, 0
        je .client_disconnected

        mov rdi, [client_socket] ;загружаем файловый дескриптор
        mov rsi, user.name
        mov rax, rsi
        call len_str             ;получаем длину сообщения
        mov rdx, rax
        mov rax, 1               ;номер системного вызова записи
        syscall

        jmp .main_loop

        @@:
        call send_fault
        jmp .main_loop

    .sign_up:
        call send_success

        mov rsi, user.name
        call recieve
        cmp rax, 0
        je .client_disconnected
        cmp word[rsi], CANCEL
        je .main_loop

        call send_success

        mov rsi, user.password
        call recieve
        cmp rax, 0
        je .client_disconnected
        cmp word[rsi], CANCEL
        je .main_loop

        call create_file
        
        mov rdi, [client_socket] ;загружаем файловый дескриптор
        mov rsi, user.id
        mov rax, rsi
        call len_str             ;получаем длину сообщения
        mov rdx, rax
        mov rax, 1               ;номер системного вызова записи
        syscall

        jmp .main_loop

    .check:
        call send_success
        
        mov rsi, buffer
        call recieve
        cmp rax, 0
        je .client_disconnected

        mov rsi, user
        call read_file

        mov rdi, [client_socket] ;загружаем файловый дескриптор
        mov rax, [user.score]
        mov rsi, buffer
        call number_str
        mov rax, rsi
        call len_str             ;получаем длину сообщения
        mov rdx, rax
        mov rax, 1               ;номер системного вызова записи
        syscall

        mov rsi, buffer
        call recieve
        cmp rax, 0
        je .client_disconnected

        mov rdi, [client_socket] ;загружаем файловый дескриптор
        mov rax, [user.credit]
        mov rsi, buffer
        call number_str
        mov rax, rsi
        call len_str             ;получаем длину сообщения
        mov rdx, rax
        mov rax, 1               ;номер системного вызова записи
        syscall
        
        jmp .main_loop

    .transfer:
        call send_success

        mov rsi, target.id
        call recieve
        cmp rax, 0
        je .client_disconnected
        cmp word[rsi], CANCEL
        je .main_loop

        call send_success

        mov rsi, container
        call recieve
        cmp rax, 0
        je .client_disconnected
        cmp word[rsi], CANCEL
        je .main_loop

        mov rsi, target
        call read_file
        cmp rax, 0
        jl @f

        call send_success

        mov rsi, buffer
        call recieve
        cmp rax, 0
        je .client_disconnected

        mov rsi, user
        call read_file
        
        mov rsi, container
        call str_number
        mov rbx, rax

        cmp qword[user.score], M
        jge .skip
        
        mov rcx, KOEF
        div rcx
        add rax, rbx

        .skip:
        cmp rax, qword[user.score]
        jg @f

        sub qword[user.score], rax
        add qword[target.score], rbx
        
        mov rsi, user
        call write_file
        mov rsi, target
        call write_file

        call send_success
        jmp .main_loop

        @@:
        call send_fault
        jmp .main_loop

    .deposit:
        call send_success

        mov rsi, container
        call recieve
        cmp rax, 0
        je .client_disconnected
        cmp word[rsi], CANCEL
        je .main_loop

        mov rsi, user
        call read_file

        mov rsi, container
        call str_number
        add [user.score], rax

        mov rsi, user
        call write_file

        call send_success

        jmp .main_loop

    .withdraw:
        call send_success

        mov rsi, container
        call recieve
        cmp rax, 0
        je .client_disconnected
        cmp word[rsi], CANCEL
        je .main_loop

        mov rsi, user
        call read_file

        mov rsi, container
        call str_number
        cmp rax, [user.score]
        jg @f

        sub [user.score], rax

        mov rsi, user
        call write_file

        call send_success
        jmp .main_loop

        @@:
        call send_fault
        jmp .main_loop

    .take_credit:
        call send_success

        mov rsi, container
        call recieve
        cmp rax, 0
        je .client_disconnected
        cmp word[rsi], CANCEL
        je .main_loop

        mov rsi, user
        call read_file

        cmp [user.credit], 0
        jg @f

        call send_success

        mov rsi, buffer
        call recieve
        cmp rax, 0
        je .client_disconnected

        mov rsi, container
        call str_number
        
        cmp [user.score], M
        jge .premium
        
        cmp rax, M
        jg @f
        jmp .approved

        .premium:
        cmp rax, [user.score]
        jg @f

        .approved:
        add [user.score], rax
        add [user.credit], rax
        mov rsi, user
        call write_file

        call send_success
        jmp .main_loop

        @@:
        call send_fault
        jmp .main_loop

    .pay_credit:
        call send_success

        mov rsi, container
        call recieve
        cmp rax, 0
        je .client_disconnected
        cmp word[rsi], CANCEL
        je .main_loop

        mov rsi, user
        call read_file

        mov rsi, container
        call str_number
        push rax
        cmp rax, [user.score]
        jg @f

        call send_success

        mov rsi, buffer
        call recieve
        cmp rax, 0
        je .client_disconnected

        pop rax
        cmp rax, [user.credit]
        jg @f

        sub [user.score], rax
        sub [user.credit], rax

        mov rsi, user
        call write_file

        call send_success
        jmp .main_loop

        @@:
        call send_fault
        jmp .main_loop

    .sign_out:
        call send_success
        jmp .main_loop

.bind_error:
    mov rsi, msg_bind_error
    call print_str
    jmp .exit_parent

.listen_error:
    mov rsi, msg_listen_error
    call print_str
    jmp .exit_parent

.fork_error:
    mov rsi, msg_fork_error
    call print_str
    jmp .exit_parent

.accept_error:
    mov rsi, msg_accept_error
    call print_str
    jmp .exit_parent

.client_disconnected:
    mov rsi, msg_disconnected
    call print_str
    mov rsi, client_port
    call print_str
    call new_line
    jmp .exit_daughter

.exit_daughter:
    ; Закрываем чтение, запись из клиентского сокета
    mov rax, 48
    mov rdi, [client_socket]
    mov rsi, 2
    syscall

    ; закрываем сокет клиента
    mov rdi, [client_socket]
    mov rax, 3                   ; SYS_CLOSE
    syscall

    call exit

.exit_parent:
    ;;Закрываем чтение, запись из серверного сокета
    mov rax, 48
    mov rdi, [server_socket]
    mov rsi, 2
    syscall

    ;;Закрываем серверный сокет
    mov rdi, [server_socket]
    mov rax, 3
    syscall
    
    call exit

; ФУНКЦИИ

; получить сообщение от клиента
; ввод: rsi - место для строки
; вывод: rax - количество полученных байтов
recieve:
    mov rax, 0               ;номер системного вызова чтения
    mov rdi, [client_socket] ;загружаем файловый дескриптор
    mov rdx, 20              ;устанавливаем количество считываемых данных
    syscall
    mov byte[rsi+rax], 0
    ret

; отправить сообщение об успехе
; ввод: нет
; вывод: нет
send_success:
    push rax

    mov rax, 1               ;номер системного вызова записи
    mov rdi, [client_socket] ;загружаем файловый дескриптор
    mov rsi, msg_success
    mov rax, rsi
    call len_str             ;получаем длину сообщения
    mov rdx, rax
    syscall

    pop rax
    ret

; отправить сообщение о неудаче
; ввод: нет
; вывод: нет
send_fault:
    mov rax, 1               ;номер системного вызова записи
    mov rdi, [client_socket] ;загружаем файловый дескриптор
    mov rsi, msg_fault
    mov rax, rsi
    call len_str             ;получаем длину сообщения
    mov rdx, rax
    syscall
    ret

; создание файла с id пользователя в названии, id генерируется случайно
; ввод: нет
; вывод: нет
create_file:
    ; открываем ГСЧ
    mov rax, 2
    mov rdi, f
    mov rsi, 0
    syscall
    mov [rand], rax

    ; инициализируем начальные значения
    mov [user.score], 0
    mov [user.credit], 0

    .try_generate:
        ; читаем 4 байта из /dev/random
        mov rax, 0
        mov rdi, [rand]
        mov rsi, buffer
        mov rdx, 4
        syscall

        ; генерируем 6-значный ID (от 100000 до 999999)
        mov eax, dword[buffer]
        and rax, 0x7FFFFFFF  ; убираем возможный знаковый бит
        mov rbx, 900000
        xor rdx, rdx
        div rbx
        add rdx, 100000      ; гарантируем 6 цифр
        mov rax, rdx
        mov rsi, user.id
        call number_str

        ; проверяем существование файла (sys_access)
        mov rax, 21         ; sys_access
        mov rdi, user.id
        mov rsi, 0          ; F_OK (проверка существования)
        syscall
        cmp rax, 0
        je .try_generate    ; если файл существует, пробуем снова

    ; создаем файл
    mov rax, 2
    mov rdi, user.id
    mov rsi, 101o       ; O_CREAT|O_WRONLY
    mov rdx, 600o       ; права доступа -rw-------
    syscall
    mov rdi, rax        ; файловый дескриптор

    ; записываем данные
    mov rsi, user.name
    call writeline

    mov rsi, user.password
    call writeline

    mov rax, [user.score]
    mov rsi, buffer
    call number_str
    call writeline

    mov rax, [user.credit]
    mov rsi, buffer
    call number_str
    call writeline

    ; закрываем файл
    mov rax, 3
    syscall

    ; закрываем ГСЧ
    mov rax, 3
    mov rdi, [rand]
    syscall

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

; проверка правильности пароля (container и user.password)
; ввод: нет
; вывод: rax - 0, если правильно, иначе 1
check_password:
    mov r9, container
    mov r10, user.password

    .check_loop:
        mov al, byte[r9]
        mov bl, byte[r10]
        cmp al, bl
        jne .check_fault

        cmp al, 0
        je .check_success

        inc r9
        inc r10
        jmp .check_loop

    .check_success:
    mov rax, 0
    ret

    .check_fault:
    mov rax, 1
    ret
