#!/bin/bash

# 1 - a package folder for building and checking
pkgname=$1

REVIEWS="$HOME/reviews/"

shopt -s expand_aliases

source ~/.bash_aliases

cd $REVIEWS

buildd $pkgname
checkd ${pkgname}_*

if [ $? -ne 0 ]; then
    echo "Check failed, fix issues and try again"
    exit 2
fi

time bioccheck $pkgname

shopt -u expand_aliases

