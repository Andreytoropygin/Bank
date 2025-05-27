SYS_EXIT = 60
SYS_READ = 0
SYS_WRITE = 1

; Function exit - завершает программу с кодом возврата 0
exit:
    mov rax, SYS_EXIT
    mov rdi, 0     ; код возврата
    syscall

; Function print_str - выводит строку на стандартный вывод
; Вход: rsi - указатель на начало строки
print_str:
    push rdi       ; сохраняем регистры
    push rsi
    
    mov rax, rsi   ; получаем длину строки
    call len_str
    mov rdx, rax   ; длина строки для вывода
    mov rax, 1     ; номер системного вызова write
    mov rdi, 1     ; файловый дескриптор stdout
    syscall

    pop rsi        ; восстанавливаем регистры
    pop rdi
    ret

; Function new_line - выводит символ новой строки
new_line:
    push rdi       ; сохраняем регистры
    push rsi
    push rcx

    mov rax, 0xA   ; символ новой строки
    push rax       ; помещаем в стек
    mov rdi, 1     ; stdout
    mov rsi, rsp   ; указатель на символ в стеке
    mov rdx, 1     ; длина 1 байт
    mov rax, 1     ; номер системного вызова write
    syscall
    pop rax        ; очищаем стек

    pop rcx        ; восстанавливаем регистры
    pop rsi
    pop rdi
    ret

; Function len_str - вычисляет длину строки
; Вход: rax - указатель на начало строки
; Выход: rax - длина строки
len_str:
    mov rdx, rax   ; сохраняем начало строки
    .iter:
        cmp byte [rax], 0  ; проверяем конец строки
        je .next
        inc rax            ; переходим к следующему символу
        jmp .iter
    .next:
        sub rax, rdx       ; вычисляем длину
        ret

; Function str_number - преобразует строку в число
; Вход: rsi - указатель на строку с числом
; Выход: rax - полученное число (0 при ошибке)
str_number:
    push rsi       ; сохраняем регистры
    push rdi

    xor rax, rax   ; обнуляем результат
    xor rcx, rcx   ; обнуляем счетчик
    .loop:
        xor rbx, rbx
        mov bl, byte [rsi+rcx]  ; получаем текущий символ
        cmp bl, 48             ; проверяем цифру (0-9)
        jl @f
        cmp bl, 57
        jg @f

        sub bl, 48             ; преобразуем символ в цифру
        add rax, rbx           ; добавляем к результату
        mov rbx, 10            
        mul rbx                ; умножаем на 10 для разряда
        inc rcx                ; переходим к следующему символу
        jmp .loop

    @@:
    cmp byte[rsi+rcx], 0       ; проверяем корректное завершение
    je .success
    xor rax, rax               ; возвращаем 0 при ошибке

    .success:
    mov rbx, 10
    div rbx                    ; корректируем результат

    pop rdi        ; восстанавливаем регистры
    pop rsi
    ret

; Function number_str - преобразует число в строку
; Вход: rax - число для преобразования
;       rsi - указатель на буфер для строки
number_str:
    push rdi       ; сохраняем регистры
    push rsi

    xor rcx, rcx   ; обнуляем счетчик цифр
    mov rbx, 10    ; основание системы
    .loop_1:
        xor rdx, rdx
        div rbx              ; получаем последнюю цифру
        add rdx, 48          ; преобразуем в символ
        push rdx             ; сохраняем в стек
        inc rcx              ; увеличиваем счетчик
        cmp rax, 0           ; проверяем конец числа
        jne .loop_1
    xor rdx, rdx
    .loop_2:
        pop rax              ; извлекаем символы из стека
        mov byte [rsi+rdx], al  ; записываем в буфер
        inc rdx              ; перемещаем указатель
        dec rcx              ; уменьшаем счетчик
        cmp rcx, 0           ; проверяем конец
        jne .loop_2
    mov byte [rsi+rdx], 0    ; добавляем нуль-терминатор

    pop rsi        ; восстанавливаем регистры
    pop rdi
    ret

; Function input_keyboard - читает ввод с клавиатуры
; Вход: rsi - указатель на буфер для ввода
; Выход: rax - количество прочитанных байтов
input_keyboard:
    mov rax, SYS_READ
    mov rdi, 0     ; stdin
    mov rdx, 20    ; максимальная длина
    syscall
    
    dec rax        ; убираем символ новой строки
    mov byte[rsi+rax], 0  ; добавляем нуль-терминатор
    inc rax        ; возвращаем корректную длину
    ret

; Function readline - читает строку из файла
; Вход: rsi - указатель на буфер
;       rdi - файловый дескриптор
; Выход: rsi - указатель на строку
;        rax - длина прочитанной строки
readline:
    push rdi       ; сохраняем регистры
    push rsi

    xor rcx, rcx   ; обнуляем счетчик
    .loop:
        push rcx
        mov rax, SYS_READ
        mov rdx, 1     ; читаем по 1 символу
        syscall
        pop rcx
        cmp rax, 0     ; проверяем конец файла
        je .end
        cmp byte[rsi], 0xA  ; проверяем символ новой строки
        je .end
        cmp byte[rsi], 0    ; проверяем нуль-терминатор
        je .end
        inc rsi       ; перемещаем указатель
        inc rcx       ; увеличиваем счетчик
        jmp .loop
    .end:
    mov byte[rsi], 0  ; добавляем нуль-терминатор
    sub rsi, rcx      ; возвращаем указатель на начало
    mov rax, rcx      ; возвращаем длину

    pop rsi        ; восстанавливаем регистры
    pop rdi
    ret

; Function writeline - записывает строку в файл
; Вход: rsi - указатель на строку
;       rdi - файловый дескриптор
writeline:
    push rdi       ; сохраняем регистры
    push rsi

    mov rax, rsi   ; получаем длину строки
    call len_str
    mov rdx, rax   ; длина для записи
    mov rax, SYS_WRITE
    syscall

    mov rax, 0xA   ; добавляем символ новой строки
    push rax
    mov rsi, rsp   ; указатель на символ
    mov rdx, 1     ; длина 1 байт
    mov rax, SYS_WRITE
    syscall
    pop rax        ; очищаем стек

    pop rsi        ; восстанавливаем регистры
    pop rdi
    ret
