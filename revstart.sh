#!/bin/bash

# 1 - package name

pkgname=$1

if [ -z "${pkgname// }" ]; then
    echo "Enter a package folder name"
    exit 1
fi

cd $pkgname

biocfile="$HOME/Bioconductor/BiocReviews/${pkgname}_review.txt"

echo $file
if [ ! -e "$file" ] ; then
    touch $file
fi 

vim -O $file DESCRIPTION NAMESPACE vignettes/*.Rmd R/*R 

