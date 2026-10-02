# WAP-Reload.ps1
Uses Posh-SSH to connect to, inspect, and reboot Cisco wireless APs if over a threshold.


         File Name : WAP-Reload.ps1
   Original Author : Kenneth C. Mazie (kcmjr AT kcmjr.com)
                   : 
       Description : Uses Posh-SSH to connect to, inspect, and reboot Cisco wireless APs if over a threshold.
                   : 
             Notes : This script is uses the Posh-SSH module from the online gallery and loads it if needed.
                   : It reads a flat text file with AP IP addresses, randomizes it, and does an SSH connection 
                   : to each in sequence.  The running config is pulled and parsed to identify the AP
                   : uptime.  The XML config file is set with a number of days the AP is allowed to be up before 
                   : forcing a reboot.  If that number of days is exceeded the AP is rebooted.  Response to the
                   : reboot command is checked for, then the script waits until the AP can be pinged again
                   : before proceeding.  Multiple run options are available.  Multiple log files are or can be 
                   : generated.   The script uses a feature to detect if run from an editor or the console
                   : that alters whether screen messages are displayed for unattended runs.
                   :
      Requirements : Requires the PowerShell Posh-SSH module from the PowerShell Gallery.
                   :
           Options : These options can be toggled at the top of the script
                   :   $Debug - When set to $True all messages normally sent to the screen are written to the 
                   :            debug.log file in the script folder, plus extra info will be displayed.
                   :   $ReportOnly - When set to $True reboots are suppressed and only the logs are written
                   :   $ForceAllReboot - When set to $true every AP will be rebooted regardless of the maximum
                   :                     days allowed or other options.
                   :   $Console - When set to $True messages will be output to the screen at all times.  This
                   :              defaults to true for running from a PS console.  Set to $False for automation.
                   : 
          Warnings : This will reboot production access points so test using one AP first.
                   :   
             Legal : Public Domain. Modify and redistribute freely. No rights reserved.
                   : SCRIPT PROVIDED "AS IS" WITHOUT WARRANTIES OR GUARANTEES OF 
                   : ANY KIND. USE AT YOUR OWN RISK. NO TECHNICAL SUPPORT PROVIDED.
                   :
           Credits : Code snippets and/or ideas came from many sources including but 
                   :   not limited to the following:
                   : 
    Last Update by : Kenneth C. Mazie                                           
   Version History : v1.00 - 10-01-26 - Original 
    Change History : v2.00 - 00-00-00 - 
                   : #>
