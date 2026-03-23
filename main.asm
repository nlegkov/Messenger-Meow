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
dc enter_inter, 0 #9


default_handler>
    halt

main>
    jsr input_inter
    ldi r1, 34
    jsr main

input_inter>
    ldi r0, 0xff00
    ldw r0, r0
    ldi r1, 0xff02
    ldw r1, r1    
    ldi r2, 0xff04
    add r2, r1
    stw r1, r0
    jsr main

enter_inter>
    ldi r1, 0xff02
    ldw r1, r1
    cmp r1, 0
    bgt label

    halt
    br done

label>
    ldi r0, 0xfffe
    ldw r0, r0
    stw r0, 1
    sub 1, r1
    stw 0xff02, r1
    jsr enter_inter

done>
    ldi r0, 0xfffe
    ldw r0, r0
    stw r0, 0


end.