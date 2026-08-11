#!/bin/bash

set -exo pipefail

# Get an updated config.sub and config.guess
if [[ "${target_platform}" != "win-"* ]]; then
    cp ${BUILD_PREFIX}/share/gnuconfig/config.* build-aux/
fi

if [[ "${target_platform}" == "win-"* ]]; then
    # Keep Clang's __attribute__ support.
    sed -i \
      's/!defined(__GNUC__) && !defined(__attribute__)/!defined(__GNUC__) \&\& !defined(__clang__) \&\& !defined(__attribute__)/' \
      src/system.h

    # unistd.h is unavailable on Windows.
    sed -i '/^#include <unistd.h>$/i #ifdef HAVE_UNISTD_H' src/popt.c
    sed -i '/^#include <unistd.h>$/a #endif' src/popt.c

    # sys/ioctl.h is unavailable on Windows.
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
