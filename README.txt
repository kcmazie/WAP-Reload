# WAP-Reload.ps1
Uses Posh-SSH to connect to, inspect, and reboot Cisco wireless APs if over a threshold.


         File Name : WAP-Reload.ps1
   Original Author : Kenneth C. Mazie (kcmjr AT kcmjr.com)
                   : 
       Description : Uses Posh-SSH to connect to, inspect, and reboot Cisco wireless APs if over a threshold.
                   : 
             Notes : This script uses the Posh-SSH module from the PowerShell gallery and loads it automatically 
                   :   if needed.  Posh-SSH is available here: https://github.com/darkoperator/Posh-SSH 
                   :   or https://www.powershellgallery.com/packages/posh-ssh/3.2.4
                   : The script reads a flat text file located in the script folder that contains a list of
                   : AP IP addresses to process.  The list is randomized and then an SSH connection is
                   : made to each IP address in sequence.  The running config is pulled and parsed to identify 
                   : the AP model and uptime.  The script also require an XML config file also located in the 
                   : script folder and named the same as the script.  In this folder you set the number of days
                   : the AP is allowed to be online before forcing a reboot.  The default is 30 days.  If that
                   : number of days is exceeded an attempt is made to reboot the AP.  The AP's response to the 
                   : reboot command is checked for and logged, then the script waits until the AP can be pinged 
                   : again before proceeding.  Multiple run options are available (see below).  Multiple log files 
                   : are or can be generated.  The script uses a feature to detect if run from an editor or a
                   : PowerShell console that alters whether screen messages are displayed for unattended runs.
                   : By default during the run you will be asked to enter the user name and password to SSH
                   : to each AP.  Alternately an encrypted password file can be used (see below).
                   :
      Requirements : An XMl config file named the same as the script in the script folder.  A sample is created
                   :   that can be edited during the initial script run
                   : Requires the PowerShell Posh-SSH module from the PowerShell Gallery.
                   : A flat text file in the script filed name "IPList.txt" containing the IP addresses of APs to access.
                   : Optionally an encrypted password file located in the script folder see the script here:
                   :   https://github.com/kcmazie/CredentialsWithKey
                   :
              Logs : 3 different log files can be created in the script folder.
                   :   Tracking.log - Always created.  Contains a coded copy of all runs.  The format of the log
                   :     is "date;IP;hostname;days up;days up allowed;reboot status;verified pingable after reboot"
                   :     The format is semicolon delimited for import into Excel or other tools.                   
                   :   Failure.log - All failures are logged
                   :   Debug.log - If debug mode is enabled all messages to the screen are recorded.
                   :   NOTE: Logs must be deleted manually.
                   :
           Options : These options can be toggled at the top of the script
                   :   $Debug - When set to $True all messages normally sent to the screen are written to the 
                   :            debug.log file in the script folder, plus extra info will be displayed.
                   :   $ReportOnly - When set to $True reboots are suppressed and only the logs are written
                   :   $ForceAllReboot - When set to $true every AP will be rebooted regardless of the maximum
                   :                     days allowed or other options.
                   :   $Console - When set to $True messages will be output to the screen at all times.  This
                   :              defaults to true for running from a PS console.  Set to $False for automation.
                   :   $NoLogging - If set to $True stops all logs from being written to for repeated testing.
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
    Change History : v1.10 - 10-05-26 - Updated internal documentation.  Added model detection.  Edited SSH
                   :                    routine to compensate for stubborn APs .
                   : v2.00 - 00-00-00 - 
                   : #>

