#include <security/pam_appl.h>
#include <security/pam_ext.h>
#include <security/pam_modules.h>
#include <string.h>

/* Test-only password verifier, installed inside the mount namespace. */
PAM_EXTERN int pam_sm_authenticate(pam_handle_t *handle, int flags,
                                   int argc, const char **argv) {
    const char *password = NULL;
    (void)flags;
    (void)argc;
    (void)argv;

    int result = pam_get_authtok(handle, PAM_AUTHTOK, &password, "Password:");
    if (result != PAM_SUCCESS)
        return result;
    return password != NULL && strcmp(password, "test-password") == 0
        ? PAM_SUCCESS : PAM_AUTH_ERR;
}

PAM_EXTERN int pam_sm_setcred(pam_handle_t *handle, int flags,
                              int argc, const char **argv) {
    (void)handle;
    (void)flags;
    (void)argc;
    (void)argv;
    return PAM_SUCCESS;
}
