#!/bin/bash

# 1 - a package folder for building and checking

pkgname=$1

BIOC="$HOME/Bioconductor"

shopt -s expand_aliases

source ~/.bash_aliases

cd $BIOC

buildr $pkgname
checkr ${pkgname}_*

if [ $? -ne 0 ]; then
    echo "Check failed, fix issues and try again"
    exit 2
fi

time Rdev CMD BiocCheck ${pkgname}_*

shopt -u expand_aliases

