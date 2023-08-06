# --------------------------------------------------------------------
# When in doubt, run `make all`, and read this file's comments.

#general options
CROSS_COMPILE := riscv64-linux-gnu-
export CROSS_COMPILE
MAKEFLAGS := -j1
export MAKEFLAGS
# ^ causes problems if parallel?

# opensbi options
PLATFORM := generic
export PLATFORM

# u-boot options
BOARD := starfive_visionfive2
# this is a default, and the virt targets should overwrite it

# sd image options
TOTAL_SIZE = 4G
FS_SIZE = 2G
SPL_START   = 4096
SPL_END = 8191
UBOOT_START = 8192
UBOOT_END = 16383
UBOOT_SIZE = $(shell expr $(UBOOT_END) - $(UBOOT_START) + 1)
EXT2_START = 16384
EXT2_END = 8386559
EXT2_SIZE = $(shell expr $(EXT2_END) - $(EXT2_START) + 1)
SECTOR_SIZE = 512

# Relevant partition type codes with GUID
SPL = 2E54B353-1271-4842-806F-E436D6AF6985
UBOOT = 5B193300-FC78-40CD-8002-E86C45580B47

# --------------------------------------------------------------------
# defaults
all:
	@echo -e 'You can either make an sd image for a starfive visionfive2 board or you can run a test on the qemu virt machine. To do the former, run `make sd.img` and flash that (likely with dd) to the sd card of the board. To do the later run `make virt-run`. \n\nWhen switching between targets, run `make clean` to prevent use of the wrong config file for uboot.\n\nBoth targets should enable you to boot the binary image at /kernel/kernel in the saneboot source tree. With virt, `bootm 0x90000000` should launch it. With visionfive2, you will need to load it from the sdcard with `load mmc 1:3 _ visionfive2.itb` and launch with `bootm _`, where `_` is an address of your choosing. (0x90000000 should work)'

# This is the flat image expected by uboot (the thing you boot), which
# contains a device tree binary that describes the layout of the qemu
# virt machine and the kernel that you are booting. See the .its file
# for the specifics.
fit/virt.itb:  fit/virt.its kernel/kernel
	cd fit ; \
	mkimage -f virt.its virt.itb

# This makes and runs a opensbi/uboot boot process on qemu that
# enables you to boot kernel/kernel. The idea is that if the kernel is
# largely hardware independent, then it can be quickly developed with
# this, and shipped with the sd card target. Exit qemu with C-a x.

# This informs uboot that we want a different target than visionfive2
virt-run: BOARD := qemu-riscv64_spl
virt-run: fit/virt.itb opensbi/build/platform/generic/firmware/fw_dynamic.bin \
		u-boot/.config u-boot/spl/u-boot-spl.bin u-boot/u-boot.itb
	qemu-system-riscv64 -nographic -machine virt -m 4G -bios u-boot/spl/u-boot-spl.bin \
		-device loader,file=u-boot/u-boot.itb,addr=0x80200000 \
		-device loader,file=fit/virt.itb,addr=0x90000000 \
		${QEMU_FLAGS}

# --------------------------------------------------------------------
# opensbi stuff

# These are the parts of opensbi that uboot needs. In short this is
# the part of the first stage bootloader that opensbi is responsible
# for. This is a seperate target, as uboot depends on it, but other
# parts of opensbi depend on uboot.
opensbi/build/platform/generic/firmware/fw_dynamic.bin:
	make -C opensbi

# This is the primary uboot binary, wrapped by opensbi to provide the
# expected library features. It is the second stage boot loader, and
# it is what provides the uboot prompt.
opensbi/build/platform/generic/firmware/fw_payload.bin: u-boot/u-boot-dtb.bin
	make -C opensbi FW_PAYLOAD_PATH=../u-boot/u-boot-dtb.bin

# --------------------------------------------------------------------
# u-boot stuff

# What are we targetting? This is the same file location for virt and
# visionfive2, so be sure to run `make clean` when trying to switch
# between targets.
u-boot/.config:
	make -C u-boot ${BOARD}_defconfig

# This is an image for the main uboot binary. It is loaded by qemu to
# provide the second stage bootloader (the prompt). The equivalent
# thing for visionfive2 is u-boot-dtb.bin that gets wrapped by opensbi
# as fw_payload and loaded into memory from a special partition by the
# first stage bootloader.
u-boot/u-boot.itb: opensbi/build/platform/generic/firmware/fw_dynamic.bin u-boot/.config
	cp $< -t u-boot/
	make -C u-boot
#for some reason uboot doesn't have a rule for u-boot.itb, but default makes it anyway?

# This is the primary u-boot image expressed as a binary. It is
# wrapped by opensbi and provides the uboot prompt and acts as the
# second stage bootloader.
u-boot/u-boot-dtb.bin: opensbi/build/platform/generic/firmware/fw_dynamic.bin u-boot/.config
	cp $< -t u-boot/
	make -C u-boot u-boot-dtb.bin
#This target exists for VF2, but not for virt?

# This is the the first stage bootloader expected by uboot. It is a
# wrapper of opensbi and provides other black box stuff for
# uboot. Just think about this as the first stage bootloader, and that
# everything after this is running atop opensbi.
u-boot/spl/u-boot-spl.bin: opensbi/build/platform/generic/firmware/fw_dynamic.bin u-boot/.config
	cp $< u-boot/
	make -C u-boot spl/u-boot-spl.bin

# --------------------------------------------------------------------
# kernel stuff

REEDOS_LOC := ./reedos
# This likely not what you really want, and is just a test. Dropping
# in your own binary for kernel/kernel should work, as should
# replacing this rule with something better
kernel/kernel: .FORCE
	make -C ${REEDOS_LOC} build
	cp -u ${REEDOS_LOC}/target/riscv64gc-unknown-none-elf/debug/kernel kernel/kernel.elf
	${CROSS_COMPILE}objcopy -O binary kernel/kernel.elf $@
.FORCE:

# --------------------------------------------------------------------
# make a FIT image for u-boot to launch, to be placed in the generic
# fs part of the filesystem.

# This is a image that contains a device tree binary for the
# visionfive2 board and the kernel we want to launch. See the .its
# file for details.
fit/visionfive2.itb: fit/visionfive2.its fit/visionfive2.dtb kernel/kernel
	cd fit ; \
	mkimage -f visionfive2.its visionfive2.itb

# --------------------------------------------------------------------
# filesystem stuff for the third partition on the disk

# What all might we want to look at from the uboot prompt? The most
# important thing here is the .itb, as that is what you can launch
# with bootm once it has been loaded into memory.
filesystem/root.img: fit/visionfive2.itb kernel/kernel fit/visionfive2.dtb
	mkdir -p filesystem
	mkdir -p filesystem/root
	dd if=/dev/zero of=filesystem/root.img bs=1 count=0 seek=${FS_SIZE}
	cp -t filesystem/root $^
	mke2fs -d filesystem/root \
		-L "SD Root" \
		-t ext2 \
		filesystem/root.img \
		${FS_SIZE}

# --------------------------------------------------------------------
# making a bootable disk image

# This is a $TOTAL_SIZE raw disk image that can be flashed onto the
# visionfive2 sd card to launch the whole nine yards. See `all` target
# for details on how to use this. You don't need this if you are
# launching virt.
sd.img: u-boot/spl/u-boot-spl.bin \
			opensbi/build/platform/generic/firmware/fw_payload.bin \
			filesystem/root.img
	dd if=/dev/zero of=sd.img bs=1 count=0 seek=${TOTAL_SIZE}
	sgdisk --clear	\
		--new=1:$(SPL_START):$(SPL_END) --change-name=1:"spl" --typecode=1:$(SPL) \
		--new=2:$(UBOOT_START):$(UBOOT_END) --change-name=2:"uboot" --typecode=2:$(UBOOT) \
		--new=3:$(EXT2_START):$(EXT2_END) --change-name=3:"file system" --typecode=3:8300 \
		sd.img
	dd if=u-boot/spl/u-boot-spl.bin of=sd.img obs=$(SECTOR_SIZE) seek=$(SPL_START) conv=notrunc
	dd if=opensbi/build/platform/generic/firmware/fw_payload.bin \
		of=sd.img obs=$(SECTOR_SIZE) seek=$(UBOOT_START) conv=notrunc
	dd if=filesystem/root.img of=sd.img obs=$(SECTOR_SIZE) \
		seek=$(EXT2_START) conv=notrunc
	sync;

# --------------------------------------------------------------------
# misc

# This just removes all the build artifacts and results. It should be
# run between making different targets, as it removes the u-boot
# config, which is a shared file location between targets.
clean:
	make -C opensbi clean
	make -C u-boot clean
	rm -f fit/visionfive2.itb \
		fit/virt.itb \
		filesystem/root.img \
		filesystem/root/* \
		sd.img \
		kernel/kernel \
		kernel/kernel.elf \
		u-boot/.config
