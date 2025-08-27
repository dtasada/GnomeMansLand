#include "../../shared/include/engine.hpp"
#include "../include/client.hpp"

#include <iostream>
#include <sstream>
#include <vector>

Client::Client(Settings st) {
    connected = false;
    host      = st.multiplayer.server_host;
    port      = st.multiplayer.server_port;
    timeout   = st.multiplayer.server_polling_interval;

    start();
}

Client::~Client(void) {
    connected = false;
    if (listen_thread.joinable()) listen_thread.join();

    std::clog << "Closing network client" << std::endl;
    SDLNet_TCP_Close(socket);
    SDLNet_Quit();
}

void Client::start(void) {
    if (SDLNet_Init() < 0) {
        exit_failure("Failed to initialize SDL_net");
    } else {
        std::clog << "Client initialized SDL_net" << std::endl;
    }

    if (SDLNet_ResolveHost(&server_ip, host.c_str(), port) < 0) {
        exit_failure("Failed to resolve host");
    } else {
        std::clog << "Client resolved host" << std::endl;
    }

    if (!(socket = SDLNet_TCP_Open(&server_ip))) {
        exit_failure("Failed to open port");
    } else {
        std::clog << "Client opened port" << std::endl;
    }

    if (!(socket_set = SDLNet_AllocSocketSet(1))) {
        exit_failure("Failed to allocate socket set");
    }

    SDLNet_TCP_AddSocket(socket_set, socket);

    connected     = true;
    listen_thread = std::thread(&Client::listen, this);
}

void Client::listen(void) {
    std::vector<char> buffer(65535);

    while (connected) {
        if (SDLNet_CheckSockets(socket_set, timeout) > 0 && SDLNet_SocketReady(socket)) {
            size_t bytes_received = SDLNet_TCP_Recv(socket, buffer.data(), buffer.size());

            if (bytes_received > 0) {
                std::stringstream message_stream(std::string(buffer.data(), bytes_received));
                std::string       message;
                std::vector<std::string> messages;

                while (std::getline(message_stream, message, '\n'))
                    message_handles.push_back(nlohmann::json::parse(message));
            } else {
                std::clog << "Connection lost or error while receiving data." << std::endl;
                connected = false;
            }
        }
    }
}

void Client::send(std::string message) {
    message += "\n";
    if (SDLNet_TCP_Send(socket, message.c_str(), message.length()) < message.length())
        std::cerr << "Failed to send message" << std::endl;
}

void Client::exit_failure(std::string message) {
    std::cerr << message << ": " << SDLNet_GetError() << std::endl;
    std::exit(EXIT_FAILURE);
}
