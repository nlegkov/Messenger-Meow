asect 0

main:            ext
default_handler: ext
uart_handler:    ext

dc main,            0
dc default_handler, 0
dc default_hxxxandler, 0
dc default_handler, 0
dc default_handler, 0
dc uart_handler,    0

align 0x80

ldi r0, main
jmp r0

end.