        ## This should be the first attempt at a bootable thing for the saneboot project targetted at the starfive-visionfive2 board

        .global entry
entry:
        li a0, 42
        li a6, 0
        li a7, 1
        ecall
        j entry
