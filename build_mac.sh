#!/bin/sh

mkdir -p build
mkdir -p build/mac64

pushd build/mac64

include_dirs="-I../../include -I../.."
lib_dirs="-L../../libs/mac64"

source_files="../../main.c"
lib_files="-lglfw3 -framework Cocoa -framework OpenGL -framework IOKit -framework CoreVideo"
output_name="simple_rt"

common="$include_dirs $source_files $lib_dirs $lib_files -o $output_name"

gcc -g -DDEBUG -O0 $common
build_ret=$?

if [ $build_ret -eq 0 ]; then
    ./$output_name
fi

popd