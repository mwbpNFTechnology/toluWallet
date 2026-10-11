#!/bin/bash
# Builds the firmware's own source files for this computer and runs them
# against reference values. No hardware, no Arduino tools: any C++17
# compiler will do.
set -euo pipefail
cd "$(dirname "$0")"

CXX="${CXX:-c++}"
FLAGS=(-std=c++17 -O1 -g -Wall -Wextra -Werror -fsanitize=address,undefined -fno-sanitize-recover=undefined -I ..)

mkdir -p build
"$CXX" "${FLAGS[@]}" test_crypto.cpp -o build/test_crypto
"$CXX" "${FLAGS[@]}" -I stubs test_card.cpp -o build/test_card

./build/test_crypto vectors.txt
./build/test_card
