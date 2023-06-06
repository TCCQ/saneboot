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

opensbi/build/platform/generic/firmware/fw_dynamic.bin:
	make -C opensbi

u-boot/.config:
	make -C u-boot ${BOARD}_defconfig

u-boot/u-boot-dtb.bin: opensbi/build/platform/generic/firmware/fw_dynamic.bin u-boot/.config
	cp $< -t u-boot/
	make -C u-boot u-boot-dtb.bin

opensbi/build/platform/generic/firmware/fw_payload.bin: u-boot/u-boot-dtb.bin
	make -C opensbi FW_PAYLOAD_PATH=../u-boot/u-boot-dtb.bin

kernel/kernel: kernel/src/main.rs
	cd kernel
	cargo build --target riscv64imac-unknown-none-elf
	cd ..

u-boot/spl/u-boot-spl.bin: u-boot/.config
	make -C u-boot spl/u-boot-spl.bin

format-boot-loader: u-boot/spl/u-boot-spl.bin \
			opensbi/build/platform/generic/firmware/fw_payload.bin

	@test -b $(DISK) || (echo "$(DISK): is not a block device"; exit 1)
	sudo /sbin/sgdisk --clear  \
	--new=1:$(SPL_START):$(SPL_END) --change-name=1:"spl" --typecode=1:$(SPL)\
	--new=2:$(UBOOT_START):$(UBOOT_END) --change-name=2:"uboot" --typecode=2:$(UBOOT)\
	$(DISK)
ifeq ($(DISK)p1,$(wildcard $(DISK)p1))
	@$(eval PART1 := $(DISK)p1)
	@$(eval PART2 := $(DISK)p2)
	# @$(eval PART3 := $(DISK)p3)
	# @$(eval PART4 := $(DISK)p4)
else ifeq ($(DISK)s1,$(wildcard $(DISK)s1))
	@$(eval PART1 := $(DISK)s1)
	@$(eval PART2 := $(DISK)s2)
	# @$(eval PART3 := $(DISK)s3)
	# @$(eval PART4 := $(DISK)s4)
else ifeq ($(DISK)1,$(wildcard $(DISK)1))
	@$(eval PART1 := $(DISK)1)
	@$(eval PART2 := $(DISK)2)
	# @$(eval PART3 := $(DISK)3)
	# @$(eval PART4 := $(DISK)4)
else
	@echo Error: Could not find bootloader partition for $(DISK)
	@exit 1
endif
	sudo dd if=u-boot/spl/u-boot-spl.bin of=$(PART1) bs=4096
	sudo dd if=opensbi/build/platform/generic/firmware/fw_payload.bin of=$(PART2) bs=4096
	# sudo dd if=$(vfat_image) of=$(PART3) bs=4096
	sync;


clean:
	make -C opensbi clean
	make -C u-boot clean
	rm sd.img
