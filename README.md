This is an attempt at a sane booting protocol for RISC-V. Specifically it targets the StarFive boards. Ideally it would also support Qemu's sifive_u target, but we will see.

Much of the content of this repo is stolen from the StarFive/VisionFive2 example repo's build procedure.

Be sure to have git-lfs and do a `git submodule update --init --recursive`.

This is an incomplete list of required build tools you might not already have, feel free to add to it:
- cpio
- dtc

Parallel building with `make -j32` is highly encouraged, as it setting `CROSS_COMPILE=riscv64-linux-gnu-` before anything, although in theory the make file should do it for you.

The goal is to make an sdcard image that will boot to the u-boot prompt in S mode. After that we can put our real kernel on the remaining space on the sdcard and boot from the u-boot prompt. (Or does the entry of the target kernel get baked into the binary blob? I don't think so...)
