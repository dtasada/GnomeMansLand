#pragma once

#include "../../shared/include/engine.hpp"

#include <nlohmann/json.hpp>
#include <string>
#include <thread>
#include <vector>

class Client {
    std::string host;
    uint16_t    port;
    uint32_t    timeout;

    IPaddress        server_ip;
    TCPsocket        socket;
    SDLNet_SocketSet socket_set;

    std::thread listen_thread;

    void exit_failure(std::string message);

  public:
    Client(Settings);
    ~Client(void);

    bool                        connected;
    std::vector<nlohmann::json> message_handles;

    void start(void);
    void stop(void);
    void listen(void);
    void send(std::string message);
};
