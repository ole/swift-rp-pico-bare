# Typical macOS config (adjust paths for your system)
CLANG=/Applications/LLVMEmbeddedToolchainForArm-17.0.1-Darwin/bin/clang
OBJCOPY=/Applications/LLVMEmbeddedToolchainForArm-17.0.1-Darwin/bin/llvm-objcopy
SWIFTC=/Library/Developer/Toolchains/swift-DEVELOPMENT-SNAPSHOT-2024-01-04-a.xctoolchain/usr/bin/swiftc
PYTHON3=/usr/bin/python3

# Typical Linux config (adjust for your system)
# CLANG=/usr/bin/clang
# OBJCOPY=/usr/bin/objcopy
# SWIFTC=/usr/bin/swiftc
# PYTHON3=/usr/bin/python3

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

build/bs2_default_padded_checksummed.S.obj: build/bs2_default_padded_checksummed.S | build
	"${CLANG}" \
		--target=armv6m-none-eabi \
		-mfloat-abi=soft \
		-march=armv6m \
		-O3 \
		-DNDEBUG \
		-ffunction-sections \
		-fdata-sections \
		-c "$<" \
		-o "$@"

build/crt0.S.obj: pico-sdk-comps/crt0.S | build
	"${CLANG}" \
		--target=armv6m-none-eabi \
		-mfloat-abi=soft \
		-march=armv6m \
		-O3 \
		-DNDEBUG \
		-ffunction-sections \
		-fdata-sections \
		-c "$<" \
		-o "$@"

build/bootrom.c.obj: pico-sdk-comps/bootrom.c pico-sdk-comps/bootrom.h | build
	"${CLANG}" \
		--target=armv6m-none-eabi \
		-mfloat-abi=soft \
		-march=armv6m \
		-O3 \
		-DNDEBUG \
		-ffunction-sections \
		-fdata-sections \
		-MD \
		-MT "$@" \
		-MF "$@.d" \
		-c "$<" \
		-o "$@"

build/pico_int64_ops_aeabi.S.obj: pico-sdk-comps/pico_int64_ops_aeabi.S | build
	"${CLANG}" \
		--target=armv6m-none-eabi \
		-mfloat-abi=soft \
		-march=armv6m \
		-O3 \
		-DNDEBUG \
		-ffunction-sections \
		-fdata-sections \
		-c "$<" \
		-o "$@"

build/App.o: App.swift MMIOVolatile/module.modulemap MMIOVolatile/MMIOVolatile.h | build
	"${SWIFTC}" \
		-O \
		-wmo \
		-enable-experimental-feature Embedded \
		-target armv6m-none-none-eabi \
		-Xcc -mfloat-abi=soft \
		-Xcc -march=armv6m \
		-Xfrontend -function-sections \
		-I MMIOVolatile \
		-parse-as-library \
		-emit-object \
		"$<" \
		-o "$@"

build/SwiftPico.elf: build/bs2_default_padded_checksummed.S.obj build/crt0.S.obj build/bootrom.c.obj build/pico_int64_ops_aeabi.S.obj build/App.o | build
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
		-Xlinker --wrap=__aeabi_lmul \
		$^ \
		-o "$@"
