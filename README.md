# Build process
```sh
mkdir build # Create build folder
cmake -B build # Only necessary on first compilation, or after changing the build process in CMakeLists.txt
cmake --build build # Actually make project
./build/bin/client # Run
```
