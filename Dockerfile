# Docker image for building Embedded Swift programs on Linux
#
# Build this image:
#
#     docker build --tag ole/embedded-swift .
#
# Start a container and run make:
#
#     docker run --rm --privileged --interactive --tty --volume "$(pwd):/src" --workdir /src ole/embedded-swift
#     make

FROM swiftlang/swift:nightly-jammy

# Install dependencies
RUN apt -y update
RUN apt -y install gcc-arm-none-eabi libnewlib-arm-none-eabi libstdc++-arm-none-eabi-newlib ninja-build python3 python3-venv clang git make

# Build the ARM Embedded Clang toolchain from source.
# v14.0.0 is the newest version supported by the Raspberry Pi Pico C/C++ SDK.
# The prebuilt Linux binaries for v14.0.0 are x86_64 only so we can’t use those.
WORKDIR /root
RUN wget https://github.com/ARM-software/LLVM-embedded-toolchain-for-Arm/releases/download/release-14.0.0/LLVMEmbeddedToolchainForArm-14.0.0-src.tar.gz
RUN tar xvzf LLVMEmbeddedToolchainForArm-14.0.0-src.tar.gz
WORKDIR LLVMEmbeddedToolchainForArm-14.0.0-src
# Patch requirements.txt to use a newer PyYAML version.
# PyYAML-5.4.1 produces an error in ./setup.sh
RUN <<EOF patch --unified requirements.txt
@@ -1,5 +1,5 @@
 # Dependencies of build scripts
 gitdb==4.0.7
 GitPython==3.1.18
-PyYAML==5.4.1
+PyYAML==6.0.1
 smmap==4.0.0
EOF
# Run the build. This can take a long time.
RUN ./setup.sh
RUN . ./venv/bin/activate
RUN ./venv/bin/build.py --install-dir /usr/local

WORKDIR /
