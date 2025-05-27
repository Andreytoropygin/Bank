format elf64
public _start
include 'func.asm'

section '.bss' writable     
f db "/dev/random", 0       ; Путь к устройству генерации случайных чисел
users db './users', 0       ; Путь к каталогу с пользовательскими файлами 

; Системные вызовы
.syscalls:
    SYS_SOCKET = 41     ; Создание сокета
    SYS_BIND = 49       ; Привязка сокета
    SYS_LISTEN = 50     ; Прослушивание порта
    SYS_ACCEPT = 43     ; Принятие соединения
    SYS_FORK = 57       ; Создание процесса
    SYS_WAIT4 = 61      ; Ожидание завершения процесса
    SYS_CLOSE = 3       ; Закрытие дескриптора
    SYS_EXIT = 60       ; Завершение программы  
    SYS_READ = 0        ; Чтение из дескриптора
    SYS_WRITE = 1       ; Запись в дескриптор
    SYS_ACCESS = 21     ; Проверка доступа к файлу
    SYS_OPEN = 2        ; Открытие файла
    SYS_CHDIR = 80      ; Смена директории
    SYS_SHUTDOWN = 48   ; Закрытие соединения

; Константы программы  
.const:
    SIGN_IN = 0x37      ; Код команды входа '7'
    SIGN_UP = 0x38      ; Код команды регистрации '8'
    CHECK = 0x30        ; Код проверки баланса '0' 
    TRANSFER = 0x31     ; Код перевода средств '1'
    DEPOSIT = 0x32      ; Код внесения средств '2'
    WITHDRAW = 0x33     ; Код снятия средств '3'
    TAKE_CREDIT = 0x34  ; Код получения кредита '4'
    PAY_CREDIT = 0x35   ; Код погашения кредита '5'
    SIGN_OUT = 0x36     ; Код выхода из системы '6'
    CANCEL = 0x15       ; Код отмены операции
    M = 1000000         ; Максимальная сумма для премиум-условий (1 млн)
    KOEF = 100          ; Коэффициент комиссии (1%)
    LIM = 10            ; Лимит одновременных подключений

; Переменные программы
.var:
    active_connections dq 0 ; Счетчик активных подключений
    container rb 20         ; Буфер для временных данных  
    buffer rb 20            ; Основной рабочий буфер
    rand dq ?               ; Дескриптор ГСЧ (/dev/random)
    server_socket dq ?      ; Дескриптор серверного сокета
    client_socket dq ?      ; Дескриптор клиентского сокета
    client_adress rb 16     ; Структура адреса клиента
    len_client rq 1         ; Длина адресной структуры
    client_port rb 10       ; Буфер для порта клиента

; Сообщения программы
.msg:
    msg_success db '1', 0                           ; Сообщение об успехе
    msg_fault db '0', 0                             ; Сообщение об ошибке
    msg_listen_error db 'Error listen', 0xa, 0      ; Ошибка прослушивания
    msg_bind_error db 'Error bind', 0xa, 0          ; Ошибка привязки
    msg_fork_error db 'Error fork', 0xa, 0          ; Ошибка создания процесса
    msg_accept_error db 'Error accept', 0xa, 0      ; Ошибка принятия соединения
    msg_socket_created db 'Socket created', 0xa, 0  ; Успешное создание сокета
    msg_socket_binded db 'Socket binded', 0xa, 0    ; Успешная привязка сокета
    msg_listening db 'Listening...', 0xa, 0         ; Сообщение о начале прослушивания
    msg_connected db 'Connection on port ', 0       ; Сообщение о новом подключении
    msg_disconnected db 'Disconnection on port ', 0 ; Сообщение об отключении

; Структура данных пользователя
struc User
{
    .id rb 20          ; ID пользователя (20 байт)
    .name rb 20        ; Имя пользователя (20 байт)
    .password rb 20    ; Пароль (20 байт)
    .score dq ?        ; Баланс счета (8 байт)
    .credit dq ?       ; Сумма кредита (8 байт)
}

user User       ; Данные авторизованного пользователя  
target User     ; Данные пользователя-получателя перевода

; Структура адреса сокета
struc sockaddr
{
  .sin_family dw 2     ; Семейство адресов (AF_INET)
  .sin_port dw 0x3d9   ; Порт 55555 (в сетевом порядке байт)
  .sin_addr dd 0       ; IP-адрес (0.0.0.0 - все интерфейсы)
  .sin_zero_1 dd 0     ; Дополнение до 16 байт
  .sin_zero_2 dd 0
}

addrstr sockaddr        ; Экземпляр структуры адреса
addrlen = $ - addrstr   ; Размер структуры адреса
	
section '.text' executable
; Точка входа программы
_start:

; Подготовительный этап
.preparation:
    ; Смена рабочей директории на ./users
    mov rax, 80         ; sys_chdir
    mov rdi, users      ; путь к директории
    syscall

    ; Создание TCP-сокета
    mov rdi, 2          ; AF_INET (IPv4)
    mov rsi, 1          ; SOCK_STREAM (TCP)
    mov rdx, 0          ; Протокол по умолчанию
    mov rax, 41         ; sys_socket
    syscall
    mov [server_socket], rax ; Сохраняем дескриптор сокета

    ; Вывод сообщения о создании сокета
    mov rsi, msg_socket_created
    call print_str

    ; Привязка адреса к сокету
    mov rax, 49                 ; sys_bind
    mov rdi, [server_socket]    ; дескриптор сокета
    mov rsi, addrstr            ; структура адреса
    mov rdx, addrlen            ; размер структуры
    syscall
    cmp rax, 0
    jl .bind_error              ; Обработка ошибки привязки

    ; Вывод сообщения об успешной привязке
    mov rsi, msg_socket_binded
    call print_str

    ; Переводим сокет в режим прослушивания
    mov rax, 50                 ; sys_listen
    mov rdi, [server_socket]    ; дескриптор сокета
    mov rsi, 10                 ; максимальная очередь подключений
    syscall
    cmp rax, 0
    jl .listen_error            ; Обработка ошибки прослушивания

    ; Вывод сообщения о начале прослушивания
    mov rsi, msg_listening
    call print_str

; Основной цикл принятия подключений
.accept_loop:
    ; Проверка лимита подключений (не более 10)
    cmp qword [active_connections], LIM
    jl @f  ; Если меньше лимита, пропускаем ожидание

    ; Ожидаем завершения любого дочернего процесса
    mov rax, 61         ; sys_wait4
    mov rdi, -1         ; ожидаем любого дочернего процесса
    xor rsi, rsi        ; не сохраняем статус
    mov rdx, 0          ; флаги (0 - блокирующий вызов)
    xor r10, r10        ; не нужна информация об использовании ресурсов
    syscall

    ; Если нет завершенных процессов
    cmp rax, 0
    jng .accept_loop    ; Продолжаем ожидать

    ; Уменьшаем счетчик активных подключений
    dec qword[active_connections]

    @@:
    ; Принимаем новое подключение
    mov rax, 43         ; sys_accept
    mov rdi, [server_socket] ; серверный сокет
    mov rsi, client_adress   ; структура для адреса клиента
    mov rdx, len_client      ; длина структуры адреса
    syscall
    cmp rax, 0
    jl .accept_error    ; Обработка ошибки принятия соединения
    mov [client_socket], rax ; Сохраняем дескриптор клиентского сокета

    ; Увеличиваем счетчик активных подключений
    inc qword [active_connections]

    ; Вывод сообщения о новом подключении
    mov rsi, msg_connected
    call print_str

    ; Преобразование и вывод номера порта клиента
    xor rax, rax
    mov ax, word [client_adress+2] ; Порт в сетевом порядке байт
    mov dh, ah
    mov dl, al
    mov ah, dl
    mov al, dh          ; Преобразуем в хостовой порядок
    mov rsi, client_port
    call number_str     ; Конвертируем число в строку
    call print_str      ; Выводим номер порта
    call new_line       ; Переход на новую строку

    ; Создаем дочерний процесс для обработки клиента
    mov rax, 57         ; sys_fork
    syscall
    cmp rax, 0
    jl .fork_error      ; Обработка ошибки создания процесса
    je .pre_main_loop   ; В дочернем процессе переходим к обработке

    ; Родительский процесс:
    ; Закрываем клиентский сокет (он обрабатывается дочерним процессом)
    mov rdi, [client_socket]
    mov rax, 3          ; sys_close
    syscall

    ; Проверка завершенных дочерних процессов без блокировки
    mov rax, 61         ; sys_wait4
    mov rdi, -1         ; ждем любого дочернего процесса
    xor rsi, rsi        ; не сохраняем статус
    mov rdx, 1          ; WNOHANG - не блокировать, если нет завершенных
    xor r10, r10        ; не нужна информация об использовании ресурсов
    syscall
    cmp rax, 0          ; проверяем результат
    jng .accept_loop    ; если нет завершенных процессов, продолжаем ждать
    
    ; Уменьшаем счетчик активных подключений
    dec qword[active_connections]
    jmp .accept_loop    ; возвращаемся в начало цикла

; Подготовка дочернего процесса к работе
.pre_main_loop:
    call send_success   ; отправляем клиенту подтверждение соединения

; Главный цикл обработки команд клиента
.main_loop:
    mov rsi, buffer         ; буфер для приема команды
    call recieve            ; получаем команду от клиента
    cmp rax, 0              ; проверяем количество полученных байтов
    je .client_disconnected ; если 0 - клиент отключился
    
    ; Проверка полученной команды и переход к соответствующему обработчику
    cmp word[buffer], SIGN_IN
    je .sign_in         ; команда входа

    cmp word[buffer], SIGN_UP
    je .sign_up         ; команда регистрации

    cmp word[buffer], CHECK
    je .check           ; проверка баланса

    cmp word[buffer], TRANSFER
    je .transfer        ; перевод средств
    
    cmp word[buffer], DEPOSIT
    je .deposit         ; внесение средств
    
    cmp word[buffer], WITHDRAW
    je .withdraw        ; снятие средств
    
    cmp word[buffer], TAKE_CREDIT
    je .take_credit     ; получение кредита
    
    cmp word[buffer], PAY_CREDIT
    je .pay_credit      ; погашение кредита

    cmp word[buffer], SIGN_OUT
    je .sign_out        ; выход из системы

    ; Если команда не распознана
    call send_fault     ; отправляем сообщение об ошибке
    jmp .main_loop      ; возвращаемся в начало цикла

    ; Обработка команды входа (SIGN_IN)
    .sign_in:
        call send_success   ; подтверждаем получение команды

        ; Получаем ID пользователя
        mov rsi, user.id        ; буфер для ID
        call recieve            ; получаем ID от клиента
        cmp rax, 0              ; проверяем соединение
        je .client_disconnected
        cmp word[rsi], CANCEL   ; проверяем отмену операции
        je .main_loop           ; возвращаемся в главное меню

        call send_success       ; подтверждаем получение ID

        ; Получаем пароль
        mov rsi, container      ; временный буфер для пароля
        call recieve            ; получаем пароль
        cmp rax, 0              ; проверяем соединение
        je .client_disconnected
        cmp word[rsi], CANCEL   ; проверяем отмену операции
        je .main_loop           ; возвращаемся в главное меню

        ; Читаем данные пользователя из файла
        mov rsi, user       ; структура для хранения данных
        call read_file      ; читаем файл пользователя
        cmp rax, 0          ; проверяем результат
        jl @f               ; если ошибка - пользователь не найден

        call send_success   ; подтверждаем успешное чтение файла

        ; Проверяем пароль
        call check_password ; сравниваем полученный пароль с сохраненным
        cmp rax, 0          ; проверяем результат
        jne @f              ; если не совпадают - ошибка

        ; Получаем подтверждение от клиента
        mov rsi, buffer
        call recieve
        cmp rax, 0
        je .client_disconnected

        call send_success   ; подтверждаем успешную авторизацию

        ; Получаем подтверждение для отправки имени пользователя
        mov rsi, buffer
        call recieve
        cmp rax, 0
        je .client_disconnected

        ; Отправляем имя пользователя клиенту
        mov rdi, [client_socket]    ; файловый дескриптор сокета
        mov rsi, user.name          ; имя пользователя
        mov rax, rsi
        call len_str                ; получаем длину строки
        mov rdx, rax                ; длина сообщения
        mov rax, 1                  ; sys_write
        syscall

        jmp .main_loop          ; возвращаемся в главное меню

        @@:
        call send_fault         ; отправляем сообщение об ошибке
        jmp .main_loop          ; возвращаемся в главное меню

    ; Обработка команды регистрации (SIGN_UP)
    .sign_up:
        call send_success       ; подтверждаем получение команды

        ; Получаем имя пользователя
        mov rsi, user.name      ; буфер для имени
        call recieve            ; получаем имя
        cmp rax, 0              ; проверяем соединение
        je .client_disconnected
        cmp word[rsi], CANCEL   ; проверяем отмену операции
        je .main_loop           ; возвращаемся в главное меню

        call send_success       ; подтверждаем получение имени

        ; Получаем пароль
        mov rsi, user.password  ; буфер для пароля
        call recieve            ; получаем пароль
        cmp rax, 0              ; проверяем соединение
        je .client_disconnected
        cmp word[rsi], CANCEL   ; проверяем отмену операции
        je .main_loop           ; возвращаемся в главное меню

        ; Создаем файл пользователя
        call create_file        ; создаем новый аккаунт
        
        ; Отправляем клиенту ID нового пользователя
        mov rdi, [client_socket] ; файловый дескриптор
        mov rsi, user.id         ; ID пользователя
        mov rax, rsi
        call len_str             ; получаем длину строки
        mov rdx, rax            ; длина сообщения
        mov rax, 1              ; sys_write
        syscall

        jmp .main_loop          ; возвращаемся в главное меню

    ; Обработка команды проверки баланса (CHECK)
    .check:
        call send_success       ; Подтверждаем получение команды
        
        ; Получаем подтверждение от клиента
        mov rsi, buffer
        call recieve
        cmp rax, 0
        je .client_disconnected

        ; Читаем данные пользователя из файла
        mov rsi, user
        call read_file

        ; Отправляем баланс счета клиенту
        mov rdi, [client_socket] ; Загружаем файловый дескриптор
        mov rax, [user.score]    ; Получаем сумму баланса
        mov rsi, buffer          ; Буфер для конвертации
        call number_str          ; Конвертируем число в строку
        mov rax, rsi
        call len_str             ; Получаем длину строки
        mov rdx, rax             ; Устанавливаем длину сообщения
        mov rax, 1               ; sys_write
        syscall

        ; Получаем подтверждение для отправки кредита
        mov rsi, buffer
        call recieve
        cmp rax, 0
        je .client_disconnected

        ; Отправляем сумму кредита клиенту
        mov rdi, [client_socket] ; Загружаем файловый дескриптор
        mov rax, [user.credit]   ; Получаем сумму кредита
        mov rsi, buffer
        call number_str          ; Конвертируем число в строку
        mov rax, rsi
        call len_str             ; Получаем длину строки
        mov rdx, rax             ; Устанавливаем длину сообщения
        mov rax, 1               ; sys_write
        syscall
        
        jmp .main_loop           ; Возвращаемся в главное меню

    ; Обработка команды перевода средств (TRANSFER)
    .transfer:
        call send_success        ; Подтверждаем получение команды

        ; Получаем ID получателя
        mov rsi, target.id
        call recieve
        cmp rax, 0
        je .client_disconnected
        cmp word[rsi], CANCEL    ; Проверяем отмену операции
        je .main_loop

        call send_success        ; Подтверждаем получение ID

        ; Получаем сумму перевода
        mov rsi, container
        call recieve
        cmp rax, 0
        je .client_disconnected
        cmp word[rsi], CANCEL    ; Проверяем отмену операции
        je .main_loop

        ; Читаем данные получателя
        mov rsi, target
        call read_file
        cmp rax, 0               ; Проверяем результат
        jl @f                    ; Если ошибка - получатель не найден

        call send_success        ; Подтверждаем успешное чтение файла

        ; Получаем подтверждение от клиента
        mov rsi, buffer
        call recieve
        cmp rax, 0
        je .client_disconnected

        ; Читаем данные отправителя
        mov rsi, user
        call read_file
        
        ; Конвертируем сумму перевода в число
        mov rsi, container
        call str_number
        mov rbx, rax             ; Сохраняем сумму в RBX

        ; Проверяем премиум-статус (баланс >= 1 млн)
        cmp qword[user.score], M
        jge .skip_commission     ; Для премиум-клиентов комиссия не берется
        
        ; Рассчитываем комиссию (1% от суммы)
        mov rcx, KOEF            ; Коэффициент 100 для расчета 1%
        div rcx                  ; Делим сумму на 100
        add rax, rbx             ; Добавляем комиссию к сумме перевода

        .skip_commission:
        ; Проверяем достаточность средств
        cmp rax, qword[user.score]
        jg @f                    ; Если недостаточно средств

        ; Выполняем перевод
        sub qword[user.score], rax ; Списываем сумму с комиссией
        add qword[target.score], rbx ; Зачисляем только сумму перевода
        
        ; Сохраняем изменения
        mov rsi, user
        call write_file          ; Обновляем данные отправителя
        mov rsi, target
        call write_file          ; Обновляем данные получателя

        call send_success        ; Подтверждаем успешный перевод
        jmp .main_loop

        @@:
        call send_fault          ; Отправляем сообщение об ошибке
        jmp .main_loop

    ; Обработка команды пополнения счета (DEPOSIT)
    .deposit:
        call send_success        ; Подтверждаем получение команды

        ; Получаем сумму пополнения
        mov rsi, container
        call recieve
        cmp rax, 0
        je .client_disconnected
        cmp word[rsi], CANCEL    ; Проверяем отмену операции
        je .main_loop

        ; Читаем текущие данные пользователя
        mov rsi, user
        call read_file

        ; Конвертируем сумму в число и добавляем к балансу
        mov rsi, container
        call str_number
        add [user.score], rax

        ; Сохраняем изменения
        mov rsi, user
        call write_file

        call send_success        ; Подтверждаем успешное пополнение
        jmp .main_loop

    ; Обработка команды снятия средств (WITHDRAW)
    .withdraw:
        call send_success        ; Подтверждаем получение команды

        ; Получаем сумму снятия
        mov rsi, container
        call recieve
        cmp rax, 0
        je .client_disconnected
        cmp word[rsi], CANCEL    ; Проверяем отмену операции
        je .main_loop

        ; Читаем текущие данные пользователя
        mov rsi, user
        call read_file

        ; Конвертируем сумму в число
        mov rsi, container
        call str_number
        ; Проверяем достаточность средств
        cmp rax, [user.score]
        jg @f                    ; Если недостаточно средств

        ; Выполняем снятие
        sub [user.score], rax

        ; Сохраняем изменения
        mov rsi, user
        call write_file

        call send_success        ; Подтверждаем успешное снятие
        jmp .main_loop

        @@:
        call send_fault          ; Отправляем сообщение об ошибке
        jmp .main_loop

    ; Обработка команды получения кредита (TAKE_CREDIT)
    .take_credit:
        call send_success        ; Подтверждаем получение команды

        ; Получаем запрашиваемую сумму кредита
        mov rsi, container
        call recieve
        cmp rax, 0
        je .client_disconnected
        cmp word[rsi], CANCEL    ; Проверяем отмену операции
        je .main_loop

        ; Читаем текущие данные пользователя
        mov rsi, user
        call read_file

        ; Проверяем наличие непогашенного кредита
        cmp [user.credit], 0
        jg @f                    ; Если кредит уже есть

        call send_success        ; Подтверждаем возможность выдачи

        ; Получаем подтверждение от клиента
        mov rsi, buffer
        call recieve
        cmp rax, 0
        je .client_disconnected

        ; Конвертируем сумму в число
        mov rsi, container
        call str_number
        
        ; Проверяем условия выдачи кредита
        cmp [user.score], M      ; Проверяем премиум-статус
        jge .premium_client      ; Для премиум-клиентов особые условия
            
        ; Для обычных клиентов лимит 1 млн
        cmp rax, M
        jg @f                    ; Если запрос превышает лимит
        jmp .approve_credit      ; Одобряем кредит

        .premium_client:
        ; Для премиум-клиентов лимит - текущий баланс
        cmp rax, [user.score]
        jg @f                    ; Если запрос превышает баланс

        .approve_credit:
        ; Выдаем кредит
        add [user.score], rax    ; Зачисляем на счет
        add [user.credit], rax   ; Увеличиваем сумму долга
        
        ; Сохраняем изменения
        mov rsi, user
        call write_file

        call send_success        ; Подтверждаем выдачу
        jmp .main_loop

        @@:
        call send_fault          ; Отправляем отказ
        jmp .main_loop

    ; Обработка команды погашения кредита (PAY_CREDIT)
    .pay_credit:
        call send_success        ; Подтверждаем получение команды

        ; Получаем сумму платежа
        mov rsi, container
        call recieve
        cmp rax, 0
        je .client_disconnected
        cmp word[rsi], CANCEL    ; Проверяем отмену операции
        je .main_loop

        ; Читаем текущие данные пользователя
        mov rsi, user
        call read_file

        ; Конвертируем сумму в число
        mov rsi, container
        call str_number
        push rax                 ; Сохраняем сумму платежа

        ; Проверяем достаточность средств
        cmp rax, [user.score]
        jg @f                    ; Если недостаточно средств

        call send_success        ; Подтверждаем возможность платежа

        ; Получаем подтверждение от клиента
        mov rsi, buffer
        call recieve
        cmp rax, 0
        je .client_disconnected

        pop rax                  ; Восстанавливаем сумму платежа
        ; Проверяем не превышает ли платеж сумму долга
        cmp rax, [user.credit]
        jg @f                    ; Если превышает

        ; Выполняем погашение
        sub [user.score], rax    ; Списываем со счета
        sub [user.credit], rax   ; Уменьшаем долг
        
        ; Сохраняем изменения
        mov rsi, user
        call write_file

        call send_success        ; Подтверждаем погашение
        jmp .main_loop

        @@:
        call send_fault          ; Отправляем сообщение об ошибке
        jmp .main_loop

    ; Обработка команды выхода из системы (SIGN_OUT)
    .sign_out:
        call send_success        ; Подтверждаем выход
        jmp .main_loop           ; Продолжаем обработку команд

; Обработка ошибки привязки сокета
.bind_error:
    mov rsi, msg_bind_error
    call print_str
    jmp .exit_parent

; Обработка ошибки прослушивания порта
.listen_error:
    mov rsi, msg_listen_error
    call print_str
    jmp .exit_parent

; Обработка ошибки создания процесса
.fork_error:
    mov rsi, msg_fork_error
    call print_str
    jmp .exit_parent

; Обработка ошибки принятия соединения
.accept_error:
    mov rsi, msg_accept_error
    call print_str
    jmp .exit_parent

; Обработка отключения клиента
.client_disconnected:
    ; Выводим сообщение об отключении
    mov rsi, msg_disconnected
    call print_str
    ; Выводим номер порта клиента
    mov rsi, client_port
    call print_str
    call new_line
    jmp .exit_daughter       ; Завершаем дочерний процесс

; Завершение дочернего процесса
.exit_daughter:
    ; Завершаем соединение с клиентом
    mov rax, 48              ; sys_shutdown
    mov rdi, [client_socket] ; дескриптор сокета
    mov rsi, 2               ; SHUT_RDWR - отключаем чтение и запись
    syscall

    ; Закрываем сокет клиента
    mov rdi, [client_socket]
    mov rax, 3               ; sys_close
    syscall

    call exit                ; Завершаем процесс

; Завершение родительского процесса
.exit_parent:
    ; Завершаем работу серверного сокета
    mov rax, 48              ; sys_shutdown
    mov rdi, [server_socket] ; дескриптор серверного сокета
    mov rsi, 2               ; SHUT_RDWR
    syscall

    ; Закрываем серверный сокет
    mov rdi, [server_socket]
    mov rax, 3               ; sys_close
    syscall
    
    call exit                ; Завершаем программу


; Функции сервера

; Функция получения сообщения от клиента
; Вход: rsi - указатель на буфер для данных
; Выход: rax - количество полученных байт (0 если соединение разорвано)
recieve:
    mov rax, 0               ; sys_read
    mov rdi, [client_socket] ; дескриптор клиентского сокета
    mov rdx, 20              ; максимальный размер данных
    syscall
    mov byte[rsi+rax], 0     ; добавляем нуль-терминатор
    ret

; Функция отправки сообщения об успехе
; Использует глобальную переменную msg_success ('1')
send_success:
    push rax                 ; сохраняем регистры
    push rdi
    push rsi
    push rdx
    
    mov rax, 1               ; sys_write
    mov rdi, [client_socket] ; дескриптор сокета
    mov rsi, msg_success     ; сообщение "1"
    mov rdx, 1               ; длина сообщения
    syscall

    pop rdx                  ; восстанавливаем регистры
    pop rsi
    pop rdi
    pop rax
    ret

; Функция отправки сообщения об ошибке 
; Использует глобальную переменную msg_fault ('0')
send_fault:
    mov rax, 1               ; sys_write
    mov rdi, [client_socket] ; дескриптор сокета
    mov rsi, msg_fault       ; сообщение "0"
    mov rdx, 1               ; длина сообщения
    syscall
    ret

; Функция создания файла пользователя со случайным ID
; Генерирует уникальный 6-значный ID, создает файл и сохраняет данные пользователя
; Входные данные:
;   user.name - имя пользователя
;   user.password - пароль
; Выходные данные:
;   user.id - сгенерированный ID пользователя
;   user.score - инициализируется 0
;   user.credit - инициализируется 0
create_file:
    ; Открываем устройство /dev/random для получения случайных чисел
    mov rax, 2               ; sys_open
    mov rdi, f               ; путь к файлу "/dev/random"
    mov rsi, 0               ; флаг O_RDONLY
    syscall
    mov [rand], rax          ; сохраняем файловый дескриптор

    ; Инициализация начальных значений счета
    mov qword [user.score], 0  ; начальный баланс = 0
    mov qword [user.credit], 0 ; начальный кредит = 0

    ; Цикл генерации уникального ID пользователя
    .try_generate:
        ; Чтение 4 байт случайных данных
        mov rax, 0           ; sys_read
        mov rdi, [rand]      ; дескриптор /dev/random
        mov rsi, buffer      ; буфер для чтения
        mov rdx, 4           ; читаем 4 байта
        syscall

        ; Преобразование случайных данных в 6-значный ID (100000-999999)
        mov eax, dword [buffer]  ; загружаем случайные 4 байта
        and rax, 0x7FFFFFFF      ; убираем знаковый бит для положительного числа
        mov rbx, 900000          ; диапазон значений (999999-100000+1)
        xor rdx, rdx
        div rbx                  ; делим на 900000
        add rdx, 100000          ; получаем число в диапазоне 100000-999999
        mov rax, rdx
        mov rsi, user.id         ; буфер для ID пользователя
        call number_str          ; конвертируем число в строку

        ; Проверка существования файла с таким ID
        mov rax, 21              ; sys_access
        mov rdi, user.id         ; имя файла для проверки
        mov rsi, 0               ; F_OK (проверка существования)
        syscall
        cmp rax, 0
        je .try_generate         ; если файл существует, генерируем новый ID

    ; Создание файла пользователя
    mov rax, 2               ; sys_open
    mov rdi, user.id         ; имя файла (ID пользователя)
    mov rsi, 101o            ; флаги O_CREAT|O_WRONLY
    mov rdx, 600o            ; права доступа -rw-------
    syscall
    mov rdi, rax             ; сохраняем файловый дескриптор

    ; Запись данных пользователя в файл (в текстовом формате)
    ; 1. Записываем имя пользователя
    mov rsi, user.name       ; указатель на имя
    call writeline           ; запись строки с переводом строки

    ; 2. Записываем пароль
    mov rsi, user.password   ; указатель на пароль
    call writeline

    ; 3. Записываем начальный баланс (0)
    mov rax, [user.score]    ; получаем баланс (0)
    mov rsi, buffer          ; буфер для конвертации
    call number_str          ; конвертируем в строку
    call writeline           ; записываем

    ; 4. Записываем сумму кредита (0)
    mov rax, [user.credit]   ; получаем кредит (0)
    call number_str          ; конвертируем в строку
    call writeline           ; записываем

    ; Закрытие файла пользователя
    mov rax, 3               ; sys_close
    syscall

    ; Закрытие устройства /dev/random
    mov rax, 3               ; sys_close
    mov rdi, [rand]          ; дескриптор /dev/random
    syscall
    ret

; чтение из файла пользователя
; ввод: rsi - место для данных
; вывод: rax - 0 в случае успеха, иначе -1
read_file:
    mov r9, rsi              ; сохраняем указатель на структуру User

    ; открываем файл пользователя для чтения
    mov rax, 2               ; sys_open
    mov rdi, r9              ; имя файла (user.id)
    mov rsi, 0               ; O_RDONLY
    syscall
    cmp rax, 0               ; проверяем успешность открытия
    jl .fault_read           ; если ошибка - возвращаем -1

    mov rdi, rax             ; сохраняем файловый дескриптор
    mov rsi, r9              ; восстанавливаем указатель на User
    add rsi, 20              ; смещение до поля name (20 байт)
    call readline            ; читаем имя пользователя

    mov rsi, r9              ; снова указатель на User
    add rsi, 40              ; смещение до поля password (40 байт)
    call readline            ; читаем пароль

    ; читаем и преобразуем баланс счета
    mov rsi, buffer          ; временный буфер
    call readline            ; читаем строку с балансом
    xor rax, rax             ; обнуляем rax перед преобразованием
    call str_number          ; конвертируем строку в число
    mov qword[r9+60], rax    ; сохраняем в user.score (смещение 60 байт)

    ; читаем и преобразуем сумму кредита
    mov rsi, buffer          ; временный буфер
    call readline            ; читаем строку с кредитом
    xor rax, rax             ; обнуляем rax перед преобразованием
    call str_number          ; конвертируем строку в число
    mov qword[r9+68], rax    ; сохраняем в user.credit (смещение 68 байт)

    ; закрываем файл
    mov rax, 3               ; sys_close
    syscall

    xor rax, rax             ; возвращаем 0 (успех)
    .fault_read:
    ret                      ; возвращаем -1 (в rax уже -1 при ошибке)

; запись в файл пользователя
; ввод: rsi - источник данных
; вывод: нет
write_file:
    mov r9, rsi              ; сохраняем указатель на структуру User

    ; открываем файл пользователя для записи
    mov rax, 2               ; sys_open
    mov rdi, r9              ; имя файла (user.id)
    mov rsi, 1001o           ; O_WRONLY|O_CREAT|O_TRUNC
    syscall
    mov rdi, rax             ; сохраняем файловый дескриптор

    ; записываем имя пользователя
    mov rsi, r9              ; указатель на User
    add rsi, 20              ; смещение до поля name (20 байт)
    call writeline           ; записываем строку

    ; записываем пароль
    mov rsi, r9              ; указатель на User
    add rsi, 40              ; смещение до поля password (40 байт)
    call writeline           ; записываем строку

    ; записываем баланс счета
    mov rax, qword[r9+60]    ; получаем user.score (смещение 60 байт)
    mov rsi, buffer          ; временный буфер
    call number_str          ; конвертируем число в строку
    call writeline           ; записываем строку

    ; записываем сумму кредита
    mov rax, qword[r9+68]    ; получаем user.credit (смещение 68 байт)
    call number_str          ; конвертируем число в строку
    call writeline           ; записываем строку

    ; закрываем файл
    mov rax, 3               ; sys_close
    syscall
    ret

; проверка правильности пароля (container и user.password)
; ввод: нет
; вывод: rax - 0, если правильно, иначе 1
check_password:
    mov r9, container        ; указатель на введенный пароль
    mov r10, user.password   ; указатель на сохраненный пароль

    .check_loop:
        mov al, byte[r9]     ; загружаем символ из введенного пароля
        mov bl, byte[r10]    ; загружаем символ из сохраненного пароля
        cmp al, bl           ; сравниваем символы
        jne .check_fault     ; если не равны - ошибка

        cmp al, 0            ; проверяем конец строки
        je .check_success    ; если оба символа '\0' - пароль верный

        inc r9               ; переходим к следующему символу введенного пароля
        inc r10              ; переходим к следующему символу сохраненного пароля
        jmp .check_loop      ; продолжаем проверку

    .check_success:
    mov rax, 0               ; возвращаем 0 (пароль верный)
    ret

    .check_fault:
    mov rax, 1               ; возвращаем 1 (пароль неверный)
    ret