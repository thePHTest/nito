@echo off
set bat_dir=%~dp0
pushd %bat_dir%
IF NOT EXIST .\debug_build mkdir .\debug_build
pushd debug_build
odin build ../src/win32_nito.odin -debug
popd popd
