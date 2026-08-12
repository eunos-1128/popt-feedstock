#include <stdio.h>
#include <popt.h>

static int flag = 0;

static struct poptOption options[] = {
    {
        "flag",
        'f',
        POPT_ARG_NONE,
        &flag,
        0,
        "Set test flag",
        NULL
    },

    POPT_AUTOALIAS
    POPT_AUTOHELP
    POPT_TABLEEND
};

int main(void)
{
    const char *argv[] = {
        "test_popt",
        "--flag",
        NULL
    };

    poptContext con;
    int rc;

    /*
     * Verify imported DLL data.
     */
    _poptBitsN = 256;
    _poptBitsM = 128;
    _poptBitsK = 2;

    if (_poptBitsN != 256 ||
        _poptBitsM != 128 ||
        _poptBitsK != 2) {
        fprintf(stderr, "DLL data import test failed\n");
        return 1;
    }

    /*
     * Verify normal API calls through the import library.
     */
    con = poptGetContext("test_popt", 2, argv, options, 0);

    if (con == NULL) {
        fprintf(stderr, "poptGetContext failed\n");
        return 2;
    }

    while ((rc = poptGetNextOpt(con)) >= 0)
        ;

    if (rc != -1) {
        fprintf(stderr, "poptGetNextOpt failed: %d\n", rc);
        poptFreeContext(con);
        return 3;
    }

    if (!flag) {
        fprintf(stderr, "option parsing failed\n");
        poptFreeContext(con);
        return 4;
    }

    /*
     * Exercise POPT_AUTOHELP / POPT_AUTOALIAS traversal.
     */
    poptPrintHelp(con, stdout, 0);

    poptFreeContext(con);

    puts("popt MSVC consumer test passed");
    return 0;
}
