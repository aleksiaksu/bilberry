#!/bin/bash
rm -r ./build
rm -r ./system/build
rm -r ./initramfs/build
cd ./initramfs
./make_all_ready.sh
cd ..
cd ./system
./make_all_ready.sh
cd ..