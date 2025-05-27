format elf64
public _start
include 'func.asm'

section '.bss' writable

; константы
.const:
    QUIT = 0x71             ; Код клавиши 'q' для выхода
    SIGN_IN = 0x37          ; Код команды входа '7'
    SIGN_UP = 0x38          ; Код команды регистрации '8'
    CHECK = 0x30            ; Код проверки баланса '0'
    TRANSFER = 0x31         ; Код перевода средств '1'
    DEPOSIT = 0x32          ; Код внесения средств '2'
    WITHDRAW = 0x33         ; Код снятия средств '3'
    TAKE_CREDIT = 0x34      ; Код получения кредита '4'
    PAY_CREDIT = 0x35       ; Код погашения кредита '5'
    SIGN_OUT = 0x36         ; Код выхода из системы '6'
    INVALID = 0x39          ; Код неверной команды '9'
    CANCEL = 0x15           ; Код отмены операции
    SUCCESS = '1'           ; Код успешного выполнения

    ; Номера системных вызовов
    SYS_SOCKET = 41         ; Создание сокета
    SYS_CONNECT = 42        ; Подключение к серверу
    SYS_READ = 0            ; Чтение из сокета
    SYS_WRITE = 1           ; Запись в сокет
    SYS_CLOSE = 3           ; Закрытие сокета
    SYS_SHUTDOWN = 48       ; Остановка передачи

; переменные
.var:
    server_socket dq ?      ; Дескриптор сокета сервера
    client_socket dq ?      ; Дескриптор сокета клиента
    sign_flag db 0          ; Флаг авторизации (0/1)
    input_buffer rb 100     ; Буфер для ввода команд
    buffer rb 100           ; Буфер для данных

; сообщения
.msg:
    msg_connected db 'Connected', 0xa, 0  ; Сообщение о подключении
    msg_inner_options db 'Вы авторизованы. Нажмите:',0xa,\
                            '0 для проверки состояния счета', 0xa,\
                            '1 для совершения перевода', 0xa,\
                            '2 для вноса средств', 0xa,\
                            '3 для снятия средств', 0xa,\
                            '4 для получения кредита', 0xa,\
                            '5 для оплаты кредита', 0xa,\
                            '6 для выхода из системы', 0xa,\
                            'q для завершения работы', 0xa, 0
    msg_outer_options db 'Вы не авторизованы. Нажмите:',0xa,\
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
  
; Структура адреса сервера
struc sockaddr_server 
{
    .sin_family dw 2         ; AF_INET (IPv4)
    .sin_port dw 0x3d9       ; Порт 55555 (0x3d9)
    .sin_addr dd 0           ; localhost (127.0.0.1)
    .sin_zero_1 dd 0         ; Заполнители
    .sin_zero_2 dd 0
}

addrstr_server sockaddr_server 
addrlen_server = $ - addrstr_server  ; Размер структуры

section '.text' executable
_start:

.connection:
    ; Создание TCP-сокета
    mov rdi, 2       ; AF_INET (IPv4)
    mov rsi, 1       ; SOCK_STREAM (TCP)
    mov rdx, 0       ; Протокол по умолчанию
    mov rax, SYS_SOCKET
    syscall

    ; Сохранение дескриптора сокета
    mov [client_socket], rax

    ; Подключение к серверу
    mov rax, SYS_CONNECT
    mov rdi, [client_socket]
    mov rsi, addrstr_server 
    mov rdx, addrlen_server
    syscall
    cmp rax, 0
    jl  .connect_error  ; Обработка ошибки подключения

    ; Чтение приветствия от сервера
    call read_from_server

    ; Вывод сообщения о подключении
    mov rsi, msg_connected
    call print_str

.main:
    ; Вывод доступных команд
    call print_options

    ; Чтение команды пользователя
    mov rsi, input_buffer
    call input_keyboard

    ; Проверка команды выхода
    cmp word[input_buffer], QUIT
    je .exit

    ; Обработка введенной команды
    call command_handler

    ; Отправка команды на сервер
    mov rsi, input_buffer
    call write_to_server

    ; Получение ответа от сервера
    call read_from_server
    
    ; Проверка подтверждения выполнения операции
    cmp [buffer], SUCCESS
    je .success
    mov rsi, msg_fault
    call print_str
    jmp .main

    ; Разветвление по коду команды
    .success:
        ; Проверка конкретной команды и переход к соответствующей обработке
        cmp word[input_buffer], SIGN_IN
        je .sign_in          ; Переход к обработке входа

        cmp word[input_buffer], SIGN_UP
        je .sign_up          ; Переход к обработке регистрации

        cmp word[input_buffer], CHECK
        je .check            ; Переход к проверке баланса

        cmp word[input_buffer], TRANSFER
        je .transfer         ; Переход к обработке перевода

        cmp word[input_buffer], DEPOSIT
        je .deposit          ; Переход к внесению средств
        
        cmp word[input_buffer], WITHDRAW
        je .withdraw         ; Переход к снятию средств
        
        cmp word[input_buffer], TAKE_CREDIT
        je .take_credit      ; Переход к получению кредита
        
        cmp word[input_buffer], PAY_CREDIT
        je .pay_credit       ; Переход к погашению кредита
            
        cmp word[input_buffer], SIGN_OUT
        je .sign_out         ; Переход к выходу из системы

        ; Обработка входа в систему (SIGN_IN)
        .sign_in:
            ; Запрос номера счета
            mov rsi, msg_enter_id
            call print_str

            ; Чтение введенного ID
            mov rsi, input_buffer
            call input_keyboard
            cmp rax, 1              ; Проверка пустого ввода
            je .empty_enter
            call write_to_server    ; Отправка ID на сервер

            ; Получение ответа от сервера
            call read_from_server

            ; Запрос пароля
            mov rsi, msg_enter_password
            call print_str

            ; Чтение пароля
            mov rsi, input_buffer
            call input_keyboard
            cmp rax, 1              ; Проверка пустого ввода
            je .empty_enter
            call write_to_server    ; Отправка пароля на сервер
            
            ; Получение ответа от сервера
            call read_from_server

            ; Проверка существования пользователя
            cmp [buffer], SUCCESS
            je @f                   ; Пользователь найден

            ; Обработка ошибки - пользователь не найден
            mov rsi, msg_user_not_found
            call print_str
            jmp .main               ; Возврат в главное меню

            @@:
            ; Отправка подтверждения
            call write_to_server
            call read_from_server

            ; Проверка правильности пароля
            cmp [buffer], SUCCESS
            je @f                   ; Пароль верный

            ; Обработка ошибки - неверный пароль
            mov rsi, msg_incorrect_password
            call print_str
            jmp .main               ; Возврат в главное меню

            @@:
            ; Установка флага авторизации
            mov [sign_flag], 1

            ; Получение имени пользователя
            call write_to_server
            call read_from_server

            ; Приветствие пользователя
            mov rsi, msg_hello
            call print_str
            mov rsi, buffer         ; Имя пользователя из буфера
            call print_str
            call new_line

            jmp .main               ; Возврат в главное меню

        ; Обработка команды регистрации нового пользователя (SIGN_UP)
        .sign_up:
            ; Вывод запроса на ввод имени пользователя
            mov rsi, msg_enter_name
            call print_str

            ; Чтение введенного имени с клавиатуры
            mov rsi, input_buffer
            call input_keyboard
            ; Проверка на пустой ввод (только Enter)
            cmp rax, 1
            je .empty_enter
            ; Отправка имени на сервер
            call write_to_server

            ; Получение подтверждения от сервера
            call read_from_server

            ; Запрос на создание пароля
            mov rsi, msg_create_password
            call print_str

            ; Чтение введенного пароля
            mov rsi, input_buffer
            call input_keyboard
            ; Проверка на пустой ввод
            cmp rax, 1
            je .empty_enter
            ; Отправка пароля на сервер
            call write_to_server
            
            ; Получение ответа с ID нового пользователя
            call read_from_server

            ; Вывод сообщения с присвоенным ID
            mov rsi, msg_your_id
            call print_str
            ; Вывод самого ID из буфера
            mov rsi, buffer
            call print_str
            call new_line

            ; Установка флага авторизации в 1 (пользователь авторизован)
            mov [sign_flag], 1

            ; Возврат в главное меню
            jmp .main

        ; Обработка команды проверки баланса (CHECK)
        .check:
            ; Отправка запроса на проверку баланса
            call write_to_server

            ; Получение текущего баланса счета
            call read_from_server
            
            ; Вывод сообщения о балансе
            mov rsi, msg_your_score
            call print_str
            ; Вывод суммы баланса из буфера
            mov rsi, buffer
            call print_str
            call new_line

            ; Отправка подтверждения получения баланса
            call write_to_server

            ; Получение суммы кредита
            call read_from_server

            ; Вывод сообщения о кредите
            mov rsi, msg_your_credit
            call print_str
            ; Вывод суммы кредита из буфера
            mov rsi, buffer
            call print_str
            call new_line

            ; Возврат в главное меню
            jmp .main

        ; Обработка команды перевода средств (TRANSFER)
        .transfer:
            ; Запрос ID получателя
            mov rsi, msg_enter_target_id
            call print_str

            ; Чтение ID получателя
            mov rsi, input_buffer
            call input_keyboard
            ; Проверка на пустой ввод
            cmp rax, 1
            je .empty_enter
            ; Отправка ID получателя на сервер
            call write_to_server

            ; Получение ответа о существовании получателя
            call read_from_server

            ; Запрос суммы перевода
            mov rsi, msg_enter_amount
            call print_str

            ; Чтение суммы перевода
            mov rsi, input_buffer
            call input_keyboard
            ; Проверка на пустой ввод
            cmp rax, 1
            je .empty_enter
            ; Отправка суммы на сервер
            call write_to_server

            ; Получение результата операции
            call read_from_server

            ; Проверка успешности операции
            cmp [buffer], SUCCESS
            je @f  ; Если успешно, продолжить

            ; Обработка ошибки - получатель не найден
            mov rsi, msg_target_not_found
            call print_str
            jmp .main

            @@:
            ; Подтверждение операции
            call write_to_server
            call read_from_server

            ; Проверка достаточности средств
            cmp [buffer], SUCCESS
            je @f  ; Если средств достаточно, продолжить

            ; Обработка ошибки - недостаточно средств
            mov rsi, msg_not_enough_money
            call print_str

            @@:
            ; Возврат в главное меню
            jmp .main
        
        ; Обработка команды внесения средств (DEPOSIT)
        .deposit:
            ; Запрос суммы для внесения
            mov rsi, msg_enter_amount
            call print_str

            ; Чтение суммы
            mov rsi, input_buffer
            call input_keyboard
            ; Проверка на пустой ввод
            cmp rax, 1
            je .empty_enter
            ; Отправка суммы на сервер
            call write_to_server

            ; Получение подтверждения операции
            call read_from_server

            ; Возврат в главное меню
            jmp .main

        ; Обработка команды снятия средств (WITHDRAW)
        .withdraw:
            ; Запрос суммы для снятия
            mov rsi, msg_enter_amount
            call print_str

            ; Чтение суммы
            mov rsi, input_buffer
            call input_keyboard
            ; Проверка на пустой ввод
            cmp rax, 1
            je .empty_enter
            ; Отправка суммы на сервер
            call write_to_server

            ; Получение результата операции
            call read_from_server

            ; Проверка успешности операции
            cmp [buffer], SUCCESS
            je @f  ; Если успешно, продолжить

            ; Обработка ошибки - недостаточно средств
            mov rsi, msg_not_enough_money
            call print_str

            @@:
            ; Возврат в главное меню
            jmp .main

        ; Обработка команды получения кредита (TAKE_CREDIT)
        .take_credit:
            ; Запрос суммы кредита
            mov rsi, msg_enter_amount
            call print_str

            ; Чтение суммы
            mov rsi, input_buffer
            call input_keyboard
            ; Проверка на пустой ввод
            cmp rax, 1
            je .empty_enter
            ; Отправка суммы на сервер
            call write_to_server

            ; Получение результата операции
            call read_from_server

            ; Проверка наличия непогашенного кредита
            cmp [buffer], SUCCESS
            je @f  ; Если кредита нет, продолжить

            ; Обработка ошибки - непогашенный кредит
            mov rsi, msg_unclosed_credit
            call print_str
            jmp .main
            
            @@:
            ; Подтверждение операции
            call write_to_server
            call read_from_server

            ; Проверка одобрения кредита
            cmp [buffer], SUCCESS
            je @f  ; Если кредит одобрен, продолжить

            ; Обработка отказа в кредите
            mov rsi, msg_credit_denied
            call print_str
            
            @@:
            ; Возврат в главное меню
            jmp .main

        ; Обработка команды погашения кредита (PAY_CREDIT)
        .pay_credit:
            ; Запрос суммы платежа
            mov rsi, msg_enter_amount
            call print_str

            ; Чтение суммы
            mov rsi, input_buffer
            call input_keyboard
            ; Проверка на пустой ввод
            cmp rax, 1
            je .empty_enter
            ; Отправка суммы на сервер
            call write_to_server

            ; Получение результата операции
            call read_from_server

            ; Проверка достаточности средств
            cmp [buffer], SUCCESS
            je @f  ; Если средств достаточно, продолжить

            ; Обработка ошибки - недостаточно средств
            mov rsi, msg_not_enough_money
            call print_str
            jmp .main
            
            @@:
            ; Подтверждение операции
            call write_to_server
            call read_from_server

            ; Проверка превышения суммы кредита
            cmp [buffer], SUCCESS
            je @f  ; Если сумма корректна, продолжить

            ; Обработка ошибки - превышение суммы кредита
            mov rsi, msg_overflow
            call print_str
            
            @@:
            ; Возврат в главное меню
            jmp .main

        ; Обработка команды выхода из системы (SIGN_OUT)
        .sign_out:
            ; Сброс флага авторизации
            mov [sign_flag], 0
            ; Вывод сообщения о выходе
            mov rsi, msg_sign_out
            call print_str
            ; Возврат в главное меню
            jmp .main

; Обработка пустого ввода (отмены операции)
.empty_enter:
    ; Вывод сообщения об отмене
    mov rsi, msg_empty_enter
    call print_str
    ; Установка кода отмены в буфер
    mov rsi, input_buffer
    mov word[input_buffer], CANCEL
    ; Отправка кода отмены на сервер
    call write_to_server
    ; Возврат в главное меню
    jmp .main

; Завершение работы клиента
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
    
    ; Остановка программы
    call exit

; Обработка ошибки подключения
.connect_error:
    ; Вывод сообщения об ошибке
    mov rsi, msg_connect_error
    call print_str

    ; Завершение работы клиента
    jmp .exit

; Функция чтения из сокета
read_from_server:
    mov rax, SYS_READ           ; Системный вызов read
    mov rdi, [client_socket]    ; Дескриптор сокета
    mov rsi, buffer             ; Буфер для данных
    mov rdx, 20                 ; Максимальный размер
    syscall
    mov byte[buffer+rax], 0     ; Добавление нуль-терминатора
    ret

; Функция записи в сокет
; Вход: rsi - указатель на данные для отправки
write_to_server:
    mov rdi, [client_socket]    ; Дескриптор сокета
    mov rax, rsi
    call len_str                ; Получение длины данных
    mov rdx, rax
    mov rax, SYS_WRITE          ; Системный вызов write
    syscall
    ret

; Функция вывода меню
print_options:
    cmp [sign_flag], 1          ; Проверка авторизации
    je .signed
    mov rsi, msg_outer_options  ; Меню для неавторизованных
    call print_str
    ret
    .signed:
    mov rsi, msg_inner_options  ; Меню для авторизованных
    call print_str
    ret

; Функция проверки команды на допустимость и преобразования ее в код команды
; Вход: input_buffer - результат, код команды, если допустимо, иначе INVALID
command_handler:
    ; Проверка состояния авторизации (авторизован/не авторизован)
    cmp [sign_flag], 1
    je .inner_options          ; Если авторизован - внутренние команды

    ; Преобразование кода команды для неавторизованного пользователя
    ; (смещение на 6 для соответствия кодам сервера)
    mov al, [input_buffer]
    add al, 6
    mov [input_buffer], al
    
    ; Проверка что команда в диапазоне SIGN_IN..SIGN_UP
    cmp word[input_buffer], SIGN_IN
    jl .invalid                ; Если меньше SIGN_IN - недопустимо
    cmp word[input_buffer], SIGN_UP
    jg .invalid                ; Если больше SIGN_UP - недопустимо
    
    jmp .valid                 ; Команда допустима

    ; Обработка команд для авторизованного пользователя
    .inner_options:
    ; Проверка что команда в диапазоне CHECK..SIGN_OUT
    cmp word[input_buffer], CHECK
    jl .invalid                ; Если меньше CHECK - недопустимо
    cmp word[input_buffer], SIGN_OUT
    jg .invalid                ; Если больше SIGN_OUT - недопустимо

    ; Выход если команда допустима
    .valid:
        ret

    ; Установка кода недопустимой команды
    .invalid:
        mov word[input_buffer], INVALID
        ret