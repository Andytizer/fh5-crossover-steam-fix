#!/bin/sh
# Build build/d3d12.dll from src/ inside Docker (llvm-mingw cross compiler). Nothing is installed on the host.
# Override the image with IMAGE=mstorsjo/llvm-mingw:<tag> ./build.sh
set -eu
cd "$(dirname "$0")"
IMAGE="${IMAGE:-mstorsjo/llvm-mingw:latest}"
mkdir -p build
docker run --rm -v "$PWD":/w -w /w/src "$IMAGE" sh -c '
  x86_64-w64-mingw32-clang -shared -O2 -Wall -static-libgcc -o ../build/d3d12.dll d3d12.c dxil_shadingrate.c inspect.c d3d12.def &&
  cd ../build && sha256sum d3d12.dll && wc -c < d3d12.dll &&
  x86_64-w64-mingw32-objdump -p d3d12.dll | sed -n "/Export Table/,/^$/p;/\\[Ordinal\\/Name Pointer\\] Table/,/^$/p"
'
# No "Wine builtin DLL" stamp: the DLL is used as a native override from the game folder (DLLOVERRIDES=d3d12=n).
# tools/pe_tools.py mark-builtin is only needed if you put it in a Wine builtin directory instead.
