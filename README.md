# Health check script for Azure Agent on Linux - waagent
VMassist is a combination of bash and python scripts intended to be used to diagnose issues with the Azure agent in a Linux VM, and related issues with the general health of the VM.

Running the VMassist.sh script will generate a serial-console-friendly summary of checks, as the intent is to identify common issues and present them in an easy-to-consume format given that troubleshooting is often done in the limited-size serial console  Further logging is done to /var/log/azure

## Prerequisites
There are two components of the script
- basic diagnostics done in the bash script, with the aim of validating the base OS issues and most importantly the python environment
- more comprehensive checks in python

## Usage
### automatic download
- run `bash <(curl -sL https://raw.githubusercontent.com/pagienge/walinuxagenthealth/main/bootstrap-VMassist.sh)`

### manual download
- download the bootstrapping script - bootstrap-VMassist.sh
- run `bootstrap-VMassist.sh` to get both scripts and place in a temporary location

### Running VMassist
- neither of the 'download' procedures will automatically run the diagnostic script
- Run the `VMassist.sh` from the path reported in the output of `bootstrap-VMassist.sh` as root, or through sudo

### syntax
Syntax: VMassist.sh [-h|v]
- options:
   -h     Print this Help.
   -v     Verbose mode.