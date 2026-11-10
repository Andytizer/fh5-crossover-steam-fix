#!/bin/sh
# Build build/ws2_32.dll from src/ inside Docker (llvm-mingw cross compiler). Nothing is installed on the host.
# Override the image with IMAGE=mstorsjo/llvm-mingw:<tag> ./build.sh
set -eu
cd "$(dirname "$0")"
IMAGE="${IMAGE:-mstorsjo/llvm-mingw:latest}"
mkdir -p build
docker run --rm -v "$PWD":/w -w /w "$IMAGE" sh -c '
  x86_64-w64-mingw32-clang -O2 -fno-builtin -fno-stack-protector -Wall -Wno-unused-function -shared -nostdlib \
    -Wl,-e,DllMain -o build/ws2_32.dll src/ws2fix.c ws2_32.def -lkernel32 &&
  sha256sum build/ws2_32.dll && wc -c < build/ws2_32.dll
'
