#!/bin/bash

sudo apt update -y
sudo apt install build-essential cmake -y

workdir=/home/ubuntu
cd $workdir 
git clone https://github.com/microsoft/lagscope.git 
cd lagscope 
./do-cmake.sh build
cd $workdir
chown -R ubuntu:ubuntu lagscope
