CLANG=/usr/local/LLVMEmbeddedToolchainForArm-14.0.0/bin/clang
SYSROOT=/usr/local/LLVMEmbeddedToolchainForArm-14.0.0/lib/clang-runtimes/armv6m_soft_nofp
OBJCOPY=arm-none-eabi-objcopy
PYTHON3=/usr/bin/python3
SWIFTC=/usr/bin/swiftc

.PHONY: all clean

all: build/SwiftPico.elf

clean:
	rm -rf build

build:
	mkdir build

build/compile_time_choice.S.obj: pico-sdk-comps/compile_time_choice.S | build
	"${CLANG}" \
		--target=armv6m-none-eabi \
		-mfloat-abi=soft \
		-march=armv6m \
		--sysroot "${SYSROOT}" \
		-O3 \
		-DNDEBUG \
		-MD \
		-MT "$@" \
		-MF "$@.d" \
		-c "$<" \
		-o "$@"

build/bs2_default.elf: build/compile_time_choice.S.obj | build
	"${CLANG}" \
		--target=armv6m-none-eabi \
		-mfloat-abi=soft \
		-march=armv6m \
		--sysroot "${SYSROOT}" \
		-O3 \
		-DNDEBUG \
		-Wl,--build-id=none \
		-nostdlib \
		-Xlinker --script=pico-sdk-comps/boot_stage2.ld \
		"$<" \
		-o "$@"

build/bs2_default.bin: build/bs2_default.elf | build
	"${OBJCOPY}" \
  	-Obinary "$<" \
  	"$@"

build/bs2_default_padded_checksummed.S: build/bs2_default.bin | build
	"${PYTHON3}" pico-sdk-comps/pad_checksum \
		-s 0xffffffff \
		"$<" \
		"$@"

build/crt0.S.obj: pico-sdk-comps/crt0.S | build
	"${CLANG}" \
		--target=armv6m-none-eabi \
		-mfloat-abi=soft \
		-march=armv6m \
		--sysroot "${SYSROOT}" \
		-O3 \
		-DNDEBUG \
		-ffunction-sections \
		-fdata-sections \
		-c "$<" \
		-o "$@"

build/bootrom.c.obj: pico-sdk-comps/bootrom.c | build
	"${CLANG}" \
		--target=armv6m-none-eabi \
		-mfloat-abi=soft \
		-march=armv6m \
		--sysroot "${SYSROOT}" \
		-O3 \
		-DNDEBUG \
		-ffunction-sections \
		-fdata-sections \
		-MD \
		-MT "$@" \
		-MF "$@.d" \
		-c "$<" \
		-o "$@"

build/main.o: main.swift | build
	"${SWIFTC}" \
		-O -wmo \
		-enable-experimental-feature Embedded \
		-target armv6m-none-none-eabi \
		-Xfrontend -function-sections \
		-parse-as-library \
		-emit-object \
		"$<" \
		-o "$@"

build/SwiftPico.elf: build/bs2_default_padded_checksummed.S build/crt0.S.obj build/bootrom.c.obj build/main.o | build
	"${CLANG}" \
		--target=armv6m-none-eabi \
		-mfloat-abi=soft \
		-march=armv6m \
		-nostdlib \
		-Wl,--build-id=none \
		-O3 \
		-Xlinker --script=pico-sdk-comps/memmap_default.ld \
		-Xlinker -z -Xlinker max-page-size=4096 \
		-Xlinker --gc-sections \
		$^ \
		-o "$@"