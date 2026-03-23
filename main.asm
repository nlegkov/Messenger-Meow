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
    jsr input_inter
    ldi r1, 34
    jsr main

input_inter>
    ldi r0, 0xff00
    ldw r0, r0
    ldi r2, 0xff02
    ldw r2, r2
    jsr main

end.


end.