# Doc landing page

## Description
This will be a landing page for the potential issues found by using the VMassist scripts on a Linux VM running in Azure.  We will discuss or link to documentation discussing mitigations to potential problems affecting the Azure agent or general system stability

## General prerequesites and program flow
The VM assist troubleshooting script requires very little in the way of prerequisites as it is intended to surface issues or present data for further scrutiny. The bare minimum is a functional `bash` shell and root-level access, either by directly becoming root or utilizing `sudo` in any form.

There are two scripts which comprise the 'tool', a bash script and a python script.  The bash script will perform some basic checks and determine if running the python script is possible and/or necessary.

The following checks are run in bash today
- OS family detection
- identify the Azure Agent service
- Identify the path of python called from the service
- Display the source package, and repository for package, for the agent and the python called from the agent
- Basic connectivity checks to the wire server and IMDS

If the bash script determines the base OS checks are not workable for whatever reason, the python script is not called and a report is output.  Assuming that the python script is run, the bash report is suppressed unless the `-r` flag is used.

Python will run the following checks - which may be duplicates of the bash work
- Find the source data for the Azure agent and the python passed from bash
- optionally check any service or package statuses, which is currently a proof-of-concept inside the script
- Provide source information for all checked files and services
- Do configuration checks for the  Azure agent
- Connectivity checks for the Azure agent
- Perform disk space checks

Output for the python script will the agent related checks where status is always displayed, along with anything deemed critical.

## Mitigations

### Agent not ready
- OS must be actually booting completely
- Generally speaking, the service should not be installed from GitHub on a distribution providing a package for the Azure Agent as many of the next checks would be incorrect
- Azure Agent service config and status must be 'enabled' and 'Running' respectively
- The python called by the agent unit must be able to load the azurelinuxagent module see (loading modules)[#loading-modules]
- Connectivity checks to the wire server must pass to report status

### Python issues
Calling versions of python not properly integrated with the rest of the operating system can cause consistency issues
- Python environments not created to the same specifications as the versions packaged with the OS may not include standard modules
- While this guidance is inteded specifically for the Azure Agent, replacing python in any modern Linux distribution is dangerous given how much of the OS is reliant on a stable and known python environment.
- On RedHat 8 systems there is a version of python to be used for all services located at '/usr/bin/platform-python' and the standard python3 usually links to it.  Note that the standard agent package references platform-python directly so it will be possible to alter the /usr/bin/python3 link without breaking the Azure Agent.
- In distributions other than RedHat 8, if there are multiple versions of python3 installed, the default python3 (/usr/bin/python3) should be one from the distribution publisher for the purpose of loading all the required modules.
- While it is possible to make any python3 work with the Azure Agent, it is out of scope for support as we only support the distribution python 3
- The correct path for anything needing a specific version of python 3 is to direct that software to the specific needed version and leave the OS-provided python in place and linked.

#### Loading modules
- Custom modules created as part of the Azure Agent are installed for the system python and other python versions will have their own library paths
- The scripts will check if the called python version can load the `azurelinuxagent` and `requests` python modules, both of which are necessary for proper functionaility
- If either module fails to load, the agent will not function properly, as the `azurelinuxagent` module is the actual agent class and `requests` is used for I/O operations with the wire server and IMDS
- In a truly custom python3 build it is possible that even base modules are not present, which places the burden back on the systems administrator to fix any issues.

Internal TSGs:
https://supportability.visualstudio.com/AzureIaaSVM/_wiki/wikis/AzureIaaSVM/910884/WALinuxAgent-ModuleNotFoundError-NameError_AGEX

### OpenSSL
Generally speaking, openssl does not apply to the starting of the Azure Agent, or communication to either the wireserver or IMDS, however openssl issues can cause problems with anything else that communicates to an SSL website. SSL communications include, but is not limited to 
- Azure platform API endpoints
- Other Azure services other than the management API 
- EntraID SSH authentication
- OS repository servers

Altering the base OpenSSL binary either by installing 3rd party packages or from source, is unsupported in all forms.

### Repositories
Installing packages that duplicate or replace system functions can cause issues, especially if these are done outside of the package manager mechanisms

When examining the output of the VM assist scripts, the repository listings are provided to surface this data for examination.  There are some strings which are treated as "distribution provided" for validation purposes.  This includes, but may not be limited to, the following and will vary based on the distribution present
- azurelinux
- Origin: Ubuntu
- @System
- anaconda
- rhui
- AppStream
- SLE-Module

Certain other outputs in the "repository" output should be considered cause for investigation
- 3rd party websites
- custom "in-house" repositories
- other versions or variations of the distribution in question, for example: CentOS on a RedHat VM, OpenSuSE on SuSE Enterprise, Debian on Ubuntu
- The string "@commandline" meaning installed from a download, without stating where it came from
- No output (blank)

#### Custom sources
The following scenarios are unsupported for anything which may affect the Azure Agent
- Using 3rd party repositories
- Mirroring the official repositories with tools like SuSE Manager, RedHat satellite, Spacewalk, or anything similar
- Installing from github
- Compiling from source

### Connectivity
- Once VM has been verified to boot successfully, work through this guide
  (Linux guest agent)[https://learn.microsoft.com/troubleshoot/azure/virtual-machines/linux/linux-azure-guest-agent]
