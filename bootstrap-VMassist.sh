#!/usr/bin/env bash

DEPLOYPATH="/tmp/VMassist"

echo "Creating $DEPLOYPATH"
mkdir $DEPLOYPATH

echo "downloading script(s)"
wget --directory-prefix=$DEPLOYPATH https://github.com/pagienge/walinuxagenthealth/blob/main/VMassist.sh
wget --directory-prefix=$DEPLOYPATH https://github.com/pagienge/walinuxagenthealth/blob/main/VMassist.py

 cd $DEPLOYPATH
 echo "Script will not be auto-run, please run $DEPLOYPATH/VMassist.sh once you have reviewed the content of the downloaded script(s)"
 exit
 
