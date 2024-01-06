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
RUN apt -y install python3 make wget

# Install ARM Embedded LLVM toolchain
WORKDIR /usr/local
RUN wget https://github.com/ARM-software/LLVM-embedded-toolchain-for-Arm/releases/download/release-17.0.1/LLVMEmbeddedToolchainForArm-17.0.1-Linux-AArch64.tar.xz
RUN tar -xf LLVMEmbeddedToolchainForArm-17.0.1-Linux-AArch64.tar.xz
RUN rm LLVMEmbeddedToolchainForArm-17.0.1-Linux-AArch64.tar.xz

WORKDIR /
