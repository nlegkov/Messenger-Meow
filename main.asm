asect 0


dc main,            0 #0
dc default_handler, 0 #1
dc default_handler, 0 #2
dc default_handler, 0 #3
dc default_handler, 0 #4
dc default_handler, 0 #5
dc default_handler, 0 #6
dc default_handler, 0 #7
dc input_inter, 0 #8


default_handler>
    halt

main>
    ldi sp, 0xf000

    sti

wait>
    jmp wait

input_inter>
    ldi r0, 0xff00
    ldi r1, 0x0000
    stw r1, r0
    rti

end.


end.