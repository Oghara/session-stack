#include <security/pam_appl.h>
#include <security/pam_ext.h>
#include <security/pam_modules.h>

#include <errno.h>
#include <signal.h>
#include <stdlib.h>
#include <string.h>
#include <sys/prctl.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>

#define BIOMETRIC_HELPER \
    "/usr/local/lib/session-stack-greeter/authenticate-biometric"
#define FACE_SELECTOR "session-stack-greeter:face:v1"
#define FINGERPRINT_SELECTOR "session-stack-greeter:fingerprint:v1"
#define PASSWORD_SELECTOR "session-stack-greeter:password:v1"

static int run_biometric_helper(const char *selector, const char *user) {
    pid_t child = fork();
    int status;

    if (child < 0)
        return PAM_SYSTEM_ERR;
    if (child == 0) {
        pid_t parent = getppid();

        if (prctl(PR_SET_PDEATHSIG, SIGTERM) != 0 || getppid() != parent)
            _exit(1);
        execl(BIOMETRIC_HELPER, BIOMETRIC_HELPER, selector, user,
              (char *)NULL);
        _exit(1);
    }

    while (waitpid(child, &status, 0) < 0) {
        if (errno != EINTR)
            return PAM_SYSTEM_ERR;
    }
    if (WIFEXITED(status) && WEXITSTATUS(status) == 0)
        return PAM_SUCCESS;
    return PAM_IGNORE;
}

PAM_EXTERN int pam_sm_authenticate(pam_handle_t *handle, int flags,
                                   int argc, const char **argv) {
    const char *user = NULL;
    int result;

    (void)flags;
    (void)argc;
    (void)argv;

    result = pam_get_user(handle, &user, NULL);
    if (result != PAM_SUCCESS || user == NULL || *user == '\0')
        return PAM_USER_UNKNOWN;

    for (;;) {
        char *selector = NULL;

        result = pam_prompt(handle, PAM_PROMPT_ECHO_OFF, &selector,
                            "Authentication method:");
        if (result != PAM_SUCCESS || selector == NULL)
            return result == PAM_SUCCESS ? PAM_CONV_ERR : result;

        if (strcmp(selector, PASSWORD_SELECTOR) == 0) {
            free(selector);
            return PAM_IGNORE;
        }
        if (strcmp(selector, FACE_SELECTOR) != 0
                && strcmp(selector, FINGERPRINT_SELECTOR) != 0) {
            free(selector);
            return PAM_IGNORE;
        }

        result = run_biometric_helper(selector, user);
        free(selector);
        if (result == PAM_SUCCESS)
            return PAM_SUCCESS;
        if (result != PAM_IGNORE)
            return result;

        /* Retry within this conversation to avoid greetd cancel/create races. */
    }
}

PAM_EXTERN int pam_sm_setcred(pam_handle_t *handle, int flags,
                              int argc, const char **argv) {
    (void)handle;
    (void)flags;
    (void)argc;
    (void)argv;
    return PAM_SUCCESS;
}
