asect 0

main:            ext
default_handler: ext
uart_handler:    ext

dc main,            0
dc default_handler, 0
dc default_handler, 0
dc default_handler, 0
dc default_handler, 0
dc uart_handler,    0

align 0x80

rsect exc_handlers

default_handler>
    halt

uart_handler>
    push r0
    push r1

    ldi  r0, 0x7F80
    ldb  r0, r1
    stb  r0, r1

    pop  r1
    pop  r0
    rti

rsect main

main>
    ei

main_loop>
    wait
    br   main_loop

end.