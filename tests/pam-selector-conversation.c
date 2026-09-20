#include <security/pam_appl.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

struct conversation_state {
    const char *selector;
    const char *password;
    int prompts;
};

static int converse(int count, const struct pam_message **messages,
                    struct pam_response **responses, void *data) {
    struct conversation_state *state = data;
    struct pam_response *result = calloc((size_t)count, sizeof(*result));
    if (result == NULL)
        return PAM_BUF_ERR;

    for (int index = 0; index < count; index++) {
        if (messages[index]->msg_style != PAM_PROMPT_ECHO_OFF
                && messages[index]->msg_style != PAM_PROMPT_ECHO_ON)
            continue;

        const char *response;
        state->prompts++;
        if (strcmp(messages[index]->msg, "Authentication method:") == 0)
            response = state->prompts == 1 ? state->selector
                : "session-stack-greeter:password:v1";
        else if (strcmp(messages[index]->msg, "Password:") == 0)
            response = state->password;
        else {
            for (int previous = 0; previous < index; previous++)
                free(result[previous].resp);
            free(result);
            return PAM_CONV_ERR;
        }
        result[index].resp = strdup(response);
        if (result[index].resp == NULL) {
            for (int previous = 0; previous < index; previous++)
                free(result[previous].resp);
            free(result);
            return PAM_BUF_ERR;
        }
    }

    *responses = result;
    return PAM_SUCCESS;
}

int main(int argc, char **argv) {
    struct conversation_state state;
    struct pam_conv conversation = {converse, &state};
    pam_handle_t *handle = NULL;
    int expected_prompts;
    int expected_result;
    int result;

    if (argc != 4 && argc != 5) {
        fprintf(stderr, "usage: %s SELECTOR EXPECTED_PROMPTS USER [reject]\n", argv[0]);
        return 2;
    }
    state.selector = argv[1];
    state.password = argc == 5 ? "wrong-test-password" : "test-password";
    expected_result = argc == 5 ? PAM_AUTH_ERR : PAM_SUCCESS;
    state.prompts = 0;
    expected_prompts = atoi(argv[2]);

    result = pam_start("greetd", argv[3], &conversation, &handle);
    if (result == PAM_SUCCESS)
        result = pam_authenticate(handle, 0);
    if (handle != NULL)
        pam_end(handle, result);

    if (result != expected_result || state.prompts != expected_prompts) {
        fprintf(stderr, "PAM returned %d with %d prompts; expected %d/%d\n",
                result, state.prompts, expected_result, expected_prompts);
        return 1;
    }
    return 0;
}
