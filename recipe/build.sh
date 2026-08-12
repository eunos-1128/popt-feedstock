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
    sed -i \
      '/#elif defined (HAVE_SETREUID)/,/^#endif$/s/^[[:space:]]*#else$/#elif !defined(_WIN32)/' \
      src/popt.c

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

    #
    # Windows shared-DLL support.
    #

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

    # Add a special include-table type whose arg points to a function
    # returning the actual option table.
    sed -i \
      '/^#define[[:space:]]*POPT_ARG_BITSET/a\
#define POPT_ARG_INCLUDE_TABLE_FUNC 15U /*!< arg points to function returning table */' \
      src/popt.h

    # Declare the accessor functions inside the public C API section.
    # These are referenced by POPT_AUTOHELP/POPT_AUTOALIAS on Windows.
    sed -i '/^poptContext poptFreeContext/i\
#ifdef _WIN32\
const struct poptOption * poptGetAliasOptions(void);\
const struct poptOption * poptGetHelpOptions(void);\
#endif\
' src/popt.h

    # On Windows, avoid using dllimport data addresses in static
    # initializers. Store accessor function addresses instead.
    #
    # Use (char)0 rather than '\''\0'\'' here to keep the sed expression
    # straightforward; the value is equivalent for shortName.
    sed -i '/^#define POPT_AUTOALIAS /,+1c\
#ifdef _WIN32\
#define POPT_AUTOALIAS { NULL, (char)0, POPT_ARG_INCLUDE_TABLE_FUNC, (void *)poptGetAliasOptions, 0, "Options implemented via popt alias/exec:", NULL },\
#else\
#define POPT_AUTOALIAS { NULL, (char)0, POPT_ARG_INCLUDE_TABLE, poptAliasOptions, 0, "Options implemented via popt alias/exec:", NULL },\
#endif' src/popt.h

    sed -i '/^#define POPT_AUTOHELP /,+1c\
#ifdef _WIN32\
#define POPT_AUTOHELP { NULL, (char)0, POPT_ARG_INCLUDE_TABLE_FUNC, (void *)poptGetHelpOptions, 0, "Help options:", NULL },\
#else\
#define POPT_AUTOHELP { NULL, (char)0, POPT_ARG_INCLUDE_TABLE, poptHelpOptions, 0, "Help options:", NULL },\
#endif' src/popt.h

    # Implement the accessor functions inside the DLL.
    sed -i '/^struct poptOption \* poptHelpOptionsI18N = poptHelpOptions2;$/a\
\
#ifdef _WIN32\
const struct poptOption * poptGetAliasOptions(void)\
{\
    return poptAliasOptions;\
}\
\
const struct poptOption * poptGetHelpOptions(void)\
{\
    return poptHelpOptionsI18N;\
}\
#endif' src/popthelp.c

    #
    # Teach popt.c to resolve POPT_ARG_INCLUDE_TABLE_FUNC.
    #

    # Resolve function-backed option tables into arg.opt.
    sed -i '/poptArg arg = { \.ptr = opt->arg };/a\
#ifdef _WIN32\
        if (poptArgType(opt) == POPT_ARG_INCLUDE_TABLE_FUNC && opt->arg != NULL) {\
            const struct poptOption *(*getTable)(void) =\
                (const struct poptOption *(*)(void))opt->arg;\
            arg.opt = getTable();\
        }\
#endif' src/popt.c

    # Treat function-backed include tables like normal included tables.
    sed -i \
      's/^\([[:space:]]*\)case POPT_ARG_INCLUDE_TABLE:/\1case POPT_ARG_INCLUDE_TABLE_FUNC:\n\1case POPT_ARG_INCLUDE_TABLE:/' \
      src/popt.c

    # One callback traversal uses opt->arg directly rather than arg.opt.
    # Use the already-resolved table instead.
    sed -i \
      's/if (opt->arg != NULL)$/if (arg.opt != NULL)/' \
      src/popt.c

    sed -i \
      's/invokeCallbacksOPTION(con, opt->arg,/invokeCallbacksOPTION(con, arg.opt,/' \
      src/popt.c

    #
    # Teach popthelp.c to resolve POPT_ARG_INCLUDE_TABLE_FUNC.
    #

    sed -i '/poptArg arg = { \.ptr = opt->arg };/a\
#ifdef _WIN32\
        if (poptArgType(opt) == POPT_ARG_INCLUDE_TABLE_FUNC && opt->arg != NULL) {\
            const struct poptOption *(*getTable)(void) =\
                (const struct poptOption *(*)(void))opt->arg;\
            arg.opt = getTable();\
        }\
#endif' src/popthelp.c

    sed -i \
      's/^\([[:space:]]*\)case POPT_ARG_INCLUDE_TABLE:/\1case POPT_ARG_INCLUDE_TABLE_FUNC:\n\1case POPT_ARG_INCLUDE_TABLE:/' \
      src/popthelp.c

    # maxArgWidth() uses a plain void * rather than poptArg.
    sed -i '/void \* arg = opt->arg;/a\
#ifdef _WIN32\
        if (poptArgType(opt) == POPT_ARG_INCLUDE_TABLE_FUNC && opt->arg != NULL) {\
            const struct poptOption *(*getTable)(void) =\
                (const struct poptOption *(*)(void))opt->arg;\
            arg = (void *)getTable();\
        }\
#endif' src/popthelp.c

    #
    # Diagnostics: make the generated source visible in CI while
    # prototyping this as sed before converting it to a patch.
    #
    echo "=== POPT_AUTO* definitions ==="
    grep -n -A8 -B3 'POPT_AUTOALIAS\|POPT_AUTOHELP' src/popt.h

    echo "=== include-table handling ==="
    grep -n -A10 -B5 'POPT_ARG_INCLUDE_TABLE' src/popt.c || true
    grep -n -A10 -B5 'POPT_ARG_INCLUDE_TABLE' src/popthelp.c || true

    echo "=== Windows DLL declarations ==="
    grep -n \
      'POPT_DATA\|poptGetAliasOptions\|poptGetHelpOptions' \
      src/popt.h src/popthelp.c || true
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
