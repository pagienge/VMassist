#!/usr/bin/env bash
# Description - Diagnostic script for the Azure Linux Agent.  Intended to be run by 
#  support personnel or system administrators to identify commonly identified issues
#  causing 'agent not ready' situations.
# Usage
#  Syntax: $0 [-h|-v]"
#    options:"
#      -h     Print this Help."
#      -v     Verbose mode."
#
# Need 
# - license statement
# - disclaimers
# - any other legalise

# defaults for the script structure
DEBUG=0
LOGDIR="/var/log/azure"
LOGFILE="$LOGDIR/waagenthealth.log"
FSFULLPCENT=90
FSFULLPCENT=10 # arbitrarily low testing value.  Release should set this to 90 or more
STARTTIME=$(date --rfc-3339=seconds)

# variable defaults for derived values
source /etc/os-release
DISTRO="hm-linux"
PY="/usr/bin/python3"
SERVICE="waagent.service"
PKG="rpm"
DNF="dnf"
UNITFILE="/usr/bin/false"
UNITSTAT="undef"
UNITSTATRC=0

# function definitions
function loggy {
  # simple logging handler
  # - writes output to the defined log file
  # - outputs to console if 'verbose' requested
  if [ $DEBUG -gt 0 ]; then
    echo "$1"
  fi
  echo "$(date +%FT%T%z)  $1" >> $LOGFILE
}

function testPyMod {
  # Test if a python module can be loaded by the given binary. Initial intention is for:
  # - testing if the agent module is usable
  # - testing for any modules we would need if we hand off to python for more diagnostics
  # Args 
  #   $1 = python version to use
  #   $2 = module to check
  # Return
  #   0 = module is fine
  #   1 = can't find module (might be present but not for the *given* python)

$1 << EOF

import importlib

def check_module(module_name):
    try:
        importlib.import_module(module_name)
        #return f"The module '{module_name}' exists."
        return 0
    except ModuleNotFoundError:
        #return f"The module '{module_name}' does not exist."
        return 1


exit (check_module("$2"))
EOF

return $?
}
# END function defs

help()
{
   # Display help block
   echo "Azure Agent health check script"
   echo
   echo "Syntax: $0 [-h|-v]"
   echo "options:"
   echo "-h     Print this Help."
   echo "-v     Verbose mode."
   echo
}

# process command-line switches
while getopts ":hv" option; do
   case $option in
      h) # display Help
        help
        exit;;
      v) # turn on verbose mode
        DEBUG=1
        ;;
      \?) # Invalid option
        echo "Error: Invalid option"
        exit;;
   esac
done


function printColorCondition {
# Function to output a colored message, if the current terminal/output supports colors
# Args: state value, a message, and optionally the expected "good" value for 'state'.
#  If the condition matches the expected state, or is 0 by default as that is the 'success'
#   return code for any command, the message will be green.
#  if false, i.e. anything other than the passed good state or 0, then it will be red
#  could add a yellow if we find a good reason, but for now red and green will suffice
# arguments are
# 1 = state value to check
# 2 = string to ouput in color
# 3 = optional 'success' value to substutue for 0 (default when not specified)
  RED='\033[0;31m'
  GREEN='\033[0;32m'
  NC='\033[0m' # No Color, aka reset when we're done coloring the text
  SUCCESS=0 # default 'good' value

  # see if we were passed a success flag
  if [ -n "$3" ] ; then
    SUCCESS=$3
  fi

  if [ $TERM ] ; then
    # echo in color because we're in a terminal
    if [ "$1" == "$SUCCESS" ] ; then
      echo -e $GREEN$2$NC
    else
      echo -e $RED$2$NC
    fi
  else
    # just echo it back out w/o color coding
    echo "$2"
  fi
}

# create the log file/directory once
if [ $EUID == 0 ]; then
  if [ ! -d $LOGDIR ]; then
    mkdir -p $LOGDIR
    logger "$0 created $LOGDIR for logging"
    loggy "Creating $LOGDIR - this could indicate larger problems"
  fi
else
  echo "Not running as root, logging may fail and some checks will not run"
fi

loggy "$0 started by $USER at $STARTTIME"

# do this in the main code body because it doesn't work inside a called function - the function wrapper makes it always false
if [ -t 1 ] ; then
  TERM=true
else
  TERM=false
fi

# distro determination
# Set this from sourcing os-release.  We'll have to be able to distill down all the different 'flavors' and how
#  they refer to themselves, into classes we will evaluate later
case "$ID_LIKE" in
  fedora)
    DISTRO="redhat"
    if (( $(echo "$VERSION_ID < 8" | bc -l) )); then
      DNF="yum"
    fi
    ;;
  debian)
    DISTRO="debian"
    SERVICE="walinuxagent.service"
    PKG="dpkg"
    ;;
  suse)
    DISTRO="suse"
    ;;
  *)
    # The distro doesn't fall into one of the main families above, so just get us the actual value
    if [[ -z $ID_LIKE ]]; then
      DISTRO=$ID
    else
      DISTRO=$ID_LIKE
    fi
  ;;
esac
loggy "Distribution family found to be $DISTRO"


# The base executable for the agent is always waagent, the difference is in how it's called and what python is being
#  called inside the exe... and maybe where it is located
loggy "Checking for agent executable"
EXE=$(which waagent)
if [ -z ${EXE} ] ; then
  # no agent found, maybe change a variable for later reference, but $EXE being 'null' should be good enough
  loggy "No waagent found inside of \$PATH - further tests may be invalid"
else
  loggy "Found waagent at $EXE"
  # pull the top line of the waagent 'executable' out and strip off #! to find out how we call 'python'
  PY=$(head -n1 $EXE | cut -c 3-)
fi

# We could either have one big if-fi structure checking distros and all the checks below in the per-distro blocks, or have these 
#  repeated if-fi blocks for the distro detection in each type of check. Pick your poison

# find the systemd unit for the Azure agent, what package owns it, and what repository that package came from
#  this is to catch any strange installations, and possibly the repo will indicate an appliance/custom image
UNITFILE=$(systemctl show $SERVICE -p FragmentPath | cut -d= -f2)
if [[ $UNITFILE ]]; then
  loggy "Agent systemd unit located at $UNITFILE"
  if [[ $DISTRO == "debian" ]]; then
    OWNER=$($PKG -S $UNITFILE 2> /dev/null | cut -d: -f1)
    # throw away the warning about apt not being a stable interface
    REPO=$(apt list --installed 2> /dev/null| grep $OWNER)
  elif [[ $DISTRO == "suse" ]]; then
    OWNER=$($PKG -q --whatprovides $UNITFILE 2> /dev/null | cut -d: -f1)
    REPO=$(zypper --quiet -s 11 se -i -t package -s $OWNER | grep "^i" | awk '{print $6}')
  elif [[ $DISTRO == "mariner" ]]; then
    OWNER=$($PKG -q --whatprovides $UNITFILE | cut -d: -f1)
  else
    # works for RHEL, suse WIP
    # Mariner does something different for the 'from repo' part
    OWNER=$($PKG -q --whatprovides $UNITFILE | cut -d: -f1)
    REPO=$($DNF info  $OWNER 2>/dev/null | grep -i "From repo" | tr -d '[:blank:]'| cut -d: -f2)
  fi
  loggy "Agent owned by $OWNER and installed from $REPO"

  # Check service/unit status by using the return value from systemctl
  UNITSTAT=$(systemctl is-active $SERVICE)
  UNITSTATRC=$?
  loggy "Unit activity test: $UNITSTAT :: RC:$UNITSTATRC"
  
  # Check python and it's origin

  PYPATH=$(systemctl show $SERVICE -q -p ExecStart | tr " " "\n" | grep python | cut -d "=" -f 2 | uniq)
  # check if we retrieved a python path, which may be false if the unit file only calls waagent instead of calling it as an arg to python
  #  This is most common on RH but may happen elsewhere
  if [[ -z $PYPATH ]]; then
    loggy "python unable to be located from unit definition, probably called from within waagent"
    WAPATH=$(systemctl show $SERVICE -q -p ExecStart | tr " " "\n" | grep waagent | cut -d "=" -f 2 | uniq)
    
    if [ -z ${WAPATH} ] ; then
      # this shouldn't be a valid codepath since waagent wasn't found, and PYPATH comes from the unit
      # no agent found, maybe change a variable for later
      false
    else
      # go search the waagent executable (which is a script) for the python package it will call
      # the first line of the waagent "binary" will be the path to whatever python it uses
      PYBIN=$(head -n1 $WAPATH | cut -d "!" -f 2 | tr " " "\n" | grep python)
      loggy "Python :: $PYBIN found in $WAPATH"
      PYPATH=$(which $PYBIN)
      PY=$(readlink -f $PYPATH)
      loggy "Python from reading waagent script :: $PYPATH derives to :: $PY"
    fi
  else
    # python was in the service definition for ExecStart, so use these variables
    loggy "Python called explicitly from the systemd unit :: $PYPATH"
    PY=$(readlink -f $PYPATH)
  fi
else
  # move more of the vars above into this 'bad variables' stanza to signal that things are failing
  OWNER="systemd"
  REPO="undef"
fi

# quick check and log the version of python
loggy "Checking $PY version"
PYVERSION=$($PY --version)
loggy "Python=$PYVERSION"

# now that we should definitively have a python path, find out who owns it.  If this is still empty, just fail, since waagen't
# didn't eval out, maybe waagent doesn't even exist??
# We will use 'PYPATH' rather than the derived PY to find out where this specific link came from
loggy "Checking who provides $PYPATH"
if [[ $PYPATH ]]; then
  if [[ $DISTRO == "debian" ]]; then
    PYOWNER=$($PKG -S $PYPATH | cut -d: -f1)
    # throw away the warning about apt not being a stable interface
    PYREPO=$(apt list --installed 2> /dev/null| grep $PYOWNER)
  elif [[ $DISTRO == "suse" ]]; then
    PYOWNER=$($PKG -q --whatprovides $PYPATH | cut -d: -f1)
    PYREPO=$(zypper --quiet -s 11 se -i -t package -s $PYOWNER | grep "^i" | awk '{print $6}')
  else
    # works for RHEL, suse WIP
    # Mariner does something different for the 'from repo' part
    PYOWNER=$($PKG -q --whatprovides $PYPATH | cut -d: -f1)
    PYREPO=$($DNF info  $PYOWNER 2>/dev/null | grep -i "From repo" | tr -d '[:blank:]'| cut -d: -f2)
  fi
else
  PYOWNER="python defintion undef - is waagent here?"
  PYREPO="n/a"
fi
loggy "Python owning package : $PYOWNER"
loggy "Package from repository:$PYREPO"

## Python functional checks
# - modules
#   We have *a* python version, as defined in the scripts, so verify if a couple of modules exist
# 'requests'
PYREQ=""
if [ testPyMod($PYPATH, "requests") ]; then
  PYREQ="loaded"
else
  PYREQ="failed to load"
fi
# 'azurelinuxagent.agent'
PYALA=""
if [ testPyMod($PYPATH, "azurelinuxagent.agent") ]; then
  PYALA="loaded"
else
  PYALA="failed to load"
fi

## CONNECTIVITY CHECKS
# -- These are great candidates for moving 'into' python
### There is possibly a better way to do this using curl - see OneNote
# These tests only work 'as root' so lets check if root and not do any of this if not
if [[ $EUID == 0 ]]; then
  loggy "Checking IMDS access"
  # block to use 'system python' to query the IMDS - move this to the end of the script later.
  # we are using the system's python to test regardless
  IMDSHTTPRC=`/usr/bin/env $PY - <<EOF

import requests

imds_server_base_url = "http://169.254.169.254"
instance_api_version = "2021-02-01"
instance_endpoint = imds_server_base_url + \
    "/metadata/instance?api-version=" + instance_api_version
headers = {'Metadata': 'True'}

try:
  r = requests.get(instance_endpoint, headers=headers, timeout=5)
  print(r.status_code)
  r.raise_for_status()
except requests.exceptions.HTTPError as errh:
  print ("Error")
except requests.exceptions.RetryError as errr:
  print ("MaxRetries")
except requests.exceptions.Timeout as errt:
  print ("Timeout")
except requests.exceptions.ConnectionError as errc:
  print ("ConnectErr")
except requests.exceptions.RequestException as err:
  print ("UnexpectedErr")
EOF`

  loggy "Checking wireserver access"
  WIREHTTPRC=`/usr/bin/env $PY - <<EOF

import requests

wire_server_base_url = "http://168.63.129.16"
wire_endpoint = wire_server_base_url + "/?comp=versions"
headers = {'Metadata': 'True'}

try:
  r = requests.get(wire_endpoint, headers=headers, timeout=5)
  print(r.status_code)
  r.raise_for_status()
except requests.exceptions.HTTPError as errh:
  print ("Error")
except requests.exceptions.RetryError as errr:
  print ("MaxRetries")
except requests.exceptions.Timeout as errt:
  print ("Timeout")
except requests.exceptions.ConnectionError as errc:
  print ("ConnectErr")
except requests.exceptions.RequestException as err:
  print ("UnexpectedErr")
EOF`

  # test the "other" wire server port - 
  # this doesn't respond to casual http requests, so for now do a low level nc
  # Since socat is 'new', nc is 'old and deprecated', use them in that order, then fail if neither are here
  # nc -w 1 -z 168.63.129.16 32526
  if [ -f /bin/socat ] ; then
    if ( /bin/socat /dev/null TCP:168.63.129.16:32526,connect-timeout=2 2>/dev/null ) ; then
      loggy "Wireserver:23526 connectivity check: passed"
      WIREEXTPORT="open"
    else
      loggy "Wireserver:23526 connectivity check: failed"
      WIREEXTPORT="fail"
    fi
  elif [ -f /bin/nc ] ; then
    loggy "No socat binary, trying nc"
    if ( nc -w 1 -z 168.63.129.16 32526 ) ; then 
      loggy "Wireserver:23526 connectivity check: passed"
      WIREEXTPORT="open"
    else 
      loggy "Wireserver:23526 connectivity check: failed"
      WIREEXTPORT="fail"
    fi
  else 
    loggy "no socat or nc binary, skipping 32526 test"
    WIREEXTPORT="socat/nc not present - skipped"
  fi
else
  loggy "Skipping wireserver and IMDS checks due to not running as root"
  WIREHTTPRC="Not run as root"
  IMDSHTTPRC="Not run as root"
fi

# Check some agent config items
loggy "Checking agent configuration parameters by running 'waagent --show-configuration'"
if [ -z ${EXE} ] ; then
  # no agent found, maybe change a variable for later, but EXE being 'null' should be good enough
  loggy "skipping config checks, no waagent found"
else
  # -- there is probably a way to reuse this code and pass in the value we want to check, but not doing that right now
  loggy "Checking extension enablement"
  #  We're just reporting the config values
  EXTENS=$($EXE --show-configuration 2> /dev/null | grep -i 'Extensions.Enabled' | tr '[:upper:]' '[:lower:]'| tr -d '[:space:]' | cut -d = -f 2 )
  EXTENSMSG="enabled" # default
  if [ -z $EXTENS ]; then
    # this shouldn't happen unless waagent wasn't located correctly
    EXTENS="undef"
    EXTENSMSG="undef"
  else
    loggy "Extensions.Enabled config : $EXTENS"
    EXTENSMSG="$EXTENS (actual value)"
  fi
  loggy "Checking AutoUpdate"
  AUTOUP=$($EXE --show-configuration 2> /dev/null | grep -i 'AutoUpdate.Enabled' | tr '[:upper:]' '[:lower:]'| tr -d '[:space:]' | cut -d = -f 2 )
  AUTOUPMSG="enabled" # default
  if [ -z $AUTOUP ]; then
    # this shouldn't happen unless waagent wasn't located correctly
    AUTOUP="undef"
    AUTOUPMSG="undef"
  else
    loggy "AutoUpdate.Enabled config : $AUTOUP"
    AUTOUPMSG="$AUTOUP (actual value)"
  fi

fi

# Network checks
# STUFF=$(curl -s -H Metadata:true --noproxy "*" "http://169.254.169.254/metadata/instance/network/interface/0/ipv4/ipAddress/0/?api-version=2023-07-01")
# echo $STUFF | tr { '\n' | tr , '\n' | tr } '\n' | grep "publicIpAdd" | awk  -F'"' '{print $4}'
# What IPs do we have
# what MAC is defined in Azure
# curl -s -H Metadata:true --noproxy "*" "http://169.254.169.254/metadata/instance/network/interface/0/?api-version=2023-07-01" | jq

# other general system checks
# look for any full filesystems, as a courtesy, and because sometimes agent blows up if /var is too full
FULLFS="none"

# Cryptic command to format the output of df, then parse it, and compare to the defined $FSFULLPCENT
DFOUT=$(df -hl --type ext4 --type xfs --type vfat --type btrfs --type ext3 --output=target,pcent | tail -n+2 | while read path pcent ; do pcent=${pcent%\%}; if [ "$pcent" -ge $FSFULLPCENT ]; then   echo "$path=>$pcent"; fi; done)
if [[ $DFOUT ]] ; then
  FULLFS=$DFOUT
fi

# make a log-friendly report, possibly for easy parsing
LOGSTRING=""
LOGSTRING="$LOGSTRING::DISTRO:$DISTRO"
LOGSTRING="$LOGSTRING::SERVICE:$SERVICE"
LOGSTRING="$LOGSTRING::SRVSTAT:$UNITSTAT"
LOGSTRING="$LOGSTRING::SRVRC:$UNITSTATRC"
LOGSTRING="$LOGSTRING::UNIT:$UNITSTAT"
LOGSTRING="$LOGSTRING::UNITPKG:$OWNER"
LOGSTRING="$LOGSTRING::REPO:$REPO"
LOGSTRING="$LOGSTRING::PY:$PY"
LOGSTRING="$LOGSTRING::PYVERS:$PYVERSION"
LOGSTRING="$LOGSTRING::PYPKG:$PYOWNER"
LOGSTRING="$LOGSTRING::PYREPO:$PYREPO"
LOGSTRING="$LOGSTRING::PYREQ:$PYREQ"
LOGSTRING="$LOGSTRING::PYALA:$PYALA"
LOGSTRING="$LOGSTRING::WIRE:$WIREHTTPRC"
LOGSTRING="$LOGSTRING::WIREEXTPORT:$WIREEXTPORT"
LOGSTRING="$LOGSTRING::IMDS:$IMDSHTTPRC"
LOGSTRING="$LOGSTRING::EXTN:$EXTENS"
LOGSTRING="$LOGSTRING::AUTOUP:$AUTOUP"
LOGSTRING="$LOGSTRING::FULLFS:$FULLFS"
loggy $LOGSTRING

# output our report to the 'console'
echo -e "Distro Family:  $DISTRO"
echo -e "Agent Service:  $SERVICE"
echo -e "Agent status:   $(printColorCondition $UNITSTATRC $UNITSTAT)"
echo -e "Unit file:      $UNITFILE"
echo -e "Unit package:   $OWNER"
echo -e "Repo for Unit:  $REPO"
echo -e "python path:    $PY"
echo -e "python version: $PYVERSION"
echo -e "python package: $PYOWNER"
echo -e "python repo:    $PYREPO"
echo -e "python mod req: "$(printColorCondition $PYREQ "$PYREQ" "loaded")
echo -e "python mod ala: "$(printColorCondition $PYALA "$PYALA" "loaded")
echo -e "IMDS HTTP CODE: $(printColorCondition $IMDSHTTPRC $IMDSHTTPRC 200)"
echo -e "WIRE HTTP CODE: $(printColorCondition $WIREHTTPRC $WIREHTTPRC 200)"
echo -e "WIRE EXTN PORT: "$(printColorCondition "$WIREEXTPORT" "$WIREEXTPORT" "open")
# these could either be 'yes|no' or 'true|false'... using the most common defaults for the 'good' string value
echo -e "Extensions:     "$(printColorCondition $EXTENS "$EXTENSMSG" "true")
echo -e "AutoUpgrade:    "$(printColorCondition $AUTOUP "$AUTOUPMSG" "true")
# System checks
echo -e "Volumes >$FSFULLPCENT%:   "$(printColorCondition "$FULLFS" "$FULLFS" "none")


AI_INSTRUMENTATION_KEY="8491943e-98da-4d75-b5b1-de88a6203eb5"
AI_ENDPOINT="https://dc.services.visualstudio.com/v2/track"

jsonPayloadEvent=$(cat <<EOF
{
  "iKey": "${AI_INSTRUMENTATION_KEY}",
  "name": "${0}",
  "time": "${STARTTIME}",
  "data": {
    "baseType": "EventData",
    "baseData": {
      "ver": 2,
      "name": "$0 post test",
      "properties": {
        "vm": "$(hostname)",
        "checks": "\"{\"distro\":\"$DISTRO\",\"IMDSReturn\":\"$IMDSHTTPRC\",\"WireReturn\":\"$WIREHTTPRC\",\"WireExtn\":\"$WIREEXTPORT\",\"DiskSpace\":\"$FSFULLPCENT\"}\""
      }
    }
  }
}
EOF
)
# ^^^ not happy with that really, the 'checks' ends up as a big string, instead of sub objects, but maybe AI has to be that way
        #"checks": {\"distro\":\"${DISTRO}\",\"IMDSReturn\":\"${IMDSHTTPRC}\",\"WireReturn\":\"${WIREHTTPRC}\",\"WireExtn\":\"${WIREEXTPORT}\",\"DiskSpace\":\"${FSFULLPCENT}\"}
CURLARGS="-i "
# intentionally clearing the var, to save the old version for posterity
CURLARGS=""
if [ $DEBUG -gt 0 ]; then
  # not sure what to do here
  true
else
  CURLARGS="$CURLARGS --show-error --silent "
fi
echo "ARGS=:$CURLARGS"
curl $CURLARGS -X POST "${AI_ENDPOINT}" -H "Content-Type: application/json" -d "${jsonPayloadEvent}"
#echo "----"
#echo $jsonPayloadEvent
#echo "----"

loggy "$0 finished at $(date --rfc-3339=seconds)"
