#!/usr/bin/env bash
source /etc/os-release
DEBUG=0
function loggy {
  if [ $DEBUG -gt 0 ]; then
    echo "log-$1"
  fi
}

loggy 1
# function defs
# do this in the main code body because it doesn't work inside a called function - the function wrapper makes it always false
if [ -t 1 ] ; then
  TERM=true
else
  TERM=false
fi

# pass in a state, a message, and optionally the expected "good" value.
#  If the condition matches the expected state, or is 0 by default as that is the 'success'
#   return code, the message will be green.
#  if false, i.e. anything other than the passed state or 0, then it will be red
#  could add a yellow if we find a good reason, but for now red and green will suffice
# arguments are
# 1 = state value to check
# 2 = string to ouput in color
# 3 = optional 'success' value to substutue for 0 (default when not specified)
function printColorCondition {
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

loggy 2
# var defaults
DISTRO="hm-linux"
PY="/usr/bin/python3"
SERVICE="waagent.service"
PKG="rpm"
DNF="dnf"
UNITFILE="/usr/bin/false"
UNITSTAT="undef"
UNITSTATRC=0

# The base executable for waagent is always this, the difference is in how it's called and what python is called inside
EXE=$(which waagent)
if [ -z ${EXE} ] ; then
  # no agent found, maybe change a variable for later
  false
else
  PY=$(head -n1 $EXE | cut -c 3-)
fi
loggy 3
# distro specification
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
    DISTRO="ubuntu"
    SERVICE="walinuxagent.service"
    PKG="dpkg"
    ;;
        suse)
    DISTRO="suse"
    ;;
  *)
    # The distro doesn't fall into one of the main families above, so just get us the actual value
    if [[ -n $ID_LIKE ]]; then
      DISTRO=$ID
    else
      DISTRO=$ID_LIKE
    fi
  ;;
  esac

# # Set some distro-specific modifiers
# if [[ $DISTRO == "redhat" ]]; then
#   if (( $(echo "$VERSION_ID < 8" | bc -l) )); then
#     DNF="yum"
#   fi
#   true;
# elif [[ $DISTRO == "suse" ]]; then
#   true;
# elif [[ $DISTRO == "ubuntu" ]]; then
#   SERVICE="walinuxagent.service"
#   PKG="dpkg"
# fi
loggy 4
# We could either have one big if-fi structure checking distros and all the checks below in the per-distro blocks, or have these repeated if-fi blocks for each type of check.
#  pick your poison

# find the systemd unit for the Azure agent, what package owns it, and what repository it came from
#  this is to catch any strange installations, and possibly the repo will call out an appliance/custom image
UNITFILE=$(systemctl show $SERVICE -p FragmentPath | cut -d= -f2)
loggy 5
if [[ $UNITFILE ]]; then
  if [[ $DISTRO == "ubuntu" ]]; then
    OWNER=$($PKG -S $UNITFILE 2> /dev/null | cut -d: -f1)
    loggy "here5.5"
    # throw away the warning about apt not being a stable interface
    REPO=$(apt list --installed 2> /dev/null| grep $OWNER)
  elif [[ $DISTRO == "suse" ]]; then
    OWNER=$($PKG -q --whatprovides $UNITFILE 2> /dev/null | cut -d: -f1)
    REPO=$(zypper --quiet -s 11 se -i -t package -s $OWNER | grep "^i" | awk '{print $6}')
#  elif [[ $DISTRO == "mariner" ]]; then
#    OWNER=$($PKG -q --whatprovides $UNITFILE | cut -d: -f1)
  else
    # works for RHEL, suse WIP
    # Mariner does something different for the 'from repo' part
    OWNER=$($PKG -q --whatprovides $UNITFILE | cut -d: -f1)
    REPO=$($DNF info  $OWNER 2>/dev/null | grep -i "From repo" | tr -d '[:blank:]'| cut -d: -f2)
  fi
  loggy 6
  # Check service/unit status
  #  I think this was for trimming a newline, but no newline on RH7, maybe this was copypasta?
  #  UNITSTAT=$(systemctl is-active $SERVICE | tr -d [:space:]
  #  will need to handle $? differently if this turns out to be needed, but ignoring it for now to grab the RV

  UNITSTAT=$(systemctl is-active $SERVICE)
  UNITSTATRC=$?
  loggy 7
  # Check python and it's origin
  # this would work if there is an agent process running
  #   dnf info $(rpm -q --whatprovides $(realpath /proc/$(systemctl show --property MainPID --value waagent)/exe))
  # but we have to deal with the fact that the service might be dying / not running
  PYPATH=$(systemctl show $SERVICE -q -p ExecStart | tr " " "\n" | grep python | cut -d "=" -f 2 | uniq)
  # check if we got a python path, which may be false if the service only calls waagent instead of calling it as an arg to python
  #  This is most common on RH but may happen elsewhere
  loggy 8
  if [[ -z $PYPATH ]]; then
    WAPATH=$(systemctl show $SERVICE -q -p ExecStart | tr " " "\n" | grep waagent | cut -d "=" -f 2 | uniq)
    loggy 9
    if [ -z ${WAPATH} ] ; then
      # no agent found, maybe change a variable for later
      false
    else
      # go search the waagent executable (which is a script) for the python package it will call
      # the first line of the waagent "binary" will be the path to whatever python it uses
      PYPATH=$(head -n1 $WAPATH | cut -d "!" -f 2)
    fi
  fi
else
  OWNER="systemd"
  REPO="undef"
  # move more of the vars above into this 'bad variables' stanza
fi

# now that we should definitively have a python path, find out who owns it.  If this is still empty, just fail, since waagen't
# didn't eval out, maybe waagent doesn't even exist??
loggy 10
if [[ $PYPATH ]]; then
  if [[ $DISTRO == "ubuntu" ]]; then
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
  PYOWNER="undef - is waagent here?"
  PYREPO="n/a"
fi

# block to use 'system python' to query the IMDS - move this to the end of the script later.
# we are using the system's python to test regardless
IMDSHTTPRC=`/usr/bin/env $PY - <<EOF

import json

import requests

# python functions
def api_call(endpoint):
  headers = {'Metadata': 'True'}

#  response=requests.get(endpoint, headers=headers, proxies=proxies, timeout=5)
  response=requests.get(endpoint, headers=headers, timeout=5)
  return response
  json_obj = response.json()
  return json_obj

def main():
    # Instance provider API call
    imdsresp = api_call(instance_endpoint)
    print(imdsresp.status_code)

imds_server_base_url = "http://169.254.169.254"
instance_api_version = "2021-02-01"
instance_endpoint = imds_server_base_url + \
    "/metadata/instance?api-version=" + instance_api_version

attested_api_version = "2021-02-01"
attested_nonce = "1234576"
attested_endpoint = imds_server_base_url + "/metadata/attested/document?api-version=" + \
    attested_api_version + "&nonce=" + attested_nonce

# Proxies must be bypassed when calling Azure IMDS
# commenting this out from example code because we want to know if a proxy exists in this script
#proxies = {
#    "http": None,
#    "https": None
#}

main()

EOF`

WIREHTTPRC=`/usr/bin/env $PY - <<EOF

import requests

imds_server_base_url = "http://168.63.129.16"
instance_endpoint = imds_server_base_url + "/?comp=versions"
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


# Check some agent config items
#  Get only the first char of the "Extensions.Enabled" value, and lowercase it, since it could be y/Y/yes/Yes
EXTENS=$(grep -i Extensions.Enabled /etc/waagent.conf | tr '[:upper:]' '[:lower:]'| cut -d = -f 2 | cut -c1-1 )
EXTENSMSG="enabled" # default
if [ -z $EXTENS ]; then
  EXTENS="undef"
  EXTENSMSG="undef"
else
  if [ $EXTENS == "n" ]; then
    EXTENSMSG="$EXTENS (actual value)";
  fi
fi


# output our report
echo -e "Distro Family:  $DISTRO"
echo -e "Agent Service:  $SERVICE"
echo -e "Agent status:   $(printColorCondition $UNITSTATRC $UNITSTAT)"
echo -e "Unit file:      $UNITFILE"
echo -e "Unit package:   $OWNER"
echo -e "Repo for Unit:  $REPO"
echo -e "python path:    $PYPATH"
echo -e "python package: $PYOWNER"
echo -e "python repo:    $PYREPO"
echo -e "IMDS HTTP CODE: $(printColorCondition $IMDSHTTPRC $IMDSHTTPRC 200)"
echo -e "WIRE HTTP CODE: $(printColorCondition $WIREHTTPRC $WIREHTTPRC 200)"
echo -e "Extensions:     $(printColorCondition $EXTENS $EXTENSMSG y)"


## Example code for printing in color and testing for outputting to the terminal
# RED='\033[0;31m'
# GREEN='\033[0;32m'
# NC='\033[0m' # No Color


# if [ -t 1 ] ; then
#     echo -e $GREEN stdout is a terminal $NC
# else
#     echo -e $RED stdout is not a terminal $NC
# fi
# echo " || "
# if [ -t 0 ] ; then
#     echo -e $GREEN stdin is a terminal $NC
# else
#     echo -e $RED stdin is not a terminal $NC
# fi