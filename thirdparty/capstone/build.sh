#!/usr/bin/env bash
# Build the vendored multi-arch Capstone static lib (libcapstone.a).
# The .a (~41 MB) is gitignored; run this once after checkout to produce it.
# Requires: git, cmake, a C compiler (all on PATH via linuxbrew).
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
src="$(mktemp -d)"
git clone --depth 1 https://github.com/capstone-engine/capstone "$src"
cmake -S "$src" -B "$src/build" -DCMAKE_BUILD_TYPE=Release \
  -DCAPSTONE_BUILD_STATIC=ON -DCAPSTONE_BUILD_SHARED=OFF \
  -DCAPSTONE_BUILD_TESTS=OFF -DCAPSTONE_BUILD_CSTOOL=OFF \
  -DCAPSTONE_ARCHITECTURE_DEFAULT=ON -DCMAKE_POSITION_INDEPENDENT_CODE=ON
cmake --build "$src/build" -j
mkdir -p "$here/lib" "$here/include"
cp "$src/build/libcapstone.a" "$here/lib/"
cp -r "$src/include/capstone" "$here/include/"
echo "vendored libcapstone.a ($(du -h "$here/lib/libcapstone.a" | cut -f1)) — full multi-arch"
