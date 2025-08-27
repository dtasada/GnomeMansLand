cmake_minimum_required(VERSION 3.31)

project(po6)
set(CMAKE_CXX_STANDARD 23)

# Optimize GNU compiler flags
if(CMAKE_COMPILER_IS_GNUCXX)
    message(STATUS "GNU CXX detected, adding compile flags")
	add_compile_options(-Wall -Wextra -Wsign-compare -O3)
endif()

set(CMAKE_RUNTIME_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/bin)

# Gather source files
file(GLOB_RECURSE CLIENT_FILES client/src/*.cpp)
file(GLOB_RECURSE SERVER_FILES server/src/*.cpp)
file(GLOB_RECURSE SHARED_FILES shared/src/*.cpp)

# Add executables
add_executable(client ${CLIENT_FILES} ${SHARED_FILES})
add_executable(server ${SERVER_FILES} ${SHARED_FILES})

# Setup OpenMP
function(setup_openmp target)
    if(APPLE)
        # Get Homebrew paths
        execute_process(COMMAND brew --prefix llvm OUTPUT_STRIP_TRAILING_WHITESPACE OUTPUT_VARIABLE LLVM_PREFIX)
        execute_process(COMMAND brew --prefix libomp OUTPUT_STRIP_TRAILING_WHITESPACE OUTPUT_VARIABLE OPENMP_PREFIX)

        # Force Homebrew Clang as compiler
        set(CMAKE_C_COMPILER "${LLVM_PREFIX}/bin/clang" CACHE STRING "" FORCE)
        set(CMAKE_CXX_COMPILER "${LLVM_PREFIX}/bin/clang++" CACHE STRING "" FORCE)

        # Apply OpenMP flags
        target_compile_options(${target} PRIVATE -Xpreprocessor -fopenmp -I${OPENMP_PREFIX}/include)
        target_link_libraries(${target} PRIVATE -L${OPENMP_PREFIX}/lib omp)
    else()
        find_package(OpenMP REQUIRED)
        target_link_libraries(${target} PRIVATE OpenMP::OpenMP_CXX)
    endif()

	if(MSVC)
		add_compile_options(/openmp /std:c++latest)
	endif()
endfunction()

# Fetch dependencies
include(FetchContent)

FetchContent_Declare(SDL2        GIT_REPOSITORY https://github.com/libsdl-org/SDL         GIT_TAG release-2.30.11)
FetchContent_Declare(SDL2_image  GIT_REPOSITORY https://github.com/libsdl-org/SDL_image  GIT_TAG release-2.8.4)
FetchContent_Declare(SDL2_net    GIT_REPOSITORY https://github.com/libsdl-org/SDL_net    GIT_TAG release-2.2.0)
FetchContent_Declare(json        GIT_REPOSITORY https://github.com/nlohmann/json         GIT_TAG v3.11.3)
FetchContent_Declare(toml        GIT_REPOSITORY https://github.com/marzer/tomlplusplus  GIT_TAG v3.4.0)

FetchContent_MakeAvailable(SDL2 SDL2_image SDL2_net json toml)

# Apply common settings to targets
foreach(TARGET client server)
    setup_openmp(${TARGET})

    target_include_directories(${TARGET} PRIVATE
		shared/include
		client/include
		server/include
        ${SDL2_INCLUDE_DIR}
        ${SDL2_image_INCLUDE_DIR}
        ${SDL2_net_INCLUDE_DIR}
        ${json_SOURCE_DIR}/include
        ${toml_SOURCE_DIR}/include
    )

    target_link_libraries(${TARGET} PRIVATE
        SDL2::SDL2
        SDL2::SDL2main
        SDL2_image::SDL2_image
        SDL2_net::SDL2_net
    )
endforeach()
