#!/usr/bin/env bash

DEPLOYPATH="/tmp/VMassist"

echo "Creating $DEPLOYPATH"
mkdir $DEPLOYPATH

echo "downloading script(s)"
wget --directory-prefix=$DEPLOYPATH https://raw.githubusercontent.com/pagienge/walinuxagenthealth/main/VMassist.sh
wget --directory-prefix=$DEPLOYPATH https://raw.githubusercontent.com/pagienge/walinuxagenthealth/main/VMassist.py

 cd $DEPLOYPATH
 echo "Script will not be auto-run, please run $DEPLOYPATH/VMassist.sh once you have reviewed the content of the downloaded script(s)"
 exit
 
