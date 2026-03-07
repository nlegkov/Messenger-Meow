asect 0

    ldi r0, 0xF0

loop:
    ldi r1, 72
    st  r0, r1
    ldi r1, 69
    st  r0, r1
    ldi r1, 76
    st  r0, r1
    ldi r1, 76
    st  r0, r1
    ldi r1, 79
    st  r0, r1
    ldi r1, 32
    st  r0, r1
    br  loop

end