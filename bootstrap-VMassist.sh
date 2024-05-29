#!/usr/bin/env bash

DLPATH="/tmp/VMassist"

echo "Creating $DLPATH"
mkdir $DLPATH

echo "downloading script(s)"
wget --no-verbose --show-progress --directory-prefix=$DLPATH https://raw.githubusercontent.com/pagienge/walinuxagenthealth/main/VMassist.sh
chmod +x $DLPATH/VMassist.sh
wget --no-verbose --show-progress --directory-prefix=$DLPATH https://raw.githubusercontent.com/pagienge/walinuxagenthealth/main/VMassist.py

 cd $DLPATH
 echo "Script will not be auto-run, please run $DLPATH/VMassist.sh once you have reviewed the content of the downloaded script(s)"
 return $?
 
