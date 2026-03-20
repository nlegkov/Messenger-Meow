# =============================================================================
# CdM-16 Chat Server
# Мессенджер для нескольких пользователей через UART
#
# Архитектура:
#   - 4 слота UART, каждый = один клиент
#   - UART memory-mapped I/O базовый адрес 0xE000
#   - Прерывания: каждый UART запрашивает IRQ при готовности байта
#
# Карта памяти данных:
#   0x0000-0x00FF  стек (sp инициализируется в 0x0100)
#   0x1000-0x11FF  RX-буферы (4 слота * 64 байта)
#   0x2000-0x203F  буферы имён (4 слота * 16 байт)
#   0x3000-0x307F  broadcast-буфер (128 байт)
#   0xE000-0xE007  UART #0   (base + 0x00)
#   0xE010-0xE017  UART #1   (base + 0x10)
#   0xE020-0xE027  UART #2   (base + 0x20)
#   0xE030-0xE037  UART #3   (base + 0x30)
#
# Регистры UART (смещение от base):
#   +0  TX  (write) — записать байт для отправки
#   +2  RX  (read)  — прочитать принятый байт
#   +4  STATUS      — бит0=con, бит1=dt, бит2=tx_ready
#   +6  CTRL        — бит0=en_irq
#
# Структура RX-буфера слота (64 байта):
#   [0..61]  данные (62 байта)
#   [62]     счётчик накопленных байт
#   [63]     флаг connected (0/1)
# =============================================================================

# =============================================================================
# asect 0 — IVT (Interrupt Vector Table)
# Каждая запись: dc <pc>, <ps>
# =============================================================================
asect 0

main:           ext
default_handler: ext
irq_uart0:      ext
irq_uart1:      ext
irq_uart2:      ext
irq_uart3:      ext

# Вектор 0: старт
dc main, 0
# Вектор 1: невыровненный SP
dc default_handler, 0
# Вектор 2: невыровненный PC
dc default_handler, 0
# Вектор 3: неверная инструкция
dc default_handler, 0
# Вектор 4: double fault
dc default_handler, 0
# Векторы 5-8: IRQ от UART 0-3
# ps = 0x8000 (I-бит) — прерывания запрещены во время обработки
dc irq_uart0, 0x8000
dc irq_uart1, 0x8000
dc irq_uart2, 0x8000
dc irq_uart3, 0x8000

align 0x80

# =============================================================================
# rsect main — весь код в одной секции, чтобы не было проблем с ext
# =============================================================================
rsect main

# --- Обработчик исключений ---

default_handler>
    halt

# --- IRQ-обработчики для каждого UART ---

irq_uart0>
    push r0
    ldi r0, 0
    jsr irq_uart_handler
    pop r0
    rti

irq_uart1>
    push r0
    ldi r0, 1
    jsr irq_uart_handler
    pop r0
    rti

irq_uart2>
    push r0
    ldi r0, 2
    jsr irq_uart_handler
    pop r0
    rti

irq_uart3>
    push r0
    ldi r0, 3
    jsr irq_uart_handler
    pop r0
    rti

# =============================================================================
# main — точка входа
# =============================================================================
main>
    ldi r0, 0x0100
    stsp r0

    # memzero(0x1000, 256) — RX-буферы
    ldi r0, 0x1000
    ldi r1, 256
    jsr memzero

    # memzero(0x2000, 64) — буферы имён
    ldi r0, 0x2000
    ldi r1, 64
    jsr memzero

    # Инициализируем UART 0-3
    ldi r0, 0
    jsr uart_init_slot
    ldi r0, 1
    jsr uart_init_slot
    ldi r0, 2
    jsr uart_init_slot
    ldi r0, 3
    jsr uart_init_slot

    ei

main_loop>
    wait
    br main_loop

# =============================================================================
# uart_init_slot
# Вход: r0 = слот (0..3). Портит r1, r2
# =============================================================================
uart_init_slot>
    # r1 = 0xE000 + slot * 16
    shl r0, r1, 4
    ldi r2, 0xE000
    add r1, r2, r1
    # r2 = &CTRL = base + 6
    ldi r2, 6
    add r1, r2, r2
    # CTRL = 1 (en_irq)
    ldi r1, 1
    stb r2, r1
    rts

# =============================================================================
# irq_uart_handler
# Вход: r0 = слот (0..3)
# =============================================================================
irq_uart_handler>
    push r1
    push r2
    push r3
    push r4
    push r5
    push r6

    # r1 = UART base = 0xE000 + slot * 16
    shl r0, r1, 4
    ldi r2, 0xE000
    add r1, r2, r1

    # Читаем STATUS в r2
    ldi r3, 4
    add r1, r3, r3
    ldb r3, r2

    # Проверяем con (бит 0)
    ldi r3, 1
    and r2, r3, r3
    bne h_con_ok

    # Нет соединения → connected = 0
    shl r0, r3, 6
    ldi r4, 0x1000
    add r3, r4, r3
    ldi r4, 63
    add r3, r4, r4
    ldi r3, 0
    stb r4, r3
    br h_done

h_con_ok>
    # connected = 1
    shl r0, r3, 6
    ldi r4, 0x1000
    add r3, r4, r3
    ldi r4, 63
    add r3, r4, r4
    ldi r5, 1
    stb r4, r5

    # Перечитываем STATUS
    shl r0, r4, 4
    ldi r5, 0xE000
    add r4, r5, r4
    ldi r5, 4
    add r4, r5, r5
    ldb r5, r2

    # Проверяем dt (бит 1)
    ldi r3, 2
    and r2, r3, r3
    beq h_done

    # Читаем байт из RX в r4
    shl r0, r5, 4
    ldi r6, 0xE000
    add r5, r6, r5
    ldi r6, 2
    add r5, r6, r6
    ldb r6, r4

    # r5 = &rx_buf[slot]
    shl r0, r5, 6
    ldi r6, 0x1000
    add r5, r6, r5

    # r3 = len = rx_buf[slot][62]
    ldi r6, 62
    add r5, r6, r6
    ldb r6, r3

    # Проверяем LF (10)
    ldi r6, 10
    cmp r4, r6
    beq h_newline

    # Проверяем CR (13) — игнорируем
    ldi r6, 13
    cmp r4, r6
    beq h_done

    # Обычный символ: добавляем если len < 62
    ldi r6, 62
    cmp r3, r6
    bhs h_done
    add r5, r3, r6
    stb r6, r4
    add r3, 1
    ldi r6, 62
    add r5, r6, r6
    stb r6, r3
    br h_done

h_newline>
    # Пустая строка?
    ldi r6, 0
    cmp r3, r6
    beq h_done

    # Проверяем наличие имени: name_buf[slot][0]
    shl r0, r6, 4
    ldi r4, 0x2000
    add r6, r4, r6
    ldb r6, r4
    ldi r6, 0
    cmp r4, r6
    beq h_register

    # Имя есть — broadcast
    jsr broadcast_message
    ldi r4, 62
    add r5, r4, r4
    ldi r3, 0
    stb r4, r3
    br h_done

h_register>
    # Копируем rx_buf[slot] → name_buf[slot] (max 15 + null)
    shl r0, r4, 4
    ldi r6, 0x2000
    add r4, r6, r4

    ldi r6, 15
    cmp r3, r6
    bls h_len_ok
    ldi r3, 15
h_len_ok>
    push r0
    move r4, r0
    move r5, r1
    move r3, r2
    jsr memcpy
    pop r0

    # null-terminate
    shl r0, r4, 4
    ldi r6, 0x2000
    add r4, r6, r4
    add r4, r3, r6
    ldi r4, 0
    stb r6, r4

    # Очищаем rx len
    ldi r4, 62
    add r5, r4, r4
    ldi r3, 0
    stb r4, r3

    jsr send_welcome
    jsr broadcast_join

h_done>
    pop r6
    pop r5
    pop r4
    pop r3
    pop r2
    pop r1
    rts

# =============================================================================
# broadcast_message — "<n>: <msg>\r\n" → всем слотам кроме r0
# Вход: r0 = слот отправителя
# =============================================================================
broadcast_message>
    push r1
    push r2
    push r3
    push r4
    push r5
    push r6

    ldi r6, 0x3000

    # Копируем имя отправителя
    shl r0, r1, 4
    ldi r2, 0x2000
    add r1, r2, r1

bm_name>
    ldb r1, r2
    ldi r4, 0
    cmp r2, r4
    beq bm_name_end
    stb r6, r2
    add r1, 1
    add r6, 1
    br bm_name
bm_name_end>

    # ": "
    ldi r2, 58
    stb r6, r2
    add r6, 1
    ldi r2, 32
    stb r6, r2
    add r6, 1

    # Копируем сообщение из rx_buf[slot]
    shl r0, r1, 6
    ldi r2, 0x1000
    add r1, r2, r1
    ldi r2, 62
    add r1, r2, r2
    ldb r2, r3

bm_msg>
    ldi r4, 0
    cmp r3, r4
    beq bm_msg_end
    ldb r1, r2
    stb r6, r2
    add r1, 1
    add r6, 1
    add r3, -1
    br bm_msg
bm_msg_end>

    # "\r\n"
    ldi r2, 13
    stb r6, r2
    add r6, 1
    ldi r2, 10
    stb r6, r2
    add r6, 1

    # Длина пакета = r6 - 0x3000
    ldi r4, 0x3000
    sub r6, r4, r4

    # Рассылаем всем кроме r0
    ldi r1, 0
bm_loop>
    cmp r1, 4
    beq bm_done
    cmp r1, r0
    beq bm_next

    # Проверяем connected
    shl r1, r2, 6
    ldi r3, 0x1000
    add r2, r3, r2
    ldi r3, 63
    add r2, r3, r3
    ldb r3, r2
    ldi r2, 0
    cmp r3, r2
    beq bm_next

    push r0
    push r1
    push r4
    ldi r0, 0x3000
    move r1, r1
    move r4, r2
    jsr uart_send_bytes
    pop r4
    pop r1
    pop r0

bm_next>
    add r1, 1
    br bm_loop
bm_done>
    pop r6
    pop r5
    pop r4
    pop r3
    pop r2
    pop r1
    rts

# =============================================================================
# uart_send_bytes
# Вход: r0 = адрес буфера, r1 = слот, r2 = длина
# =============================================================================
uart_send_bytes>
    push r3
    push r4
    push r5

    shl r1, r3, 4
    ldi r4, 0xE000
    add r3, r4, r3
    # r4 = &TX = base + 0
    move r3, r4

usb_loop>
    ldi r5, 0
    cmp r2, r5
    beq usb_done

    # Ждём tx_ready (бит 2 STATUS)
    ldi r5, 4
    add r3, r5, r5
usb_wait>
    ldb r5, r5
    ldi r6, 4
    and r5, r6, r5
    ldi r6, 0
    cmp r5, r6
    beq usb_wait

    # Отправляем байт
    ldb r0, r5
    stb r4, r5
    add r0, 1
    add r2, -1
    br usb_loop
usb_done>
    pop r5
    pop r4
    pop r3
    rts

# =============================================================================
# send_welcome — "Welcome, <n>!\r\n" → слот r0
# =============================================================================
send_welcome>
    push r0
    push r1
    push r2

    ldi r1, str_welcome
    ldi r2, 9
    jsr uart_send_bytes

    # Имя
    shl r0, r1, 4
    ldi r2, 0x2000
    add r1, r2, r1
    push r0
    move r1, r0
    jsr strlen
    move r0, r2
    pop r0
    shl r0, r3, 4
    ldi r1, 0x2000
    add r3, r1, r1
    jsr uart_send_bytes

    ldi r1, str_excl
    ldi r2, 3
    jsr uart_send_bytes

    pop r2
    pop r1
    pop r0
    rts

# =============================================================================
# broadcast_join — "<n> joined\r\n" → всем кроме r0
# =============================================================================
broadcast_join>
    push r1
    push r2
    push r3
    push r4

    ldi r3, 0x3000
    move r3, r4

    shl r0, r1, 4
    ldi r2, 0x2000
    add r1, r2, r1

bj_name>
    ldb r1, r2
    ldi r3, 0
    cmp r2, r3
    beq bj_name_end
    stb r4, r2
    add r1, 1
    add r4, 1
    br bj_name
bj_name_end>

    ldi r1, str_joined
    ldi r2, 10
bj_copy>
    ldi r3, 0
    cmp r2, r3
    beq bj_copy_end
    ldb r1, r3
    stb r4, r3
    add r1, 1
    add r4, 1
    add r2, -1
    br bj_copy
bj_copy_end>

    ldi r3, 0x3000
    sub r4, r3, r2

    ldi r1, 0
bj_loop>
    cmp r1, 4
    beq bj_done
    cmp r1, r0
    beq bj_next

    shl r1, r3, 6
    ldi r4, 0x1000
    add r3, r4, r3
    ldi r4, 63
    add r3, r4, r4
    ldb r4, r3
    ldi r3, 0
    cmp r4, r3
    beq bj_next

    push r0
    push r1
    push r2
    ldi r0, 0x3000
    jsr uart_send_bytes
    pop r2
    pop r1
    pop r0

bj_next>
    add r1, 1
    br bj_loop
bj_done>
    pop r4
    pop r3
    pop r2
    pop r1
    rts

# =============================================================================
# strlen — длина null-terminated строки
# Вход: r0 = адрес. Выход: r0 = длина
# =============================================================================
strlen>
    push r1
    push r2
    move r0, r1
    ldi r0, 0
sl_loop>
    ldb r1, r2
    ldi r3, 0
    cmp r2, r3
    beq sl_done
    add r1, 1
    add r0, 1
    br sl_loop
sl_done>
    pop r2
    pop r1
    rts

# =============================================================================
# memzero — заполнить r1 байт нулями начиная с адреса r0
# =============================================================================
memzero>
    push r2
    ldi r2, 0
mz_loop>
    ldi r3, 0
    cmp r1, r3
    beq mz_done
    stb r0, r2
    add r0, 1
    add r1, -1
    br mz_loop
mz_done>
    pop r2
    rts

# =============================================================================
# memcpy — скопировать r2 байт из r1 в r0
# =============================================================================
memcpy>
    push r3
mc_loop>
    ldi r4, 0
    cmp r2, r4
    beq mc_done
    ldb r1, r3
    stb r0, r3
    add r0, 1
    add r1, 1
    add r2, -1
    br mc_loop
mc_done>
    pop r3
    rts

# =============================================================================
# Строковые константы (в памяти программы, той же секции)
# =============================================================================

str_welcome>
    dc 'W', 'e', 'l', 'c', 'o', 'm', 'e', ',', ' '

str_excl>
    dc '!', 13, 10

str_joined>
    dc ' ', 'j', 'o', 'i', 'n', 'e', 'd', 13, 10, 0

end.