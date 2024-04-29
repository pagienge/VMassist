# Health check script for Azure Agent on Linux - waagent

## Purpose
This is intended as a troubleshooting tool for the Azure Agent on Linux, and some related resources.  The intent is to identify common issues and present them in an easy-to-consume format, with the output mindset that this can be run in a limited-size serial console.

Logging is attempted to /var/log/azure/waagenthealth.log with full details, regardless of 

## Usage
- Run as root, or through sudo
- installation location TBD

Syntax: health.sh [-h|v]
- options:

   -h     Print this Help.
   
   -v     Verbose mode.