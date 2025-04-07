/*
 * linkline_client.c
 *
 * A simple "linkline" client. Connects to a host:port, then relays
 * data between the user (stdin/stdout) and the server (socket).
 *
 * Compile (using musl-gcc or any other C compiler):
 *    musl-gcc linkline_client.c -o linkline_client
 *
 * Usage:
 *    ./linkline_client <host> <port>
 *
 * Example:
 *    ./linkline_client 127.0.0.1 2323
 *
 * WARNING:
 *    1. This is NOT a real Telnet client—no negotiation, no security.
 *    2. It will display raw data (including Telnet control sequences).
 *    3. Only use in controlled environments. If you need security,
 *       please use SSH or a similar secure protocol.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <errno.h>
#include <sys/types.h>
#include <arpa/inet.h>
#include <sys/socket.h>
#include <fcntl.h>
#include <sys/select.h>

int main(int argc, char *argv[]) {
    if (argc != 3) {
        fprintf(stderr, "Usage: %s <host> <port>\n", argv[0]);
        exit(EXIT_FAILURE);
    }

    const char *host = argv[1];
    int port = atoi(argv[2]);
    if (port <= 0 || port > 65535) {
        fprintf(stderr, "Invalid port number.\n");
        exit(EXIT_FAILURE);
    }

    // Create socket
    int sockfd = socket(AF_INET, SOCK_STREAM, 0);
    if (sockfd < 0) {
        perror("socket");
        exit(EXIT_FAILURE);
    }

    // Prepare server address
    struct sockaddr_in server_addr;
    memset(&server_addr, 0, sizeof(server_addr));
    server_addr.sin_family = AF_INET;
    server_addr.sin_port = htons(port);

    // Convert host string to binary form (IPv4)
    if (inet_pton(AF_INET, host, &server_addr.sin_addr) <= 0) {
        perror("inet_pton");
        close(sockfd);
        exit(EXIT_FAILURE);
    }

    // Connect to the server
    if (connect(sockfd, (struct sockaddr *)&server_addr, sizeof(server_addr)) < 0) {
        perror("connect");
        close(sockfd);
        exit(EXIT_FAILURE);
    }

    printf("Connected to %s:%d.\n", host, port);
    printf("Type your commands or text. Press Ctrl-C or Ctrl-D to exit.\n\n");

    // Use select() to watch both STDIN and the socket
    while (1) {
        fd_set readfds;
        FD_ZERO(&readfds);

        FD_SET(STDIN_FILENO, &readfds);
        FD_SET(sockfd, &readfds);

        int max_fd = (STDIN_FILENO > sockfd) ? STDIN_FILENO : sockfd;
        int ready = select(max_fd + 1, &readfds, NULL, NULL, NULL);
        if (ready < 0) {
            perror("select");
            break;
        }

        // Check if there's data from stdin
        if (FD_ISSET(STDIN_FILENO, &readfds)) {
            char buf[1024];
            ssize_t len = read(STDIN_FILENO, buf, sizeof(buf));
            if (len < 0) {
                perror("read from stdin");
                break;
            } else if (len == 0) {
                // EOF on stdin
                printf("\nEOF on stdin. Closing connection.\n");
                break;
            } else {
                // Send to server
                ssize_t sent = send(sockfd, buf, len, 0);
                if (sent < 0) {
                    perror("send");
                    break;
                }
            }
        }

        // Check if there's data from the server
        if (FD_ISSET(sockfd, &readfds)) {
            char buf[1024];
            ssize_t len = recv(sockfd, buf, sizeof(buf), 0);
            if (len < 0) {
                perror("recv");
                break;
            } else if (len == 0) {
                // Server closed connection
                printf("Server closed connection.\n");
                break;
            } else {
                // Write data to stdout
                if (write(STDOUT_FILENO, buf, len) < 0) {
                    perror("write to stdout");
                    break;
                }
            }
        }
    }

    close(sockfd);
    return 0;
}
