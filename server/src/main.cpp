#include "../include/server.hpp"

#include <cstdlib>
#include <iostream>
#include <ostream>

int main(int argc, char *argv[]) {
    Server server(Settings::parse());
    server.listen();

    std::cout << "Database: " << server.database.dump(4) << std::endl;
    return EXIT_SUCCESS;
}
