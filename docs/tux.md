# Doc landing page

## Description
This will be a landing page for the potential issues found by using the VMassist scripts on a Linux VM running in Azure.  We will discuss or link to documentation discussing mitigations to potential problems affecting the Azure agent or general system stability

## General prerequesites and program flow


## Mitigations

### Agent not ready
- OS must be actually booting completely
- Service config and status must be 'enabled' and 'Running' respectively
- The python called by the agent unit must be able to load the azurelinuxagent module see (loading modules)[#loading-modules]
- Service should not be installed from GitHub on a distribution providing a package for the Azure Agent
- Connectivity checks

### Python issues
- Don't change the default python on distributions which do not provide a 'platform-python'
- In the situation where there are multiple versions of python installed, the default python (/usr/bin/python3) should be one from the distribution publisher

#### Loading modules
- The scripts will check if the called python version can load the `azurelinuxagent` and 'requests' python modules, both of which are necessary for proper functionaility
- If either module fails to load, the agent will not function properly, as the `azurelinuxagent` module is the actual agent object and `requests` is used for I/O operations with the wire server and IMDS

### Repositories
- Installing packages that duplicate or replace system functions can cause issues, especially if these are done outside of the package manager mechanisms

#### python
Calling versions of python not properly integrated with the rest of the operating system can cause consistency issues
- Custom modules created as part of the Azure Agent are installed for the system python and other python versions will have their own library paths
- Python environments not created to the same specifications as the versions packaged with the OS may not include standard modules
- While this guidance is inteded specifically for the Azure Agent, replacing python in any modern Linux distribution is dangerous given how much of the OS is reliant on a stable and known python environment.

#### openssl


#### Custom
- Using 3rd party or custom repositories for system functionality is out of support
- installing from source is unsupportable

### OpenSSL
- The distribution-provided OpenSSL environment must be in place for supportability
- Some 3rd party programs may bring in their own libraries for openssl
- Installing from source to 'mitigate' a security concern is out of support

### Connectivity
- Once VM has been verified to boot successfully, work through this guide
  (Linux guest agent)[https://learn.microsoft.com/troubleshoot/azure/virtual-machines/linux/linux-azure-guest-agent]

### General package concerns
- For all checks of the source of a file, the "package" owning a file and the "repository" that package came from are listed.
- All packages must come from a supported repository or `@system`
