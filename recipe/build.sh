#!/bin/bash

set -exo pipefail

# The Windows gettext-tools package contains a non-relocatable autopoint
# script whose gettext data path points to its original build environment.
# Override gettext_datadir so autopoint can find archive.git.tar.gz in the
# current conda build prefix.
if [[ "${target_platform}" == win-* ]]; then
    export gettext_datadir="$(cygpath -u "${BUILD_PREFIX}")/Library/share/gettext"
    test -f "${gettext_datadir}/archive.git.tar.gz"
fi

./autogen.sh

# Get an updated config.sub and config.guess
cp ${BUILD_PREFIX}/share/gnuconfig/config.* build-aux/

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
