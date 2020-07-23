#!/bin/bash

# 1 - package name

pkgname=$1

BIOC="$HOME/bioc"

PKGLOC=$BIOC/$pkgname

if [ -z "${pkgname// }" ]; then
    echo "Enter a package folder name"
    exit 1
elif [ ! -d $PKGLOC ]; then
    echo "Directory does not exist"
    exit 1
fi

cd $PKGLOC

biocfile="$BIOC/BiocReviews/packages/${pkgname}_review.txt"

echo $biocfile
if [ ! -e "$biocfile" ] ; then
    touch $biocfile
fi 

vim -O $biocfile DESCRIPTION NAMESPACE vignettes/*.Rmd R/*R R/*\.r

