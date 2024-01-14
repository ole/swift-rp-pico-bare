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
RUN apt -y install python3 make

WORKDIR /
