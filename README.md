# Health check script for Azure Agent on Linux - waagent
VMassist is a combination of bash and python scripts intended to be used to diagnose issues with the Azure agent in a Linux VM, and related issues with the general health of the VM.

Output is intended to be viewed in the serial console and provide pointers to solve some well-known issues, as well as certain deviations from best practice which can affect VM availability.

## Prerequisites
There are two components of the script
- basic diagnostics done in the bash script, with the aim of validating the base OS issues and most importantly the python environment
- more comprehensive checks in python

## Usage
### automatic download
- run `bash <(curl -sL https://raw.githubusercontent.com/pagienge/walinuxagenthealth/main/bootstrap-VMassist.sh)`

### manual download
- download the two scripts individually to the current directory
`wget https://github.com/pagienge/VMassist/raw/main/VMassist.sh`
`wget https://github.com/pagienge/VMassist/raw/main/VMassist.py`
- add executable permissions
`chmod VMassist.sh`
- Run the script
`./VMassist.sh`

### Running VMassist
- Running `bootstrap-VMassist.sh` will download and run the diagnostic script from `/tmp/VMassist`
- After downloading by any method, run the `VMassist.sh` from the path reported in the output of `bootstrap-VMassist.sh` as root, or through sudo

### syntax
Syntax: VMassist.sh [-h|v]
- options:
   -h     Print this Help.
   -v     Verbose mode.

### Analyzing output
The output from the script should be a serial console friendly report of well known issues, along with a link to current documentation on both interpreting the output and references for fixing identified issues.

Log output is created in `/var/log/azure`, using filenames staring with `VMassist`

### Issues running VMassist
#### Seems to hang forever
There are conditions where the scripts may not produce output at all and seem to hang without causing system load.  This may be due to the underlying package manager expecting interaction from a prompt, specifically on newer VMs.  If this is encountered, run a package manager command from the command line and watch for prompts.  Examples:
- dnf repolist
- zypper ref
- apt-get update
