#!/usr/bin/env bash

DEPLOYPATH="/tmp/VMassist"

echo "Creating $DEPLOYPATH"
mkdir $DEPLOYPATH

echo "downloading script(s)"
wget --directory-prefix=$DEPLOYPATH https://github.com/pagienge/walinuxagenthealth/blob/main/VMaccess.sh
wget --directory-prefix=$DEPLOYPATH https://github.com/pagienge/walinuxagenthealth/blob/main/VMaccess.py

 cd $DEPLOYPATH
 echo "Script will not be auto-run, please run $DEPLOYPATH/VMaccess.sh once you have reviewed the content of the downloaded script(s)"
 exit
 
