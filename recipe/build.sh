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

    # Use the Windows CRT name for strdup.
    sed -i \
      's/^#define[[:space:]]*xstrdup(_str)[[:space:]]*strdup(_str)$/#define xstrdup(_str) _strdup(_str)/' \
      src/system.h

    # Include unistd.h only when it is available.
    for file in src/popt.c src/poptconfig.c; do
        sed -i '/^#include <unistd.h>$/i #ifdef HAVE_UNISTD_H' "$file"
        sed -i '/^#include <unistd.h>$/a #endif' "$file"
    done

    # Disable TIOCGWINSZ support on Windows to avoid including sys/ioctl.h.
    sed -i '/^#define[[:space:]]*POPT_USE_TIOCGWINSZ$/i #ifndef _WIN32' src/popthelp.c
    sed -i '/^#define[[:space:]]*POPT_USE_TIOCGWINSZ$/a #endif' src/popthelp.c

    # Use Windows CRT equivalents for POSIX process APIs.
    sed -i '/^#include <errno.h>$/a\
    #ifdef _WIN32\
    #include <io.h>\
    #include <process.h>\
    #define access _access\
    #define execvp _execvp\
    #define X_OK 0\
    #endif' src/popt.c

    # Skip Unix uid/gid checks on Windows.
    sed -i '/#elif defined (HAVE_SETREUID)/,/^#endif$/s/^[[:space:]]*#else$/#elif !defined(_WIN32)/' src/popt.c

    # Use Windows CRT equivalents for POSIX file APIs.
    sed -i '/^#include <errno.h>$/a\
    #ifdef _WIN32\
    #include <io.h>\
    #define open _open\
    #define lseek _lseek\
    #define read _read\
    #define close _close\
    #ifndef S_ISREG\
    #define S_ISREG(mode) (((mode) & _S_IFMT) == _S_IFREG)\
    #endif\
    #ifndef S_IXUSR\
    #define S_IXUSR _S_IEXEC\
    #define S_IXGRP 0\
    #define S_IXOTH 0\
    #endif\
    #endif' src/poptconfig.c

    # _read returns int on Windows.
    sed -i \
      's/read(fdno, (char \*)b, (size_t)nb) != (ssize_t)nb/read(fdno, (char *)b, (unsigned int)nb) != (int)nb/' \
      src/poptconfig.c

    # Mark exported global data as dllimport when consuming the DLL.
    sed -i '/^#include <stdio.h>/a\
    #if defined(_WIN32) && !defined(DLL_EXPORT)\
    #define POPT_DATA __declspec(dllimport)\
    #else\
    #define POPT_DATA\
    #endif' src/popt.h
    
    sed -i \
      -e 's/^extern struct poptOption poptAliasOptions\[\];$/POPT_DATA extern struct poptOption poptAliasOptions[];/' \
      -e 's/^extern struct poptOption poptHelpOptions\[\];$/POPT_DATA extern struct poptOption poptHelpOptions[];/' \
      -e 's/^extern struct poptOption \* poptHelpOptionsI18N;$/POPT_DATA extern struct poptOption * poptHelpOptionsI18N;/' \
      -e 's/^extern unsigned int _poptBitsN;$/POPT_DATA extern unsigned int _poptBitsN;/' \
      -e 's/^extern  unsigned int _poptBitsM;$/POPT_DATA extern unsigned int _poptBitsM;/' \
      -e 's/^extern  unsigned int _poptBitsK;$/POPT_DATA extern unsigned int _poptBitsK;/' \
      src/popt.h
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
