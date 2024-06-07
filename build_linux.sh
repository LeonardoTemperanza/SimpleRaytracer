#!/bin/bash

mkdir -p build/linux64
pushd build/linux64

include_dirs="-I../../include -I../../src"
lib_dirs="-L../../libs/linux64"

source_files="../../src/main.c"
lib_files="-lglfw -lm -lGL -lX11"
output_name="simple_rt"

common="$include_dirs $source_files $lib_dirs $lib_files -o $output_name"

gcc -g -DDEBUG -O0 $common
build_ret=$?

if [ $build_ret -eq 0 ]; then
    ./$output_name
fi

popd
