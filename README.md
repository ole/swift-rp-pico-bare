# ”Bare bare metal” Embedded Swift on the RP2040 (Raspberry Pi Pico)

Build a Swift executable for the Raspberry Pi Pico without the Pico C SDK. Tested on macOS 14 and Linux (Ubuntu 22.04).

Swift forum discussion thread: <https://forums.swift.org/t/embedded-swift-on-the-raspberry-pi-pico-rp2040-without-the-pico-sdk/69338>

## Installation

### On macOS

1. Download and install a current [nightly Swift toolchain](https://www.swift.org/download/#snapshots) ("Trunk Development (main)"). Tested with 2024-02-15, newer versions will probably work too. The download is a `.pkg` installer that will install the toolchain into `/Library/Developer/Toolchains` or `~/Library/Developer/Toolchains`. 

2. Install LLVM using Homebrew:

    ```sh
    brew install llvm
    ```

    Note: This is necessary even though Xcode already comes with LLVM. We need (a) a linker that can produce `.elf` files, and (b) the tool `llvm-objcopy`. Xcode currently doesn’t provide these. Don’t worry, installing LLVM from Homebrew, won’t mess up your Xcode setup; Homebrew won’t place these tools into your `PATH`.

3. Put the `ld.lld` executable (this is the linker from LLVM you just installed) in your `PATH`. SwiftPM will be looking for this program and it needs to be able to find it. I have a `~/bin` directory that's already in my `PATH`, so I put a symlink to `ld.lld` in that folder:

    ```sh
    ln -s /opt/homebrew/opt/llvm/bin/ld.lld ~/bin/ld.lld
    ```

    (If you’re on an Intel Mac, the path to your Homebrew may vary.)
    
    Alternatively, you could put this symlink in `/usr/local/bin` or some other directory in your `PATH`. Note: I advise against putting the `llvm/bin` directory itself in your `PATH` as Xcode and other build tools might get confused which one to use, but I haven’t tested this.

5. Install [`elf2uf2-rs`](https://crates.io/crates/elf2uf2-rs) and [`probe-rs`](https://probe.rs/) (requires a working Rust installation; see <https://www.rust-lang.org/tools/install> for guidance):

      ```sh
      cargo install elf2uf2-rs --locked
      cargo install probe-rs --features cli
      ```

      We’ll use these tools to create the UF2 file for the Pico and/or flash the ELF file to the Pico. If you have other tools to do these jobs, feel free to use them. These are not required for the actual build process.

### On Linux

1. Install a current [nightly Swift toolchain](https://www.swift.org/download/#snapshots) ("Trunk Development (main)"). You can probably use [swiftly](https://swift-server.github.io/swiftly/) or [swiftenv](https://swiftenv.fuller.li/), or use one of the official Swift Docker images (I tested with `swiftlang/swift:nightly-jammy`).

2. Install the `objcopy` tool if you don't have it already. You probably already have this installed, type `objcopy --version` to verify. If not, install it with your distribution's package manager.

    We use `objcopy` in one of the build steps for the second-stage bootloader to convert a linked `.elf` file into the raw binary machine code representation (to compute the checksum for the bootloader).

3. Install [`elf2uf2-rs`](https://crates.io/crates/elf2uf2-rs) and [`probe-rs`](https://probe.rs/) (requires a working Rust installation; see <https://www.rust-lang.org/tools/install> for guidance):

      ```sh
      cargo install elf2uf2-rs --locked
      cargo install probe-rs --features cli
      ```

      We’ll use these tools to create the UF2 file for the Pico and/or flash the ELF file to the Pico. If you have other tools to do these jobs, feel free to use them. These are not required for the actual build process.

## Building

The normal SwiftPM commands `swift build` and `swift run` won’t work. You need to call `swift package link` with the correct arguments (see below) to build. This will use our custom SwiftPM command plugin for building and linking.

### On macOS

```sh
# Build and link final executable App.elf
swift package --triple armv6m-none-none-eabi \
    --toolchain /Library/Developer/Toolchains/swift-latest.xctoolchain/ \
    link \
    --objcopy /opt/homebrew/opt/llvm/bin/llvm-objcopy
```

Adjust the path to the Swift toolchain you downloaded accordingly. It should be either `/Library/Developer/…` or `~/Library/Developer/…`. Note that we’re passing in the path to `llvm-objcopy` from the Homebrew LLVM install.

Note: as of 2024-02-22, the macOS build produces dozens of warnings of the type "Class xyz is implemented in both \[path to toolchain\] and \[path to Xcode\]. One of the two will be used. Which one is undefined." I don't understand why these messages appear, but they don’t seem to be a problem.

### On Linux

```sh
# Build and link final executable App.elf
swift package --triple armv6m-none-none-eabi link
```

## Flashing the executable to the Raspberry Pi Pico

The build will produce an RP2040 executable in `.build/plugins/Link/outputs/App.elf`.

If you have a [Raspberry Pi Debug Probe](https://www.raspberrypi.com/documentation/microcontrollers/debug-probe.html) or a second Pico that you can use as a debug probe, use `probe-rs` to flash it to the Pico:

```sh
probe-rs run --chip RP2040 .build/plugins/Link/outputs/App.elf
```

Note: If `probe-rs` shows an error of the form "ERROR probe_rs::cmd::run: Failed to attach to RTT continuing..." after it says "Finished", you can ignore it. Use Ctrl+C to exit probe-rs.

Alternatively, use `elf2uf2-rs` to create a UF2 file which you can then copy to the Pico in BOOTSEL mode:

```sh
# Creates .build/plugins/Link/outputs/App.elf
elf2uf2-rs .build/plugins/Link/outputs/App.elf
```

You should see the Pico’s onboard LED blinking.

Note: If the LED is blinking very fast (to the point where it appears to be permanently on), try disconnecting and reconnecting the Pico from power. After reconnecting, you should observe the blinking to be approximately 20× slower. This is caused by a bug in our after-boot init code. See [issue 7](https://github.com/ole/swift-rp-pico-bare/issues/7) for details.
