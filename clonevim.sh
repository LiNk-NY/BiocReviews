#!/bin/bash

# 1 - package name

pkgname=$1

BIOC="$HOME/reviews"

PKGLOC=$BIOC/$pkgname

if [ -z "${pkgname// }" ]; then
    echo "Enter a package folder name"
    exit 1
elif [ ! -d $PKGLOC ]; then
    cd $BIOC
    git clone git@git.bioconductor.org:packages/${pkgname}.git
fi

cd $PKGLOC

biocfile="$BIOC/BiocReviews/packages/${pkgname}_review.txt"

echo $biocfile
if [ ! -e "$biocfile" ] ; then
    touch $biocfile
fi 

R_LIBS_USER=$HOME/R/bioc-devel RLOC=$HOME/src/svn/r-devel/R/bin RCOMP=$HOME/.cache/Nvim-Rd /usr/local/bin/vim -O $biocfile DESCRIPTION NAMESPACE vignettes/*.Rmd R/*R

