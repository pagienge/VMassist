print("Notice:: This python script is in heavy development\n")

import argparse
import os
import logging
import subprocess
import re
# for os-release (initially)
import csv
import pathlib


from pprint import pprint

### COMMAND LINE ARGUMENT HANDLING
parser = argparse.ArgumentParser(
    description="stuff"
)
parser.add_argument('-b', '--bash', required=True, type=str)
parser.add_argument('-d', '--debug', action='store_true')
parser.add_argument('-l', '--log', type=str, required=False, default='/var/log/azure/'+os.path.basename(__file__)+'.log')
parser.add_argument('-t', '--noterm', action='store_true') # mainly used for coloring output
args=parser.parse_args()

# example bash value:
# bash='DISTRO=redhat|SERVICE=waagent.service|SRVSTAT=active|SRVRC=0|UNIT=active|UNITPKG=WALinuxAgent-2.7.0.6-8.el8_8.noarch|REPO=rhui-rhel-8-for-x86_64-appstream-rhui-rpms|PY=/usr/libexec/platform-python3.6|PYVERS=3.6.8|PYPKG=platform-python-3.6.8-51.el8.x86_64|PYREPO=rhui-rhel-8-for-x86_64-baseos-rhui-rpms|PYCOUNT=1|PYREQ=loaded|PYALA=loaded|WIRE=200|WIREEXTPORT=open|IMDS=200|EXTN=true|AUTOUP=true|FULLFS=/:16'
bashArgs = dict(inStr.split('=') for inStr in args.bash.split("|"))
# pprint(parser.parse_args())
# any value can be extracted with 
#   bashArgs.get('NAME', "DefaultString")
#  ex:
#   bashArgs.get('PY',"N/A")
### END COMMAND LINE ARGUMENT HANDLING

### UTILITY FUNCTIONS
def colorPrint(color, strIn):
    retVal=""
    if ( args.noterm ):
        retVal=strIn
#        print(strIn)
    else:
        retVal=color+"{} \033[00m".format(strIn)
#        print(color+"{} \033[00m".format(strIn))
    return retVal
def cRed(strIn): return colorPrint("\033[91m", strIn)
def cGreen(strIn): return colorPrint("\033[92m", strIn)
def cYellow(strIn): return colorPrint("\033[93m", strIn)
def cBlack(strIn): return colorPrint("\033[98m", strIn)

### END UTIL FUNCS
### MAIN CODE
#### Global vars setup
logger = logging.getLogger(__name__)
logging.basicConfig(format='%(asctime)s %(message)s', filename=args.log, level=logging.DEBUG)

# parse out os-release and put the values into a dict
path = pathlib.Path("/etc/os-release")
with open(path) as stream:
  reader = csv.reader(filter(lambda line: line.strip(), stream), delimiter="=")
  os_release = dict(reader)

# holding dict for all the binaries we will valiate
bins={}

#### END Global vars
#### Main logic functions
def validateBin(binPath):
  # usage: pass in a binary to check, the following will be determined
  #  - absolute path (dereference links)
  #  - provided by what package
  #  - what repo provides the package
  #  - version for the package or binary if possible
  # load up os-release into a dict for later reference
  logger.info("Validating " + binPath)
  thisBin={"exe":binPath}
  #
  osrID=os_release.get("ID_LIKE", os_release.get("ID"))
  if (osrID == "debian"):
    try:
      # Find what package owns the binary
      dpkg=subprocess.check_output("dpkg -S " + binPath, shell=True).decode().strip()
      thisBin["pkg"]=dpkg.split(":")[0]
      #
      # find what repository the package came from
      try:
        aptOut=subprocess.check_output("apt-cache show --no-all-versions " + thisBin["pkg"] , shell=True).decode().strip()
        thisBin["repo"]=re.search("Origin.*",aptOut).group()
      except:
        # we didn't get a match, probably a manual install (dkpg)
        thisBin["repo"]="not from a repo"
    #
    except subprocess.CalledProcessError as e:
      # binary not found or may be source installed (no pkg)
      thisBin["pkg"]="no file or owning pkg: " + e
      thisBin["repo"]="n/a"
  #
  elif ( osrID == "fedora"):
    try:
      rpm=subprocess.check_output("rpm -q --whatprovides " + binPath, shell=True).decode().strip()
      thisBin["pkg"]=rpm
      try:
        # expand on this to make the call to 'dnf' do yum on old things, for old RH flavors, maybe
        dnfOut=subprocess.check_output("dnf info " + rpm, shell=True).decode().strip()
        thisBin["repo"]=re.search("Repository.*",dnfOut).group().strip()
      except:
        # we didn't get a match, probably a manual install (rpm)
        thisBin["repo"]="not from a repo"
    except subprocess.CalledProcessError as e:
      thisBin["pkg"]="no file or owning pkg: " + e
      thisBin["repo"]="n/a"
  elif ( osrID == "suse"):
    try:
      rpm=subprocess.check_output('rpm -q --queryformat %{NAME} --whatprovides ' + binPath, shell=True).decode()
      thisBin["pkg"]=rpm
      try:
        # options:
        zyppOut=subprocess.check_output("zypper --quiet --no-refresh info " + rpm, shell=True).decode().strip()
        thisBin["repo"]=re.search("Repository.*",zyppOut).group().split(":")[1].strip()
      except:
        # we didn't get a match, probably a manual install (rpm)
        thisBin["repo"]="not from a repo"
    except subprocess.CalledProcessError as e:
      thisBin["pkg"]="no file or owning pkg: " + e
      thisBin["repo"]="n/a"
  elif ( osrID == "mariner" or osrID == "azurelinux"):
    try:
      rpm=subprocess.check_output('rpm -q --queryformat %{NAME} --whatprovides ' + binPath, shell=True).decode()
      thisBin["pkg"]=rpm
      try:
        # options:
        zyppOut=subprocess.check_output("tdnf --installed info " + rpm, shell=True).decode().strip()
        thisBin["repo"]=re.search("Repo.*",zyppOut).group().split(":")[1].strip()
      except:
        # we didn't get a match, probably a manual install (rpm)
        thisBin["repo"]="not from a repo"
    except subprocess.CalledProcessError as e:
      thisBin["pkg"]="no file or owning pkg: " + e
      thisBin["repo"]="n/a"

  else:
    print("Unable to determine OS family from os-release")
    thisBin["pkg"]="packaging system unknown"
    thisBin["repo"]="n/a"
  #
  logString = binPath + " owned by package '" + thisBin["pkg"] + "' from repo '" + thisBin["repo"] + "'"
  if ( args.debug ):
    pprint(logString)
  logger.info(logString)
  bins[binPath]=thisBin

#### END main logic funcs
#### 

#print(cGreen("Green"))
#redText=cRed("red")
#print("Red text is " + redText)


# ToDo list:
# LOGSTRING="DISTRO=$DISTRO"
# LOGSTRING="$LOGSTRING|SERVICE=$SERVICE"
# LOGSTRING="$LOGSTRING|SRVSTAT=$UNITSTAT"
# LOGSTRING="$LOGSTRING|SRVRC=$UNITSTATRC"
# LOGSTRING="$LOGSTRING|UNIT=$UNITSTAT"
# LOGSTRING="$LOGSTRING|UNITPKG=$OWNER"
# LOGSTRING="$LOGSTRING|REPO=$REPO"
# LOGSTRING="$LOGSTRING|PY=$PY"
# LOGSTRING="$LOGSTRING|PYVERS=$PYVERSION"
# LOGSTRING="$LOGSTRING|PYPKG=$PYOWNER"
# LOGSTRING="$LOGSTRING|PYREPO=$PYREPO"
# LOGSTRING="$LOGSTRING|PYCOUNT=$PYCOUNT"
# LOGSTRING="$LOGSTRING|PYREQ=$PYREQ"
# LOGSTRING="$LOGSTRING|PYALA=$PYALA"
# LOGSTRING="$LOGSTRING|WIRE=$WIREHTTPRC"
# LOGSTRING="$LOGSTRING|WIREEXTPORT=$WIREEXTPORT"
# LOGSTRING="$LOGSTRING|IMDS=$IMDSHTTPRC"
# LOGSTRING="$LOGSTRING|EXTN=$EXTENS"
# LOGSTRING="$LOGSTRING|AUTOUP=$AUTOUP"
# LOGSTRING="$LOGSTRING|FULLFS=$FULLFS"

logger.info("Python script started:"+os.path.basename(__file__))
logger.info("args were "+str(parser.parse_args()))

validateBin("/usr/sbin/waagent")
validateBin("/usr/bin/python3")
validateBin("/usr/bin/openssl")

pprint(bins)
logger.info("Python ended")