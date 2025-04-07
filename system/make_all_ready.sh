#!/bin/bash
./build_system.sh
./build_etc.sh
./build_ncurses.sh
./build_nano.sh
./build_musl_libc.sh
#./make_image.sh
#./build_iso.sh 
./make_image.sh


