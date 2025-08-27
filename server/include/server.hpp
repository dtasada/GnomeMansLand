#pragma once

#if defined(__linux)
    #include <nlohmann/json.hpp>
    #include <SDL2/SDL_net.h>
#elif defined(__APPLE__) || defined(_WIN32)
    #include <nlohmann/json.hpp>
    #include <SDL_net.h>
#endif

#include "../include/world_gen.hpp"

#include <string>
#include <vector>

struct RemoteClient {
    TCPsocket socket;
    IPaddress address;
    bool      connected;

    RemoteClient(TCPsocket socket, IPaddress address);
};

class Server {
    bool running;

    uint16_t port;

    IPaddress                 address;
    TCPsocket                 socket;
    SDLNet_SocketSet          socket_set;
    std::vector<RemoteClient> client_connections;

    void exit_failure(std::string message);
    void new_client(TCPsocket socket, IPaddress address);

  public:
    Server(Settings);
    ~Server();

    nlohmann::json database;
    std::string    database_path;

    WorldGen world;

    void listen(void);
    void handle_clients(void);
    void send(RemoteClient &client, std::string descriptor, nlohmann::json message_t);
    void send_to_all(std::string descriptor, nlohmann::json message_t);
};
