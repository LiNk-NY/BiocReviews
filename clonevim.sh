#!/bin/bash

# 1 - package name

pkgname=$1

REVIEWS="$HOME/reviews"
BIOC="devel"

PKGLOC=$REVIEWS/$pkgname

RVER="r-4-4"

if [ -z "${pkgname// }" ]; then
    echo "Enter a package folder name"
    exit 1
elif [ ! -d $PKGLOC ]; then
    cd $REVIEWS
    git clone git@git.bioconductor.org:packages/${pkgname}.git
fi

cd $PKGLOC

biocfile="$REVIEWS/BiocReviews/packages/${pkgname}_review.txt"

echo $biocfile
if [ ! -e "$biocfile" ] ; then
    touch $biocfile
fi 

R_LIBS_USER=$HOME/R/bioc-${BIOC} RLOC=$HOME/src/svn/${RVER}/R/bin RCOMP=$HOME/.cache/Nvim-Rd /usr/local/bin/vim -O $biocfile DESCRIPTION NAMESPACE vignettes/*.Rmd R/*R

