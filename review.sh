#!/bin/bash

# 1 - a package folder for building and checking

shopt -s expand_aliases

source ~/.bash_aliases

buildr $1 
checkr $1_*

if [ $? -ne 0 ]; then
    echo "Check failed, fix issues and try again"
    exit 2
fi

time Rdev CMD BiocCheck  $1

shopt -u expand_aliases

