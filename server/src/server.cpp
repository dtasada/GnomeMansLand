#include "../include/server.hpp"

#include <fstream>
#include <iostream>
#include <nlohmann/json.hpp>
#include <nlohmann/json_fwd.hpp>
#include <sstream>

#define MAX_PACKET_SIZE 64512  // 63 KB

RemoteClient::RemoteClient(TCPsocket socket, IPaddress address) :
    socket(socket),
    address(address),
    connected(true) {}

Server::Server(Settings st) : port(st.server.port) {
    if (SDLNet_Init() < 0) exit_failure("Failure to initialize SDL_net");

    /* Resolving the host using NULL make network interface to listen */
    if (SDLNet_ResolveHost(&address, NULL, port) < 0) exit_failure("Failure to resolve host");

    /* Open a connection with the IP provided (listen on the host's port) */
    if (!(socket = SDLNet_TCP_Open(&address))) exit_failure("Failure to open port");

    database_path = "server/db.json";
    std::ifstream database_file(database_path);

    if (database_file.is_open()) {
        try {
            database_file >> database;
            std::clog << "Loaded database from " << database_path << std::endl;
        } catch (nlohmann::json::parse_error &e) {
            std::cerr << "Failed to parse database: " << e.what() << std::endl;
            std::exit(EXIT_FAILURE);
        }
        database_file.close();
    } else {
        std::clog << database_path << " doesn't exist. Creating new database." << std::endl;
        database = {
            {"players",                 nlohmann::json::array()},
            {  "world", {{"map_data", nlohmann::json::array()}}},
        };
        std::ofstream new_file(database_path);
        new_file << database.dump(4);
        new_file.close();
        std::clog << "Created new database at " << database_path << std::endl;
    }

    world   = WorldGen(st, database);
    running = true;
}

Server::~Server() {
    running = false;
    SDLNet_FreeSocketSet(socket_set);
    SDLNet_TCP_Close(socket);
    SDLNet_Quit();
    std::clog << "Closed SDL_net." << std::endl;

    std::ofstream database_file(database_path);
    if (database_file.is_open()) {
        database_file << database.dump(4);
        database_file.close();
        std::clog << "Saved database at " << database_path << std::endl;
    } else {
        std::cerr << "Failed to save database." << std::endl;
    }
}

void Server::exit_failure(std::string message) {
    std::cerr << message << ": " << SDLNet_GetError() << std::endl;
    std::exit(EXIT_FAILURE);
}

void Server::handle_clients() {
    // Listen for incoming messages from clients
    for (RemoteClient &client : client_connections) {
        if (SDLNet_SocketReady(client.socket)) {
            static std::vector<char> buffer(MAX_PACKET_SIZE);
            size_t bytes_received = SDLNet_TCP_Recv(client.socket, buffer.data(), buffer.size());

            if (bytes_received > 0 && bytes_received < buffer.size()) {
                std::stringstream message_stream(std::string(buffer.data(), bytes_received));
                std::string       message;
                std::vector<std::string> messages;

                while (std::getline(message_stream, message, '\n')) {
                    nlohmann::json message_t = nlohmann::json::parse(message);
                    if (message_t.contains("fetch")) {
                        if (message_t["fetch"] == "world") {
                            std::clog << "Client requested world data" << std::endl;

                            nlohmann::json current_chunk = {
                                {"map_data", nlohmann::json::object()}
                            };
                            int current_chunk_index = 0;

                            int height = database["world"]["map_data"].size();
                            int width  = database["world"]["map_data"][0].size();
                            for (int y = 0; y < height; y++) {
                                for (int x = 0; x < width; x++) {
                                    std::string    x_s   = std::to_string(x);
                                    std::string    y_s   = std::to_string(y);
                                    nlohmann::json pixel = database["world"]["map_data"][y][x];

                                    current_chunk["chunk_num"] = current_chunk_index;

                                    size_t pixel_size = pixel.dump().size();
                                    size_t total_size = current_chunk.dump().size();

                                    if (total_size + pixel_size < MAX_PACKET_SIZE) {
                                        current_chunk["map_data"][y_s][x_s] = pixel;
                                    }
                                    if (total_size + pixel_size >= MAX_PACKET_SIZE
                                        || (x == width - 1 && y == height - 1)) {
                                        send(client, "world", current_chunk);
                                        current_chunk.clear();
                                        current_chunk_index++;
                                    }
                                }
                            }

                            send(
                                client,
                                "close_world_fetch",
                                {
                                    {"packet_count", current_chunk_index}
                            }
                            );
                        } else {
                            std::cerr << "Invalid fetch request" << std::endl;
                            std::cerr << message_t["fetch"] << std::endl;
                        }
                    } else {
                        std::clog << "Received message from client: " << message << std::endl;
                    }
                }
            } else {
                client.connected = false;
                SDLNet_TCP_DelSocket(socket_set, client.socket);
                SDLNet_TCP_Close(client.socket);
            }
        }
    }

    // Remove any disconnected clients
    std::erase_if(client_connections, [](const RemoteClient &client) {
        if (!client.connected)
            std::clog << "Client disconnected: " << client.address.host << ":"
                      << client.address.port << std::endl;
        return !client.connected;
    });
}

void Server::listen() {
    std::clog << "SDL_net server listening on port " << port << std::endl;

    // Create a socket set for the server and clients
    const int max_sockets = 32;
    if (!(socket_set = SDLNet_AllocSocketSet(max_sockets)))
        exit_failure("Failed to allocate socket set");

    SDLNet_TCP_AddSocket(socket_set, socket);

    const uint32_t timeout = 10;
    while (running) {
        handle_clients();

        if (SDLNet_CheckSockets(socket_set, timeout) > 0 && SDLNet_SocketReady(socket)) {
            TCPsocket client_socket = SDLNet_TCP_Accept(socket);
            if (client_socket) {
                IPaddress *client_ip = SDLNet_TCP_GetPeerAddress(client_socket);
                if (client_ip) new_client(client_socket, *client_ip);
            }
        }
    }
}

void Server::send(RemoteClient &client, std::string descriptor, nlohmann::json message_t) {
    message_t["descriptor"] = descriptor;
    std::string message     = message_t.dump();
    message += "\n";

    std::clog << "Sending message: " << message << std::endl;
    std::cerr << "Message length: " << message.size() << std::endl;

    if (SDLNet_TCP_Send(client.socket, message.c_str(), message.length()) < message.length()) {
        std::cerr << "Failed to send message" << std::endl;
    }
}

void Server::send_to_all(std::string descriptor, nlohmann::json message_t) {
    for (RemoteClient &client : client_connections) { send(client, descriptor, message_t); }
}

void Server::new_client(TCPsocket client_socket, IPaddress client_address) {
    SDLNet_TCP_AddSocket(socket_set, client_socket);

    client_connections.emplace_back(client_socket, client_address);
    database["players"].push_back({
        {"host", client_address.host},
        {"port", client_address.port}
    });

    std::clog << "New client connected: " << client_address.host << ":" << client_address.port
              << std::endl;
}
