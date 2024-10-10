print("Notice:: This python script is in heavy development\n")

import argparse
import os
import sys
import socket
import requests
import logging
import subprocess
import re
# for os-release (initially)
import csv
import pathlib
# network checking
import socket
# disk stuff - moved down to a try block near the code
#import psutil

# probably only for development, strip later when all the pprint debug calls are gone
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
### UTILS
#### UTIL VARs and OBJs
logger = logging.getLogger(__name__)
logging.basicConfig(format='%(asctime)s %(message)s', filename=args.log, level=logging.DEBUG)
# add the 'to the console' flag to the logger
if ( args.debug ):
  logging.getLogger().addHandler(logging.StreamHandler(sys.stdout))
  logger.info("Debug on")
#### END UTIL VARS
#### UTIL FUNCTIONS
def colorPrint(color, strIn):
  retVal=""
  if ( args.noterm ):
    retVal=strIn
  else:
    retVal=color+"{} \033[00m".format(strIn)
#        print(color+"{} \033[00m".format(strIn))
  return retVal
def cRed(strIn): return colorPrint("\033[91m", strIn)
def cGreen(strIn): return colorPrint("\033[92m", strIn)
def cYellow(strIn): return colorPrint("\033[93m", strIn)
def cBlack(strIn): return colorPrint("\033[98m", strIn)
def colorString(strIn, redVal="dead", greenVal="active", yellowVal="inactive"):
  # ordered so that errors come first, then warnings and eventually "I guess it's OK"
  if redVal.lower() in strIn.lower():
    return cRed(strIn)
  elif yellowVal.lower() in strIn.lower():
    return cYellow(strIn)
  elif greenVal.lower() in strIn.lower():
    return cGreen(strIn)
  else:
    return cBlack(strIn)

#### END UTIL FUNCS
### END UTILS
### MAIN CODE
#### Global vars setup
fullPercent=90
# debug var
fullPercent=20
# parse out os-release and put the values into a dict
path = pathlib.Path("/etc/os-release")
with open(path) as stream:
  reader = csv.reader(filter(lambda line: line.strip(), stream), delimiter="=")
  os_release = dict(reader)
osrID=os_release.get("ID_LIKE", os_release.get("ID"))

# holding dicts for all the different things we will valiate
bins={}
services={}
checks={}
findings={}
# took out the part to put some default findings in, delete them if we find something bad

#### END Global vars
#### Main logic functions
def validateBin(binPathIn):
  # usage: pass in a binary to check, the following will be determined
  #  - absolute path (dereference links)
  #  - provided by what package
  #  - what repo provides the package
  #  - version for the package or binary if possible
  # output object:
  # load up os-release into a dict for later reference
  logger.info("Validating " + binPathIn)
  # we need to store the passed value in case of exception with the dereferenced path
  binPath=binPathIn
  realBin=os.path.realpath(binPath)
  if ( binPath != realBin ):
    logger.info(f"Link found: {binPath} points to {realBin}, verify outputs if this returns empty data")
    binPath=realBin
  thisBin={"exe":binPathIn}
 
  if (osrID == "debian"):
    noPkg=False # extra exception flag, using pure try/excepts is difficult to follow
    try:
      # Find what package owns the binary
      thisBin["pkg"]=subprocess.check_output("dpkg -S " + binPath, shell=True, stderr=subprocess.DEVNULL).decode().strip().split(":")[0]
    except:
      logger.info(f"issue validating {binPath}, reverting to original path: {binPathIn}")
      try:
        thisBin["pkg"]=subprocess.check_output("dpkg -S " + binPathIn, shell=True, stderr=subprocess.DEVNULL).decode().strip().split(":")[0]
      except subprocess.CalledProcessError as e:
        logger.info(f"All attempts to validate {binPathIn} have failed. Likely a rogue file: {e.output}")
        noPkg=True
    if not noPkg:
      # find what repository the package came from
      try:
        aptOut=subprocess.check_output("apt-cache show --no-all-versions " + thisBin["pkg"] , shell=True, stderr=subprocess.DEVNULL).decode().strip()
        thisBin["repo"]=re.search("Origin.*",aptOut).group()
      except subprocess.CalledProcessError as e:
        # we didn't get a match, probably a manual install (dkpg) or installed from source
        logger.info(f"package {thisBin['pkg']} does not appear to have come from a repository")
        thisBin["repo"]="no repo"
    else: 
      # binary not found or may be source installed (no pkg)
      thisBin["pkg"]=f"no file or owning pkg for {binPathIn}"
      thisBin["repo"]="n/a"
  elif ( osrID == "fedora"):
    try:
      rpm=subprocess.check_output("rpm -q --whatprovides " + binPath, shell=True, stderr=subprocess.DEVNULL).decode().strip()
      thisBin["pkg"]=rpm
      try:
        # expand on this to make the call to 'dnf' do yum on old things, for old RH flavors, maybe
        dnfOut=subprocess.check_output("dnf info " + rpm, shell=True, stderr=subprocess.DEVNULL).decode().strip()
        # Repo line should look like "From repo   : [reponame]" so clean it up
        thisBin["repo"]=re.search("From repo.*",dnfOut).group().strip().split(":")[1].strip()
      except:
        # we didn't get a match, probably a manual install (rpm) or from source
        thisBin["repo"]="not from a repo"
    except subprocess.CalledProcessError as e:
      thisBin["pkg"]="no file or owning pkg: " + e
      thisBin["repo"]="n/a"
  elif ( osrID == "suse"):
    try:
      rpm=subprocess.check_output('rpm -q --queryformat %{NAME} --whatprovides ' + binPath, shell=True, stderr=subprocess.DEVNULL).decode()
      thisBin["pkg"]=rpm
      try:
        # options:
        zyppOut=subprocess.check_output("zypper --quiet --no-refresh info " + rpm, shell=True, stderr=subprocess.DEVNULL).decode().strip()
        thisBin["repo"]=re.search("Repository.*",zyppOut).group().split(":")[1].strip()
      except:
        # we didn't get a match, probably a manual install (rpm) or from source
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
        # we didn't get a match, probably a manual install (rpm) or from source
        thisBin["repo"]="not from a repo"
    except subprocess.CalledProcessError as e:
      thisBin["pkg"]="no file or owning pkg: " + e
      thisBin["repo"]="n/a"
  else:
    print("Unable to determine OS family from os-release")
    thisBin["pkg"]="packaging system unknown"
    thisBin["repo"]="n/a"
  logString = binPath + " owned by package '" + thisBin["pkg"] + "' from repo '" + thisBin["repo"] + "'"
  logger.info(logString)
  bins[binPathIn]=thisBin
def checkService(unitName, package=False):
  # take in a unit file and check status, enabled, etc.
  # output object:

  logger.info("Service/Unit check " + unitName)

  thisSvc={"svc":unitName}
  unitStat=0          # default service status return, we'll set this based on the 'systemctl status' RC
  thisSvc["status"]="undef" # this will get changed somewhere
  # First off, let us check if the unit even exists
  try:
    throwawayVal=subprocess.check_output(f"systemctl status {unitName}", shell=True)
    #0 program is running or service is OK <<= default value of unitStat
    #1 program is dead and /var/run pid file exists
    #2 program is dead and /var/lock lock file exists
    #3 program is not running
    #4 program or service status is unknown
    #5-99  reserved for future LSB use
    #100-149   reserved for distribution use
    #150-199   reserved for application use
    #200-254   reserved
  except subprocess.CalledProcessError as sysctlErr:
    # we will be referencing this return code later, assuming it's not 4 - see table above
    unitStat=sysctlErr.returncode
    if ( unitStat == 4 ):
      thisSvc["status"]="nonExistantService"
    else:
      logger.info(f"Service {unitName} status returned unexpected value: {sysctlErr.output} with text: {sysctlErr.output}")
  # Unit was determined to exist (not rc=4), so lets validate the service status and maybe some other files
  if ( unitStat < 4 ):
    # Process the configured, active and substate for the service.  Active/Sub could be inactive(dead) in an interactive console
    #  This can be done from systemctl show [service] --property=[UnitFileState|ActiveState|SubState]
    config=subprocess.check_output(f"systemctl show {unitName} --property=UnitFileState",shell=True).decode().strip().split("=")[1]
    active=subprocess.check_output(f"systemctl show {unitName} --property=ActiveState",shell=True).decode().strip().split("=")[1]
    sub=subprocess.check_output(f"systemctl show {unitName} --property=SubState",shell=True).decode().strip().split("=")[1]
    thisSvc["config"]=config
    # make the 'status' look like the output of `systemctl status`
    thisSvc["status"]=f"{active}({sub})"

    # more integrety checks based on digging into the files
    thisSvc["path"]=subprocess.check_output(f"systemctl show {unitName} -p FragmentPath", shell=True).decode().strip().split("=")[1]
    # Which python does the service call?
    # # dive into the file in 'path' and logic out what python is being called for validations
    # who owns it... maybe?
    if ( package ):
      # We need to process the owner and path of the unit if (package) was set by the caller
      logger.info(f"Checking owners for unit: {unitName} using validateBins")
      # No need to re-code all this, just call validateBin(binName)
      validateBin(thisSvc["path"])
      thisSvc["pkg"]=bins[thisSvc["path"]]['pkg']
      thisSvc["repo"]=bins[thisSvc["path"]]['repo']
      # get rid of this extra entry in bins caused by calling validateBins()
      del bins[thisSvc["path"]]
    else:
      logger.info(f"package details for {unitName} not requested, skipping")
      pass
  else:
    #set some defaults when the unit wasn't here
    pass

  unitFile=subprocess.check_output(f"systemctl show {unitName} -p FragmentPath", shell=True).decode().strip().split("=")[1]
  logString = unitName + " unit file found at " + thisSvc["path"] + "owned by package '" + thisSvc["pkg"] + "from repo: " + thisSvc["repo"]
  logger.info(logString)
  services[unitName]=thisSvc
  
def checkHTTPURL(urlIn):
  checkURL = urlIn
  headers = {'Metadata': 'True'}
  returnString=""
  try:
    r = requests.get(checkURL, headers=headers, timeout=5)
    returnString=r.status_code
    r.raise_for_status()
  except requests.exceptions.HTTPError as errh:
    returnString=f"Error:{r.status_code}"
  except requests.exceptions.RetryError as errr:
    returnString=f"MaxRetries"
  except requests.exceptions.Timeout as errt:
    returnString=f"Timeout"
  except requests.exceptions.ConnectionError as errc:
    returnString=f"ConnectErr"
  except requests.exceptions.RequestException as err:
    returnString=f"UnexpectedErr"
  return returnString
def isOpen(ip, port):
  # return true/false if the remote port is/isn't listening, only takes an IP, no DNS is done
  s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
  s.settimeout(2)
  try:
    is_open = s.connect_ex((ip, int(port))) == 0 # True if open, False if not
    if is_open:
      s.shutdown(socket.SHUT_RDWR)
    return True
  except Exception:
    is_open = False
  s.close()
  return is_open
#### END main logic funcs

#### START main processing flow

# ToDo list from bash logstring: (delete when completed)
# LOGSTRING="$LOGSTRING|SERVICE=$SERVICE"
# LOGSTRING="$LOGSTRING|PY=$PY"
# LOGSTRING="$LOGSTRING|PYVERS=$PYVERSION"
# LOGSTRING="$LOGSTRING|PYCOUNT=$PYCOUNT"
# LOGSTRING="$LOGSTRING|PYREQ=$PYREQ"
# LOGSTRING="$LOGSTRING|PYALA=$PYALA"

logger.info("Python script started:"+os.path.basename(__file__))
logger.info("args were "+str(parser.parse_args()))

# We'll use the 'bash' arguments from the bash wrapper to seed this script
waaServiceIn=bashArgs.get('SERVICE', "waagent.service") # this may differ per-distro, but offer a default
pythonIn=bashArgs.get('PY', "/usr/bin/python3")
waaBin=subprocess.check_output("which waagent", shell=True, stderr=subprocess.DEVNULL).decode().strip()
logger.info(f"using waagent location {waaBin}")

# Check services and binaries

checkService(waaServiceIn, package=True)
validateBin(pythonIn)
# PoC for right now to show what we can do, also because changing SSL can cause problems for some extensions
validateBin("/usr/bin/openssl")
validateBin("/sbin/waagent") # just to create another easy-to-check test
# Don't worry about SSHD initially until we get to more 'best practice' checks
#checkService("sshd.service", package=True)

## turn service/bins checks into 'checks' and 'findings'
### Binaries
#### string for the console report
binReportString=""
for binName in bins:
  checks[bins[binName]['exe']] = {'check': bins[binName]['exe'],
                                  'description': f"Binary check of {bins[binName]['exe']}",
                                  'value': f"Package:{bins[binName]['pkg']}, source:{bins[binName]['repo']}"
                                  }
  # check for alarms in the binaries and create findings as needed
  # - is the path include questionable areas - local, home, opt - these aren't "normal"
  if ( re.search(r"local", bins[binName]['exe']) or 
       re.search(r"opt", bins[binName]['exe']) or
       re.search(r"home", bins[binName]['exe'])):
    # this is bad, create a findings from this check
    findings[f"bp:{bins[binName]['exe']}"]={
      'description': f"binpath:{bins[binName]['exe']}",
      'status': "Path includes questionable directories",
      'type': "bin"
    }
    logger.warn(f"Checking path of {bins[binName]['exe']} found in a non-standard location")
    binReportString+=f"{cYellow(bins[binName]['exe'])} => check location\n"
  # - is the repository uncommon
  repoBad=False
  if osrID == "debian":
    # check if the repository is expected, this should usually say "Origin: Ubuntu"
    if ( not re.search(r"Origin: Ubuntu", bins[binName]['repo'])):
      repoBad=True
  elif ( osrID == "fedora" or osrID == "azurelinux" ) : 
    # check if the repository is either @System (initial install for RHEL or AL) or includes 'rhui' or 'azurelinux'
    if ( not (re.search(r"@System", bins[binName]['repo']) or 
              re.search(r"anaconda", bins[binName]['repo']) or
              re.search(r"rhui", bins[binName]['repo']) or
              re.search(r"azurelinux", bins[binName]['repo'])
             )):
      repoBad=True
  elif osrID == "suse":
    # check if the repository includes 'SLE-Module' or 'SUSE'
    if ( not re.search(r"SLE-Module", bins[binName]['repo'])):
      repoBad=True
  # all distro-specific checks finished, report if needed
  if ( repoBad ):
    findings[f"bs:{bins[binName]['exe']}"]={
      'description': f"binsource:{bins[binName]['exe']}",
      'status': f"Binary came from unusual source: {bins[binName]['repo']}",
      'type': "bin"
    }
    logger.warn(f"Checking {bins[binName]['exe']} found sourced from the repo {bins[binName]['repo']}")
    binReportString+=f"{bins[binName]['exe']} => {cRed(bins[binName]['repo'])} - verify repository\n"
if (len(binReportString) == 0 ):
  binReportString=cGreen("No issues with checked binaries")
### Services/Units
svcReportString=""
for svcName in services:
  if ( not re.search(r"running", services[svcName]['status']) ):
    findings[f"ss:{services[svcName]['svc']}"]={
      'description': f"service:{services[svcName]['svc']}",
      'status': f"Service not in 'running' state: {services[svcName]['status']}",
      'type': "svc"
    }
    logger.warn(f"Checking {services[svcName]['svc']} found in state {services[svcName]['status']}")
    svcReportString+=f"{services[svcName]['svc']} => {cRed(services[svcName]['status'])} - check logs\n"
  if ( not re.search(r"enabled", services[svcName]['config']) ):
    findings[f"sc:{services[svcName]['svc']}"]={
      'description': f"service:{services[svcName]['svc']}",
      'status': f"Service not enabled: {services[svcName]['config']}",
      'type': "svc"
    }
    logger.warn(f"Checking {services[svcName]['svc']} not enabled: {services[svcName]['config']}")
    svcReportString+=f"{services[svcName]['svc']} => {cRed(services[svcName]['config'])} - check config\n"
if (len(svcReportString) == 0 ):
  svcReportString=cGreen("No issues with checked services")

  # print(f"Analysis of unit : {services[svcName]['svc']}:")
  # print(f"  Owning pkg     : {services[svcName]['pkg']}" )
  # print(f"  Repo for pkg   : {services[svcName]['repo']}" )
  # print( "  run state      : "+colorString(services[svcName]['status'], redVal="dead", greenVal="active"))
  # print( "  config state   : "+colorString(services[svcName]['config'], redVal="disabled", greenVal="enabled"))


# Connectivity checks
## Wire server
wireCheck=checkHTTPURL("http://168.63.129.16/?comp=versions")
thisCheck={"check":"wire 80", "value":wireCheck}
checks['wire']=thisCheck
if wireCheck != 200:
  findings['wire80']={
    'description': 'WireServer:80',
    'status': wireCheck,
    'type': "conn"
  }
# clean up, this shouldn't remove the 'checks' reference, just the temp object
del(thisCheck)
## Wire server "extension" port
wireExt=isOpen("168.63.129.16",32526)
thisCheck={"check":"wire 23526", "value":wireExt}
checks['wireExt']=thisCheck
if not wireExt :
  findings['wire23526']={
    'description': 'WireServer:32526',
    'status': wireExt,
    'type': "conn"
  }
# clean up, this shouldn't remove the 'checks' reference, just the temp object
del(thisCheck)
## IMDS
imdsCheck=checkHTTPURL("http://169.254.169.254/metadata/instance?api-version=2021-02-01")
thisCheck={"check":"imds 443", "value":imdsCheck}
checks['imds']=thisCheck
if imdsCheck != 200:
  findings['imds']={
    'description': 'IMDS',
    'status': imdsCheck,
    'type': "conn"
  }
# clean up, this shouldn't remove the 'checks' reference, just the temp object
del(thisCheck)

# OS checks
## Agent config
waaConfigOut=subprocess.check_output(f"{waaBin} --show-configuration", shell=True, stderr=subprocess.DEVNULL).decode().strip().split('\n')
waaConfig={}
# put all output from the config command into a KVP
for line in waaConfigOut:
  key, value = line.split('=', 1)
  waaConfig[key.strip()] = value.strip()
checks['waaExt']={"check":"WAA Extension", "value":waaConfig['Extensions.Enabled']}
if ( checks['waaExt']['value'] != 'True' ):
  findings['waaExt']={'status': checks['waaExt']['value'], 'description':"Extensions are disabled in WAA config"}
checks['waaUpg']={"check":"WAA AutoUpgrade", "value":waaConfig['AutoUpdate.Enabled']}
if ( checks['waaUpg']['value'] != 'True' ):
  findings['waaUpg']={'status': checks['waaUpg']['value'], 'description':"Agent extension handler auto-upgrade is disabled in WAA config"}

# Checks against disks and objects
## results of disk space checks
### seed checks with a 'no problems' message, we'll reset it when we find one
checks['fullFS']={"check":"fullFS", "description": f"filesystem util over {fullPercent}%", "none":f"No filesystems over {fullPercent}% util"}
diskFind=""
## find the device 'id' for checking if the extension directory is 'noexec'
vlwaDev=os.stat("/var/lib/waagent").st_dev

mounts=[]

# only check these filesystem types ext4,xfs,vfat,btrfs,ext3
findmnt=subprocess.check_output("findmnt --evaluate -nb -o TARGET,SOURCE,FSTYPE,OPTIONS,USE% --pairs -t=ext2,ext3,ext4,btrfs,xfs,vfat", shell=True, stderr=subprocess.DEVNULL).decode().strip().split("\n")

for fm in findmnt:
  pairs = fm.split()
  dictTemp={}
  for pair in pairs:
    key, value = pair.split('=',1)
    dictTemp[key] = value.strip('"%')
  mounts.append(dictTemp)

# this was initially done in psutils:
#  mounts = psutil.disk_partitions()
#  but was found that certain distros do not include psutils in their marketplace images, so re-wrote with generic python code
for m in mounts:
  logger.info(f"Checking {m['SOURCE']} mounted at {m['TARGET']}")
  # the following hack brought to you by SLES, where USE% is instead USE_PCT
  pcent=0
  if ( 'USE%' in m ):
    pcent = m['USE%']
  elif ( 'USE_PCT' in m ):
    pcent = m['USE_PCT']

  if int(pcent) >= fullPercent:
    logger.warning(f"Filesystem utilization for {m['TARGET']} is over {fullPercent}: {pcent}")
    # delete the 'default empty set' wording in 'checks' for fullFS, because we found a disk over the util threshold
    if 'none' in checks["fullFS"]:
      checks['fullFS']={'check': 'fullFS', 'description':f'Look for filesystems utilized more than {fullPercent}','value':'see findings for details'}
      findings['fullFS']={}
    if 'status' in findings['fullFS']:
      findings['fullFS']['status'] = f"{findings['fullFS']['status']}, {m['TARGET']}:{pcent}"
    else:
      findings['fullFS']={'description': f"Filesystems over{fullPercent}",
                           'status': f"{m['TARGET']}:{pcent}",
                           'type':'os'
      }
  # check if this mount (m) is the one holding /var/lib/waagent, if so we will  want to check to see if the mount options include 'noexec'
  if ( os.stat(m['TARGET']).st_dev == vlwaDev ):
    logger.info(f"Found /var/lib/waagent based in filesystem {m['TARGET']} on device {m['SOURCE']}, checking mount options")
    # create the 'checks' data describing this
    checks['noexec']={
      'description': f"Checking mount options for noexec on {m['SOURCE']}",
      'check': 'noexec',
      'value': m['TARGET']
    }
    # add the 'findings' data if it's bad
    if (re.search("noexec", m['OPTIONS'])):
      # Found noexec so flag it
      logger.error(f"mountpoint {m['TARGET']} mounted with 'noexec'")
      findings['noexec']={
        'description':"Found /var/lib/waagent with noexec bit set",
        'status':True
      }

## Networking
### TODO: static IP
### TODO: MAC mismatch

# END ALL CHECKS

# START OUTPUT
print("------ VMassist.py results ------")
print("Please see https://github.com/pagienge/VMassist/blob/main/docs/tux.md for information about any issues in the above output")
print(f"OS family        : {osrID}")
if 'none' in checks["fullFS"]:
  print(f"Disk util > {fullPercent}%  : {checks['fullFS']['none']}")
else:
  print(f"Disk util > {fullPercent}%  : {findings['fullFS']['status']}")
# TODO: clean up and verify color on all core checks - wire server, waagent status
# TODO: parse findings list
# TODO: optionally output all 'checks' objects
# Output the pre-determined binary findings
print("Binary check results:")
print(binReportString)
print("Service check results:")
print(svcReportString)
# Parse all items in bins{} and services{} and add them to checks and findings as needed

### Log the data - don't send to the console
logger.info("Binary check data structure:")
logger.info(str(bins))
logger.info("Service checks data structure:")
logger.info(str(services))
logger.info("All \"checks\" data structure:")
logger.info(str(checks))
logger.info("All \"findings\" data structure:")
logger.info(str(findings))

# # DEBUG STUFF
# # semi-debug, looks good for now until we get the checks and findings presentation built up
# for binName in bins:
#   print(f"Analysis of      : {bins[binName]['exe']}:")
#   print(f"  Owning pkg     : {bins[binName]['pkg']}" )
#   print(f"  Repo for pkg   : {bins[binName]['repo']}" )
# for svcName in services:
#   print(f"Analysis of unit : {services[svcName]['svc']}:")
#   print(f"  Owning pkg     : {services[svcName]['pkg']}" )
#   print(f"  Repo for pkg   : {services[svcName]['repo']}" )
#   print( "  run state      : "+colorString(services[svcName]['status'], redVal="dead", greenVal="active"))
#   print( "  config state   : "+colorString(services[svcName]['config'], redVal="disabled", greenVal="enabled"))
# # END DEBUG

print("------ END VMassist.py output ------")
#pprint(bins)
logger.info("Python ended")
#if ( args.debug ):
# print("------------ DATA STRUCTURE DUMP ------------")
# print("bins")
# pprint(bins)
# print("services")
# pprint(services)
# print("findings")
# pprint(findings)
# print("checks")
# pprint(checks)
# print("args")
# pprint(args)
# print("---------- END DATA STRUCTURE DUMP ----------")