# Wireless MCS DIagnostic Tool (`routermcs.sh`)
<!-- VT_BADGE_START -->
[![VirusTotal Scan](https://github.com/benem3000/router_mcs_check/actions/workflows/virustotal.yml/badge.svg)](https://www.virustotal.com)
<!-- VT_BADGE_END -->
A simple, interactive Bash utility for Linux environments that scans nearby wireless networks and management frames to see if your router is broadcasting Basic MCS Sets incorrectly. Also attempts to identify other useful information like ISP, wireless card model, and vendor/model of the router to identify affected models.

_AI Disclosure: Google Gemini was used heavily in the making of this tool, though testing and careful guidance were carried out by myself._

### A Note on Antivirus False Positives
_Because this script requires `sudo` privileges, performs active network scans, and makes a silent `curl` request to an external API (MacVendors), some overly aggressive heuristic antivirus engines (like Windows Defender) may flag the raw file if you download it to a Windows machine first. This is a false positive. The code is entirely open-source, and you are encouraged to review it before execution. New versions will be uploaded to virustotals for review._

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

### Share the results if desired. 
Ensure you copy the grave accents " ``` " that preceed and folow the results to ensure the formatting is preserved. (a.k.a. code markdown)

Results should look like this:
Single SSID:
```
Hardware: Intel Corporation Wi-Fi 6E(802.11ax) AX210/AX1675* 2x2 [Typhoon Peak] (rev 1a)
ISP:      comcast.net
--------------------------------------------------------------------------------------------------------------
SSID                             | BASIC MCS    | VENDOR             | MODEL NAME       | MODEL NUM       
--------------------------------------------------------------------------------------------------------------
| T************N                   | MCS 0-76     | SERCOMM PHILIPP... | N/A              | N/A              |
```


All SSID's
```
Hardware: Intel Corporation Wi-Fi 6E(802.11ax) AX210/AX1675* 2x2 [Typhoon Peak] (rev 1a)
ISP:      comcast.net
--------------------------------------------------------------------------------------------------------------
SSID                             | BASIC MCS    | VENDOR             | MODEL NAME       | MODEL NUM       
--------------------------------------------------------------------------------------------------------------
| M****o                           | None         | Technicolor        | XB8              | CGM4981COM       |
| P**********a                     | None         | NETGEAR, Inc.      | R7000            | R7000            |
| T************N                   | MCS 0-76     | SERCOMM PHILIPP... | N/A              | N/A              |
| T******************T             | None         | TP-Link            | N/A              | N/A              |
| W*******************k            | None         | Unknown            | N/A              | N/A              |
| W******T                         | None         | NETGEAR            | N/A              | N/A              |
| W**********t                     | None         | Unknown            | N/A              | N/A              |
| Y*********2                      | None         | TP-Link Systems... | N/A              | N/A              |
| Y***5                            | MCS 0-76     | Technicolor        | XB8              | CGM4981COM       |
```
___
### If you are having issues related to MCS
Any router with a Basic MCS range higher than 0-15 will likely have issues with certain 2x2 wireless cards and may need this patch if you experience max speeds around 20mbps:

For arch and non-imutable distros such as ubuntu (original patch):
https://github.com/WoodyWoodster/mac80211-mcs-patch

For Bazzite:
I have gotten this patch working via BlueBuild and have a custom testing repository (standard desktop bazzite only) here:
https://github.com/benem3000/mcspatched

If you have a special bazzite release, such as nvidia or the steam deck release, please don't use this yet. I will work on getting the other versions once I finish testing.

Other immutable distros will require the patch to be implemented by the maintainers of that distribution at their discretion. I'd recommend filing an issue with your distro provider to implement the patch. You're also free to clone my Bazzite repository and try to adapt it to your distro. I may add more information on the repo about adapting this to other distros in the near future.

___
Additional arguments available for debugging purposes, they are not necessary for the average user.

-c or --csv : Exports the final parsed results to a .csv file in your current directory.

-v or --verbose : Prints live execution commands and raw output streams to the console.

-d or --debug : Activates full Bash tracing and saves raw unparsed frame captures to .log files for deep troubleshooting.
___
