This is an attempt at a sane booting protocol for RISC-V. Specifically it targets the StarFive boards. Ideally it would also support Qemu's sifive_u target, but we will see.

Much of the content of this repo is stolen from the StarFive/VisionFive2 example repo's build procedure.

Be sure to have git-lfs and do a `git submodule update --init --recursive`.

This is an incomplete list of required build tools you might not already have, feel free to add to it:
- cpio
- dtc
- mtools

Parallel building with `make -j$(nproc)` is highly encouraged, as it setting `CROSS_COMPILE=riscv64-linux-gnu-` before anything, although in theory the makefile should do it for you.

The goal is to make an sdcard image that will boot to the u-boot prompt in S mode. After that we can put our real kernel on the remaining space on the sdcard and boot from the u-boot prompt. (Or does the entry of the target kernel get baked into the binary blob? I don't think so...)

If everything works as intended, once the repo is set up, then you should be able to make an sdcard image with just
```
make format-boot-loader DISK=/dev/_
```
one thing you might want to do for further control / inspection is make a file backed block device, and then talk about it as a loop device with
```
sudo losetup -fP sd.img
```
which should make a new `/dev/loop_` for you. Be sure to unloop it with `sudo losetup -d /dev/loop_`!

For reasons I don't fully understand, the format-boot-loader target doesn't always work, instead giving an error about not being able to find the boot partitions. Try running it again and make sure your block device, real or file backed is at least 4G.
