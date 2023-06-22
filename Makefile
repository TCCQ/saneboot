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
BOARD := sifive_unleashed
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
# VFAT = EBD0A0A2-B9E5-4433-87C0-68B6B72699C7
# LINUX = 0FC63DAF-8483-4772-8E79-3D69D8477DE4
UBOOT = 5B193300-FC78-40CD-8002-E86C45580B47
# UBOOTENV = a09354ac-cd63-11e8-9aff-70b3d592f0fa
# UBOOTDTB = 070dd1a8-cd64-11e8-aa3d-70b3d592f0fa
# UBOOTFIT = 04ffcafa-cd65-11e8-b974-70b3d592f0fa

# --------------------------------------------------------------------
# defaults
all:
	@echo -e 'You can either make an sd image for a starfive visionfive2 board or you can run a test on the qemu virt machine. To do the former, read the makefile. To do the later run `make virt-run`. \n\nWhen switching between targets, run `make clean` to prevent use of the wrong config file for uboot.\n\nBoth targets should enable you to boot the binary image at /kernel/kernel in the saneboot source tree. With virt, `bootm 0x90000000` should launch it. With visionfive2, you will need to load it from the sdcard with `load mmc 1:3 _ simple.itb` and launch with `bootm _`, where `_` is an address of your choosing.'

fit/virt.itb:  fit/virt.its kernel/kernel
	cd fit ; \
	mkimage -f virt.its virt.itb

virt-run: BOARD := qemu-riscv64_spl
virt-run: fit/virt.itb opensbi/build/platform/generic/firmware/fw_dynamic.bin \
		u-boot/.config u-boot/spl/u-boot-spl.bin u-boot/u-boot.itb
	qemu-system-riscv64 -nographic -machine virt -m 4G -bios u-boot/spl/u-boot-spl.bin \
		-device loader,file=u-boot/u-boot.itb,addr=0x80200000 \
		-device loader,file=fit/virt.itb,addr=0x90000000

# --------------------------------------------------------------------
# opensbi stuff

opensbi/build/platform/generic/firmware/fw_dynamic.bin:
	make -C opensbi

opensbi/build/platform/generic/firmware/fw_payload.bin: u-boot/u-boot-dtb.bin
	make -C opensbi FW_PAYLOAD_PATH=../u-boot/u-boot-dtb.bin

# --------------------------------------------------------------------
# u-boot stuff

u-boot/.config:
	make -C u-boot ${BOARD}_defconfig

u-boot/u-boot.itb: opensbi/build/platform/generic/firmware/fw_dynamic.bin u-boot/.config
	cp $< -t u-boot/
	make -C u-boot 
#for some reason uboot doesn't have a rule for u-boot.itb, but default makes it anyway?

#This target exists for VF2, but not for virt?
u-boot/u-boot-dtb.bin: opensbi/build/platform/generic/firmware/fw_dynamic.bin u-boot/.config
	cp $< -t u-boot/
	make -C u-boot u-boot-dtb.bin

u-boot/spl/u-boot-spl.bin: opensbi/build/platform/generic/firmware/fw_dynamic.bin u-boot/.config 
	cp $< u-boot/
	make -C u-boot spl/u-boot-spl.bin

# --------------------------------------------------------------------
# kernel stuff

# This likely not what you really want, and is just a test. Dropping
# in your own binary for kernel/kernel should work, as should
# replacing this rule with something better
kernel/kernel: kernel/simple.S kernel/simple.ld
	cd kernel; \
	${CROSS_COMPILE}gcc -ffreestanding -nostdlib -no-pie -fno-pic \
		-Tsimple.ld -e entry \
		simple.S -o simple.elf; \
	${CROSS_COMPILE}objcopy -O binary simple.elf kernel; \
	cd ..

# --------------------------------------------------------------------
# make a FIT image for u-boot to launch, to be placed in the generic
# fs part of the filesystem

fit/visionfive2.itb: fit/visionfive2.its fit/visionfive2.dtb kernel/kernel
	cd fit ; \
	mkimage -f visionfive2.its visionfive2.itb


# --------------------------------------------------------------------
# filesystem stuff for the third partition on the disk

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

sd.img: u-boot/spl/u-boot-spl.bin \
			opensbi/build/platform/generic/firmware/fw_payload.bin \
			filesystem/root.img
	dd if=/dev/zero of=sd.img bs=1 count=0 seek=${TOTAL_SIZE}
	sgdisk --clear  \
		--new=1:$(SPL_START):$(SPL_END) --change-name=1:"spl" --typecode=1:$(SPL) \
		--new=2:$(UBOOT_START):$(UBOOT_END) --change-name=2:"uboot" --typecode=2:$(UBOOT) \
		--new=3:$(EXT2_START):$(EXT2_END) --change-name=3:"file system" --typecode=3:8300 \
		sd.img
	dd if=u-boot/spl/u-boot-spl.bin of=sd.img obs=$(SECTOR_SIZE) oseek=$(SPL_START) conv=notrunc
	dd if=opensbi/build/platform/generic/firmware/fw_payload.bin \
		of=sd.img obs=$(SECTOR_SIZE) oseek=$(UBOOT_START) conv=notrunc
	dd if=filesystem/root.img of=sd.img obs=$(SECTOR_SIZE) \
		oseek=$(EXT2_START) conv=notrunc
	sync;

# --------------------------------------------------------------------
# misc

clean:
	make -C opensbi clean
	make -C u-boot clean
	rm -f fit/visionfive2.itb \
		fit/virt.itb \
		filesystem/root.img \
		filesystem/root/* \
		sd.img \
		kernel/kernel \
		kernel/simple.elf
