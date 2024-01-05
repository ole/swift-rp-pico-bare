Build a Swift executable for the Raspberry Pi Pico without the Pico C SDK.

## Build steps

```sh
/usr/local/LLVMEmbeddedToolchainForArm-14.0.0/bin/clang \
  --target=armv6m-none-eabi \
  -mfloat-abi=soft \
  -march=armv6m \
  --sysroot /usr/local/LLVMEmbeddedToolchainForArm-14.0.0/lib/clang-runtimes/armv6m_soft_nofp \
  -O3 \
  -DNDEBUG \
  -MD \
  -MT build/compile_time_choice.S.obj \
  -MF build/compile_time_choice.S.obj.d \
  -o build/compile_time_choice.S.obj   \
  -c pico-sdk-comps/compile_time_choice.S
  
/usr/local/LLVMEmbeddedToolchainForArm-14.0.0/bin/clang \
  --target=armv6m-none-eabi \
  -mfloat-abi=soft \
  -march=armv6m \
  --sysroot /usr/local/LLVMEmbeddedToolchainForArm-14.0.0/lib/clang-runtimes/armv6m_soft_nofp \
  -O3 \
  -DNDEBUG \
  -Wl,--build-id=none \
  -nostdlib \
  -Xlinker --script=pico-sdk-comps/boot_stage2.ld \
  build/compile_time_choice.S.obj \
  -o build/bs2_default.elf 
  
/usr/local/LLVMEmbeddedToolchainForArm-14.0.0/bin/llvm-objcopy \
  -Obinary build/bs2_default.elf \
  build/bs2_default.bin

/usr/bin/python3 pico-sdk-comps/pad_checksum \
  -s 0xffffffff \
  build/bs2_default.bin \
  build/bs2_default_padded_checksummed.S

/usr/local/LLVMEmbeddedToolchainForArm-14.0.0/bin/clang \
  --target=armv6m-none-eabi \
  -mfloat-abi=soft \
  -march=armv6m \
  --sysroot /usr/local/LLVMEmbeddedToolchainForArm-14.0.0/lib/clang-runtimes/armv6m_soft_nofp \
  -O3 \
  -DNDEBUG \
  -ffunction-sections \
  -fdata-sections \
  -o build/crt0.S.obj \
  -c pico-sdk-comps/crt0.S

/usr/local/LLVMEmbeddedToolchainForArm-14.0.0/bin/clang \
  --target=armv6m-none-eabi \
  -mfloat-abi=soft \
  -march=armv6m \
  --sysroot /usr/local/LLVMEmbeddedToolchainForArm-14.0.0/lib/clang-runtimes/armv6m_soft_nofp \
  -O3 \
  -DNDEBUG \
  -std=gnu11 \
  -ffunction-sections \
  -fdata-sections \
  -MD \
  -MT build/bootrom.c.obj \
  -MF build/bootrom.c.obj.d \
  -o build/bootrom.c.obj \
  -c pico-sdk-comps/bootrom.c

swiftc \
  -O -wmo \
  -enable-experimental-feature Embedded \
  -target armv6m-none-none-eabi \
   -Xfrontend -function-sections \
   -parse-as-library \
   -emit-object \
   -o build/main.o \
   main.swift

/usr/local/LLVMEmbeddedToolchainForArm-14.0.0/bin/clang \
  --target=armv6m-none-eabi \
  -mfloat-abi=soft \
  -march=armv6m \
  -nostdlib \
  -Wl,--build-id=none \
  -O3 \
  -Xlinker --script=pico-sdk-comps/memmap_default.ld \
  -Xlinker -z -Xlinker max-page-size=4096 \
  -Xlinker --gc-sections \
  build/bs2_default_padded_checksummed.S \
  build/crt0.S.obj \
  build/bootrom.c.obj \
  build/main.o \
  -o build/SwiftPico.elf
```
