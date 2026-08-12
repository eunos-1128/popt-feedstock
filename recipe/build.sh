#!/bin/bash

set -exo pipefail

./autogen.sh

# Get an updated config.sub and config.guess
if [[ "${target_platform}" != "win-"* ]]; then
    cp ${BUILD_PREFIX}/share/gnuconfig/config.* build-aux/
fi

if [[ "${target_platform}" == "win-"* ]]; then
    # Use an unversioned DLL name on Windows.
    sed -i 's/-version-info 0:2:0/-avoid-version/' src/Makefile.in
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
