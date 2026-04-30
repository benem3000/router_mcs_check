# Wireless MCS DIagnostic Tool (`routermcs.sh`)
A simple, interactive Bash utility for Linux environments that scans nearby wireless networks and management frames to see if your router is broadcasting Basic MCS Sets incorrectly. Also attempts to identify other useful information like ISP, wireless card model, and vendor/model of the router to identify affected models.

## Getting Started
## **Important! If sharing results with strangers or online, please be sure to select the option to censor the SSIDs to prevent potentially leaking your location!**

### 1. Download the Script
Download the latest version of the script from the [Releases page](../../releases) of this repository. 

### 2. Make it Executable
Open your terminal, navigate to the directory where you downloaded the file, and grant it execution permissions:
```
cd ./script/location/
chmod +x routermcs.sh`
```
### Run the script and follow the prompts:

`./routermcs.sh`

Profit!




_Additional arguments available for debugging purposes, they are not recommended for the average user and include (-v or --verbose to provide more information from certatin functions and -d or --debug to enable logging and xtrace)_
