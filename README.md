# ”Bare bare metal” Embedded Swift on the RP2040 (Raspberry Pi Pico)

Build a Swift executable for the Raspberry Pi Pico without the Pico C SDK. Tested on macOS (13 and 14) and Linux (Ubuntu 22.04).

## Installation

1. If you're on macOS, download and install the [ARM Embedded LLVM Toolchain](https://github.com/ARM-software/LLVM-embedded-toolchain-for-Arm/releases/). Tested with v17.0.1, newer versions will probably work too. This isn’t necessary on Linux.

2. Download and install a current [nightly Swift toolchain](https://www.swift.org/download/#snapshots) ("Trunk Development (main)"). Tested with 2024-01-04, newer versions will probably work too.

3. Install Python 3 if you don’t have it.

4. Install [`elf2uf2-rs`](https://crates.io/crates/elf2uf2-rs) and [`probe-rs`](https://probe.rs/) (requires a working Rust installation):

      ```sh
      cargo install elf2uf2-rs --locked
      cargo install probe-rs --features cli
      ```

      We’ll use these tools to create the UF2 file for the Pico and/or flash the ELF file to the Pico.
  
5. Edit `Makefile` to specify the paths to `clang`, `llvm-objcopy`, and `swiftc`. These must point to the toolchains you just installed.

## Building

Running `make` will build the `build/SwiftPico.elf` executable:

```sh
# Creates build/SwiftPico.elf
make
```

If you have a [Raspberry Pi Debug Probe](https://www.raspberrypi.com/documentation/microcontrollers/debug-probe.html) or a second Pico that you can use as a debug probe, use `probe-rs` to flash it to the Pico:

```sh
probe-rs run --chip RP2040 build/SwiftPico.elf
```

Alternatively, use `elf2uf2-rs` to create a UF2 file which you can copy to the Pico in BOOTSEL mode:

```sh
# Creates build/SwiftPico.uf2
elf2uf2-rs build/SwiftPico.elf
```
