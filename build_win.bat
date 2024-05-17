
@echo off
setlocal enabledelayedexpansion

if not exist build mkdir build 
if not exist build\win64 mkdir build\win64

pushd build\win64

set include_dirs=/I..\..\include /I..\..
set lib_dirs=/LIBPATH:..\..\libs\win64

set source_files=..\..\main.c
set lib_files=user32.lib gdi32.lib shell32.lib glfw\glfw3_mt.lib
set output_name=simple_rt.exe

set common=/nologo /FC /MT %include_dirs% %source_files% /link %lib_dirs% %lib_files% /out:%output_name%

REM Development build, debug is enabled, profiling and optimization disabled
cl /Zi /DDEBUG /Od %common%
set build_ret=%errorlevel%

if %build_ret%==0 (
simple_rt.exe
)

popd