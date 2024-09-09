# Doc landing page

## Description
This will be a landing page for the potential issues found by using the VMassist scripts on a Linux VM running in Azure.  We will discuss or link to documentation discussing mitigations to potential problems affecting the Azure agent or general system stability

## Mitigations

### Agent not ready
- OS must be actually booting completely
- Service must be 'enabled' and 'Running'
- Python must be able to load the azurelinuxagent module see (loading modules)[#loading-modules]
- Service should not be installed from GitHub on a distribution providing a package for the Azure Agent
- Connectivity checks

### Python issues
- Don't change the default python
- Ensure an alternative python does not take priority over 'platform python'

#### Loading modules
- This can be related to using a custom python

### Repositories
- Installing packages that duplicate or replace system functions can cause issues
-- python
-- openssl

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
