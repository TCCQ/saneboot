#general options
CROSS_COMPILE := riscv64-linux-gnu-
export CROSS_COMPILE
MAKEFLAGS := -j$(nproc)
export MAKEFLAGS


# opensbi options
PLATFORM := generic
export PLATFORM

# u-boot options
BOARD := sifive_unleashed

# sd image options
TOTAL_SIZE = 4G
FS_SIZE = 2G
SPL_START   = 4096
SPL_END = 8191
UBOOT_START = 8192
UBOOT_END = 16383
UBOOT_SIZE = $(shell expr $(UBOOT_END) - $(UBOOT_START) + 1)
VFAT_START = 16384
VFAT_END = 614399
VFAT_SIZE = $(shell expr $(VFAT_END) - $(VFAT_START) + 1)
ROOT_START = 614400

# Relevant partition type codes with GUID
SPL = 2E54B353-1271-4842-806F-E436D6AF6985
VFAT = EBD0A0A2-B9E5-4433-87C0-68B6B72699C7
LINUX = 0FC63DAF-8483-4772-8E79-3D69D8477DE4
UBOOT = 5B193300-FC78-40CD-8002-E86C45580B47
UBOOTENV = a09354ac-cd63-11e8-9aff-70b3d592f0fa
UBOOTDTB = 070dd1a8-cd64-11e8-aa3d-70b3d592f0fa
UBOOTFIT = 04ffcafa-cd65-11e8-b974-70b3d592f0fa

# --------------------------------------------------------------------
# defaults
all: 
	@echo 'You probably want to flash an image with `make format-boot-loader /dev/{something}`. Consider making a loop device to ensure things get written properly.'

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

u-boot/u-boot-dtb.bin: opensbi/build/platform/generic/firmware/fw_dynamic.bin u-boot/.config
	cp $< -t u-boot/
	make -C u-boot u-boot-dtb.bin

u-boot/spl/u-boot-spl.bin: u-boot/.config
	make -C u-boot spl/u-boot-spl.bin

# --------------------------------------------------------------------
# kernel stuff

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

fit/simple.itb: fit/simple_fdt_kernel.its fit/target.dtb kernel/kernel
	cd fit; \
	mkimage -f simple_fdt_kernel.its simple.itb

# --------------------------------------------------------------------
# filesystem stuff for the third partition on the disk

filesystem/root.img: fit/simple.itb kernel/kernel fit/target.dtb
	dd if=/dev/zero of=filesystem/root.img bs=1 count=0 seek=${FS_SIZE}
	cp -t filesystem/root $^
	mke2fs -d filesystem/root \
		-L "SD Root" \
		-t ext2 \
		filesystem/root.img \
		${FS_SIZE}

# --------------------------------------------------------------------
# making a bootable disk image

format-boot-loader: u-boot/spl/u-boot-spl.bin \
			opensbi/build/platform/generic/firmware/fw_payload.bin \
			filesystem/root.img

	@test -b $(DISK) || (echo "$(DISK): is not a block device"; exit 1)
	sudo sgdisk --clear  \
	--new=1:$(SPL_START):$(SPL_END) --change-name=1:"spl" --typecode=1:$(SPL) \
	--new=2:$(UBOOT_START):$(UBOOT_END) --change-name=2:"uboot" --typecode=2:$(UBOOT) \
	--new=3:0:+${FS_SIZE} --change-name=3:"file system" --typecode=3:8300 \
	$(DISK)
ifeq ($(DISK)p1,$(wildcard $(DISK)p1))
	@$(eval PART1 := $(DISK)p1)
	@$(eval PART2 := $(DISK)p2)
	@$(eval PART3 := $(DISK)p3)
# @$(eval PART4 := $(DISK)p4)
else ifeq ($(DISK)s1,$(wildcard $(DISK)s1))
	@$(eval PART1 := $(DISK)s1)
	@$(eval PART2 := $(DISK)s2)
	@$(eval PART3 := $(DISK)s3)
# @$(eval PART4 := $(DISK)s4)
else ifeq ($(DISK)1,$(wildcard $(DISK)1))
	@$(eval PART1 := $(DISK)1)
	@$(eval PART2 := $(DISK)2)
	@$(eval PART3 := $(DISK)3)
# @$(eval PART4 := $(DISK)4)
else
	@echo Error: Could not find bootloader partition for $(DISK)
	@exit 1
endif
	sudo dd if=u-boot/spl/u-boot-spl.bin of=$(PART1) bs=4096
	sudo dd if=opensbi/build/platform/generic/firmware/fw_payload.bin of=$(PART2) bs=4096
	sudo dd if=filesystem/root.img of=$(PART3) bs=4096
	sync;

# --------------------------------------------------------------------
# misc

clean:
	make -C opensbi clean
	make -C u-boot clean
	rm -f sd.img \
		fit/simple.itb \
		filesystem/root.img \
		filesystem/root/* \
		kernel/kernel \
		kernel/simple.elf
