/*
 * linkline_server.c
 *
 * A simple "linkline" server that:
 *   - Binds to a user-specified IP and port
 *   - Logs connections to ./log.txt
 *   - PROMPTS for a PASSWORD before launching /bin/sh
 *
 * Usage:
 *   ./linkline_server <bind_ip> <port> <password>
 *
 * Example:
 *   ./linkline_server 127.0.0.1 2323 secret123
 *
 * WARNING:
 *   1. This is still extremely insecure. The "password" is sent in plaintext
 *      over the network, and typed in plaintext by the user (no echo hiding).
 *   2. There's no Telnet option negotiation, so a real telnet client may show
 *      weird control sequences or echo the password.
 *   3. For real security, use SSH or a properly hardened service.
 *   4. This is NOT a real Telnet client—no negotiation, no security.
 *   5. It will display raw data (including Telnet control sequences).
 *   6. Only use in controlled environments. If you need security,
 *       please use SSH or a similar secure protocol.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/socket.h>
#include <arpa/inet.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <errno.h>
#include <time.h>
#include <stdarg.h>

#define BACKLOG 5
#define MAX_PASS_LEN 128

// Log to file with timestamp
void log_message(FILE *logfile, const char *format, ...) {
    if (!logfile) return;

    time_t now = time(NULL);
    struct tm *tm_info = localtime(&now);
    char time_str[32];
    strftime(time_str, sizeof(time_str), "%Y-%m-%d %H:%M:%S", tm_info);

    fprintf(logfile, "[%s] ", time_str);

    va_list args;
    va_start(args, format);
    vfprintf(logfile, format, args);
    va_end(args);

    fflush(logfile);
}

int main(int argc, char *argv[]) {
    if (argc != 4) {
        fprintf(stderr, "Usage: %s <bind_ip> <port> <password>\n", argv[0]);
        fprintf(stderr, "Example: %s 127.0.0.1 2323 secret123\n", argv[0]);
        exit(EXIT_FAILURE);
    }

    const char *bind_ip  = argv[1];
    int         port     = atoi(argv[2]);
    const char *password = argv[3];

    if (port <= 0 || port > 65535) {
        fprintf(stderr, "Invalid port: %s\n", argv[2]);
        exit(EXIT_FAILURE);
    }

    // Open log file for appending
    FILE *logfile = fopen("./log.txt", "a");
    if (!logfile) {
        perror("fopen log.txt");
        exit(EXIT_FAILURE);
    }
    log_message(logfile, "Starting linkline_server on %s:%d with password.\n", bind_ip, port);

    // Create the listening socket
    int server_fd = socket(AF_INET, SOCK_STREAM, 0);
    if (server_fd < 0) {
        perror("socket");
        log_message(logfile, "socket() failed: %s\n", strerror(errno));
        fclose(logfile);
        exit(EXIT_FAILURE);
    }

    // Reuse address
    int optval = 1;
    if (setsockopt(server_fd, SOL_SOCKET, SO_REUSEADDR, &optval, sizeof(optval)) < 0) {
        perror("setsockopt");
        log_message(logfile, "setsockopt() failed: %s\n", strerror(errno));
        close(server_fd);
        fclose(logfile);
        exit(EXIT_FAILURE);
    }

    struct sockaddr_in server_addr;
    memset(&server_addr, 0, sizeof(server_addr));
    server_addr.sin_family      = AF_INET;
    server_addr.sin_port        = htons(port);

    // Convert IP from text to binary
    if (inet_pton(AF_INET, bind_ip, &server_addr.sin_addr) <= 0) {
        perror("inet_pton");
        log_message(logfile, "Invalid bind IP address: %s\n", bind_ip);
        close(server_fd);
        fclose(logfile);
        exit(EXIT_FAILURE);
    }

    if (bind(server_fd, (struct sockaddr *)&server_addr, sizeof(server_addr)) < 0) {
        perror("bind");
        log_message(logfile, "bind() failed on %s:%d: %s\n", bind_ip, port, strerror(errno));
        close(server_fd);
        fclose(logfile);
        exit(EXIT_FAILURE);
    }

    if (listen(server_fd, BACKLOG) < 0) {
        perror("listen");
        log_message(logfile, "listen() failed: %s\n", strerror(errno));
        close(server_fd);
        fclose(logfile);
        exit(EXIT_FAILURE);
    }

    printf("linkline_server listening on %s:%d (with password)\n", bind_ip, port);
    log_message(logfile, "Server listening on %s:%d\n", bind_ip, port);

    while (1) {
        struct sockaddr_in client_addr;
        socklen_t client_len = sizeof(client_addr);

        int client_fd = accept(server_fd, (struct sockaddr *)&client_addr, &client_len);
        if (client_fd < 0) {
            perror("accept");
            log_message(logfile, "accept() failed: %s\n", strerror(errno));
            continue;
        }

        // Convert client IP/port to string
        char client_ip[INET_ADDRSTRLEN];
        inet_ntop(AF_INET, &client_addr.sin_addr, client_ip, sizeof(client_ip));
        int client_port = ntohs(client_addr.sin_port);
        log_message(logfile, "Incoming connection from %s:%d\n", client_ip, client_port);

        pid_t pid = fork();
        if (pid < 0) {
            perror("fork");
            log_message(logfile, "fork() failed: %s\n", strerror(errno));
            close(client_fd);
            continue;
        }

        if (pid == 0) {
            // Child process
            close(server_fd); // Child doesn't need the listening socket

            // Step 1: Prompt the client for a password (plaintext, no echo hiding!)
            const char *prompt = "Password: ";
            write(client_fd, prompt, strlen(prompt));

            // Read what they typed
            char pass_buf[MAX_PASS_LEN + 1];
            ssize_t n = read(client_fd, pass_buf, MAX_PASS_LEN);
            if (n <= 0) {
                log_message(logfile, "Child %d: no password read or error.\n", getpid());
                close(client_fd);
                fclose(logfile);
                exit(EXIT_FAILURE);
            }

            // Remove trailing newline if present
            // This is naive. We assume the last char is '\n'.
            // If it's \r\n or partial, we handle that trivially for demonstration.
            if (pass_buf[n - 1] == '\n' || pass_buf[n - 1] == '\r')
                pass_buf[n - 1] = '\0';
            else
                pass_buf[n] = '\0'; // Ensure null termination

            // Step 2: Compare to the real password
            if (strcmp(pass_buf, password) != 0) {
                // Password mismatch
                const char *deny = "\nAccess denied.\n";
                write(client_fd, deny, strlen(deny));
                log_message(logfile,
                            "Child %d: Incorrect password attempt from %s:%d\n",
                            getpid(), client_ip, client_port);
                close(client_fd);
                fclose(logfile);
                exit(EXIT_FAILURE);
            }

            // Step 3: If password is correct, proceed to shell
            log_message(logfile,
                        "Child %d handling client %s:%d; password OK. Launching shell.\n",
                        getpid(), client_ip, client_port);

            // Redirect stdin/stdout/stderr to the client socket
            dup2(client_fd, STDIN_FILENO);
            dup2(client_fd, STDOUT_FILENO);
            dup2(client_fd, STDERR_FILENO);

            // Launch shell
            execl("/bin/sh", "sh", (char *)NULL);

            // If execl fails:
            log_message(logfile, "Child %d: execl() failed: %s\n", getpid(), strerror(errno));
            perror("execl");
            close(client_fd);
            fclose(logfile);
            exit(EXIT_FAILURE);

        } else {
            // Parent process
            close(client_fd); // Parent doesn't need this socket
            log_message(logfile, "Forked child %d for client %s:%d\n",
                        pid, client_ip, client_port);

            // Optionally wait for the child to finish
            waitpid(pid, NULL, 0);
            log_message(logfile, "Child %d for client %s:%d has exited\n",
                        pid, client_ip, client_port);
        }
    }

    close(server_fd);
    fclose(logfile);
    return 0;
}
