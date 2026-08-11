#!/bin/bash

set -exo pipefail

# Get an updated config.sub and config.guess
if [[ "${target_platform}" != "win-"* ]]; then
    cp ${BUILD_PREFIX}/share/gnuconfig/config.* build-aux/
fi

if [[ "${target_platform}" == "win-"* ]]; then
    # Prevent popt from redefining Clang's __attribute__ macro.
    sed -i \
      's/!defined(__GNUC__) && !defined(__attribute__)/!defined(__GNUC__) \&\& !defined(__clang__) \&\& !defined(__attribute__)/' \
      src/system.h

    # Include unistd.h only when it is available.
    for file in src/popt.c src/poptconfig.c; do
        sed -i '/^#include <unistd.h>$/i #ifdef HAVE_UNISTD_H' "$file"
        sed -i '/^#include <unistd.h>$/a #endif' "$file"
    done

    # Disable TIOCGWINSZ support on Windows to avoid including sys/ioctl.h.
    sed -i '/^#define[[:space:]]*POPT_USE_TIOCGWINSZ$/i #ifndef _WIN32' src/popthelp.c
    sed -i '/^#define[[:space:]]*POPT_USE_TIOCGWINSZ$/a #endif' src/popthelp.c
fi

./configure --prefix=${PREFIX} --disable-debug --disable-dependency-tracking --disable-static

if [[ "${target_platform}" == "win-"* ]]; then
    patch_libtool
fi

make -j${CPU_COUNT}

if [[ "${CONDA_BUILD_CROSS_COMPILATION:-}" != "1" || "${CROSSCOMPILING_EMULATOR}" != "" ]]; then
  make check
fi

make install
