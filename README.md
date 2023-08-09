You are on the reedos branch. That means you probably want to checkout to some interesting branch of the reedos submodule before building. Your interest is probably a `make virt-run QEMU_FLAGS='-S -s'` and a `cd kernel; riscv64gc-elf-gdb kernel.elf` in two different terminals in the root of saneboot.

This is an attempt at a sane booting protocol for RISC-V. Specifically it targets the StarFive boards. It also supports the qemu virt machine for ease of development.

Be sure to have git-lfs and do a `git submodule update --init --recursive`.

This is an incomplete list of required build tools you might not already have, feel free to add to it:
- cpio
- dtc
- mtools
- full riscv cross-compiling toolchain (gcc in current setup)
- uboot-tools
There is also a full list of build dependencies of u-boot that can be found here:
https://u-boot.readthedocs.io/en/latest/build/gcc.html
You probably also want qemu-system-riscv


There are two main ways of using this system. The goal of both is to allow you to launch the binary located at `kernel/kernel` on top of an opensbi + uboot base. This means that the kernel can use opensbi calls, and uboot is just there to get the ball rolling.

- The first is to create a bootable sd card image for use with Starfive VisionFive2 boards. This can be accomplished by placing your kernel at `kernel/kernel` (or better yet, replacing the make rule for it), and running `make sd.img`. This should make a raw disk image called `sd.img` in the root of the repo that can be booted on a VF2 board after flashing the sd (likely with `dd`). Once at the uboot prompt, copy the image into memory with `load mmc 1:3 0x90000000 visionfive2.itb`, inspect it with `iminfo 0x90000000` and launch it with `bootm 0x90000000`. When in doubt, uboot has `help [cmd]`.

- The second is to run a qemu virtual machine to quickly test a kernel build. This also uses `kernel/kernel` in the same way, and can be invoked with `make virt-run`. Once at the uboot prompt, `bootm 0x90000000` should start your kernel. You can exit with `C-a x`.

Be sure to `make clean` between switching targets!

The idea is that if your kernel can be configured to expect either the virt machine or the VF2 board, then you can quickly prototype with virt, and run production with VF2.

U-boot should supply your kernel with a device tree on boot (passed in a register). The devices trees should be correct for the two targets above if your kernel expects/uses them.

An more in-depth explanation of what all the build artifacts and files are can be found in the makefile.

-------------------------------------------------------------------------------

* Sources:
- Much of the content of this repo is stolen from the StarFive/VisionFive2 example repo's build procedure.
- The device tree binary for visionfive2 is stolen from the linux build inside the starfive repo above
- The device tree binary for virt is acquired via `qemu-system-riscv64 -M virt,dumpdtb=virt.dtb`
- The .its source files are adapted from the u-boot repo docs directory
