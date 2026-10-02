
<#==============================================================================
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
                   $ScriptVer = "1.00"    <#--[ Current version # used in script ]--
==============================================================================#>
#Requires -version 5
Clear-host
$ProgressPreference = 'SilentlyContinue'

#==[ Runtime Options ]=========================================================

#--[ "Debug" Records everything printed to the screen in the debug log and display extra debugging info ]--
$Debug = $False #True     
#--[ "ReportOnly" Disables reboot for all WAPs unless forced but still records WAP status in the tracking log  ]-- 
$ReportOnly = $False #True
#---------------------------------------------------------------------------------------------------
#--[ BE VERY CAREFUL WITH THIS.  IT FORCES ALL WAPs TO REBOOT DURING A RUN REGARDLESS OF DAYS UP ]--
$ForceAllReboot = $False   
#---------------------------------------------------------------------------------------------------
$Console = $True

#==[ Functions ]===============================================================

Function StatusMsg ($Msg, $Color, $ExtOption, $Tracking){
    If ($Null -eq $Color){
        $Color = "Magenta"
    }
    If ($ExtOption.Debug){
        Add-Content -Path "$PSScriptRoot\Debug.log" -Value $Msg
    }
    If ($Null -ne $Tracking){
        Add-Content -Path "$PSScriptRoot\Tracking.log" -Value $Tracking
        Return
    }    
    If ($ExtOption.ConsoleState){
        Write-Host "-- Script Status: " -NoNewline -ForegroundColor "Magenta"
        Write-host $Msg -ForegroundColor $Color
    }
    $Msg = ""
}

Function LoadModules ($ExtOption){
    $ErrorActionPreference = "stop"
    $ModName = "Posh-SSH"
    If (!(Get-Module -Name $ModName)) {    
        Try{  
            Import-Module -name $ModName -force
            #Install-Module -Name Posh-SSH -force
        }Catch{
            StatusMsg "-- Error loading Posh-SSH module." Red $ExtOption
            StatusMsg  ("Error: "+$_.Error.Message) Red $ExtOption
            StatusMsg  ("Exception: "+$_.Exception.Message) Red $ExtOption
        }
    }
}

Function GetConsoleHost ($ExtOption){  #--[ Detect if we are using a script editor or the console ]--
    Switch ($Host.Name){
        'consolehost'{
            $ExtOption | Add-Member -MemberType NoteProperty -Name "ConsoleState" -Value $False -force
            $ExtOption | Add-Member -MemberType NoteProperty -Name "ConsoleMessage" -Value "- PowerShell Console detected." -Force
        }
        'Windows PowerShell ISE Host'{
            $ExtOption | Add-Member -MemberType NoteProperty -Name "ConsoleState" -Value $True -force
            $ExtOption | Add-Member -MemberType NoteProperty -Name "ConsoleMessage" -Value "- PowerShell ISE editor detected." -Force
        }
        'PrimalScriptHostImplementation'{
            $ExtOption | Add-Member -MemberType NoteProperty -Name "ConsoleState" -Value $True -force
            $ExtOption | Add-Member -MemberType NoteProperty -Name "COnsoleMessage" -Value "- PrimalScript or PowerShell Studio editor detected." -Force
        }
        "Visual Studio Code Host" {
            $ExtOption | Add-Member -MemberType NoteProperty -Name "ConsoleState" -Value $True -force
            $ExtOption | Add-Member -MemberType NoteProperty -Name "ConsoleMessage" -Value "- Visual Studio Code editor detected." -Force
        }
    }
    If ($ExtOption.ConsoleState){
        StatusMsg "PowerShell session is running from an editor..." "Magenta" $ExtOption
    }
    Return $ExtOption
}

Function RebootWindow ($ExtOption) {    #--[ Returns $True or $False ]--
    [int]$StartHour = $ExtOption.WindowBegin
    [int]$EndHour = $ExtOption.WIndowEnd
    $Now = Get-Date
    $Start = Get-Date -Hour $StartHour -Minute 0 -Second 0
    $End = Get-Date -Hour $EndHour -Minute 0 -Second 0
    If ($Start -lt $End){
        #--[ Daytime Window ]--
        Return ($Now -ge $Start -and $Now -le $End)
    } Else {
        #--[ Overnight Window (Spans midnight) ]--
        Return ($Now -ge $Start -or $Now -le $End)
    }
}

Function LoadConfig ($ExtOption,$ConfigFile){
    If (Test-Path $ConfigFile){                          #--[ Error out if configuration file doesn't exist ]--
        [xml]$Config = Get-Content $ConfigFile  #--[ Read & Load XML ]--    
        $ExtOption | Add-Member -Force -MemberType NoteProperty -Name "PasswordFile" -Value $Config.Settings.Credentials.PasswordFile        
        $ExtOption | Add-Member -Force -MemberType NoteProperty -Name "KeyFile" -Value $Config.Settings.Credentials.KeyFile
        $ExtOption | Add-Member -Force -MemberType NoteProperty -Name "DaysBetween" -Value $Config.Settings.General.DaysBetween
        $ExtOption | Add-Member -Force -MemberType NoteProperty -Name "WindowBegin" -Value $Config.Settings.General.WindowBegin
        $ExtOption | Add-Member -Force -MemberType NoteProperty -Name "WindowEnd" -Value $Config.Settings.General.WindowEnd
    }Else{
        Write-Host "MISSING XML CONFIG FILE.  File is required.  Script aborted..." -ForegroundColor Red
        $Message = (
            '<?xml version="1.0" encoding="utf-8"?>
            <!-- External XML config file example -->
            <!-- To be named the same as the script and located in the same folder as the script -->
            <Settings>
				<General>
					<DaysBetween>30</DaysBetween>
					<WindowBegin>18</WindowBegin>
					<WindowEnd>6</WindowEnd>
				</General>
                <Credentials>
                    <PasswordFile>\AESP.txt</PasswordFile>
                    <KeyFile>\AESK.txt</KeyFile>
                </Credentials>        
            </Settings> ')
        Write-host $Message -ForegroundColor Yellow 
        Add-content -Path $ConfigFile -Value $Message
        Write-Host "A basic config file has been created for you in the script folder." -ForegroundColor green
        Write-Host "MISSING XML CONFIG FILE.  File is required.  Script aborted..." -ForegroundColor Red
        break;break;break
    }
    Return $ExtOption
}

Function GetSSH ($TargetIP,$Tracker,$ExtOption){
    $ErrorActionPreference = "stop"
    $HostName = ""
    $UpTime = ""
    [int]$Days = 0
    $Password = $ExtOption.Credential.GetNetworkCredential().Password
    Try{        
        Get-SSHSession | Select-Object SessionId | Remove-SSHSession | Out-Null  #--[ Remove any existing sessions ]--
        $Session = New-SSHSession -ComputerName $TargetIP -AcceptKey -Credential $ExtOption.Credential   #--[ Create the session ]--
        If ($Session.Connected) {
            StatusMsg "SSH session status           : Connected" "Green" $ExtOption
        }else{
            StatusMsg "SSH session status           : FAILED" "Red" $ExtOption
        }
        Start-Sleep -Milliseconds 10            #--[ Pause ]--
        #--[ Stream Arguments: (terminalName, columns, rows, width, height, bufferSize) ]--
        $Stream = $Session.Session.CreateShellStream("dumb", 200, 50, 0, 0, 256000)  #--[ Open the stream ]--     
        Start-Sleep -Milliseconds 250           #--[ Pause ]--
        $Stream.Read() | Out-Null               #--[ Clear the buffer ]--
        $Stream.WriteLine("terminal length 0")  #--[ Set the terminal length ]--
        Start-Sleep -Milliseconds 250           #--[ Pause ]--
        $Stream.Read() | Out-Null               #--[ Clear the buffer ]--
        $Stream.WriteLine("en")                 #--[ Send the enable command ]--
        Start-Sleep -Milliseconds 250           #--[ Pause ]--]
        $Stream.Read() | Out-Null               #--[ Clear the buffer ]--
        $Stream.WriteLine($Password)            #--[ Send the password ]--
        Start-Sleep -Milliseconds 250           #--[ Pause ]-- 
        $Stream.Read() | Out-Null               #--[ Clear the buffer ]--
        $Stream.WriteLine("terminal length 0")  #--[ Set the terminal length ]--
        Start-Sleep -Milliseconds 250           #--[ Pause ]-- 
        $Stream.Read() | Out-Null               #--[ Clear the buffer ]--
        $Stream.WriteLine("show version")       #--[ Get the OS version ]--
        Start-Sleep -Milliseconds 350           #--[ Pause ]--

        $Response = $Stream.Read()
        $Response.Split("`r`n") | ForEach-Object{
 #           $_
            If ($_.Trim() -like "*uptime*"){
                #--[ The uptime line in SHOW VERSION is not consistent.  Some may show weeks,  ]--
                #--[ some may show days, some both, or neither.  The $Day variable defaults to ]--                
                #--[ zero, then weeks are calculated as days and added, then days are added.   ]--
                #--[ If no weeks or days exist then $Days stays at zero.                       ]--    
                If ($ExtOption.Debug){  
                    StatusMsg ("DEBUG - Detected data        : "+$_) "Gray" $ExtOption
                }
                $Uptime = ($_.Trim().Split([string[]]"is", [System.StringSplitOptions]::None)[1]).Trim()
                #--[ Split out weeks and days to get total days ]--
                $SplitTime = $UpTime.Trim().Split(",")
                ForEach ($Chunk in $SplitTime){
                    If ($Chunk -like "*week*"){
                        [int]$Days += (([int]$Chunk.Trim().Split(" ")[0])*7)
                    }
                    If ($Chunk -like "*day*"){
                        [int]$Days += [int]$Chunk.Trim().Split(" ")[0]
                    }
                }
                $Hostname = ($_.Trim().Split(" ")[0])
                StatusMsg ("Detected Hostname            : "+$Hostname) "Cyan" $ExtOption
                StatusMsg ("Detected Uptime              : "+$Uptime) "Cyan" $ExtOption
                StatusMsg ("Days since last reboot       : "+$Days) "Cyan" $ExtOption                
            }
            Start-Sleep -Milliseconds 2   
        }
        If ($HostName -eq ""){
            StatusMsg "-- Failure to read uptime --" "Red" $ExtOption
            $Tracker = $Tracker+";- Failure to read uptime -"
            Add-Content -Path "$PSScriptRoot\Failure.log" -Value $Tracker
            Return
        }
        $Tracker = $Tracker+";$HostName;$UpTime"
        $Stream.Read() | Out-Null          #--[ Clear the buffer ]--  
        Start-Sleep -Milliseconds 250      #--[ Pause ]-- 
        $RebootOK = $True

        #--[ Validation Checks ]--
        StatusMsg ("Allowed days between reboots : "+$ExtOption.DaysBetween) "Cyan" $ExtOption
        StatusMsg "Performing validation checks :" "Cyan" $ExtOption
        If ($Days -lt $ExtOption.DaysBetween){  
            StatusMsg "- This WAP has been online less than 30 days.   No reboot will occur..." "Green" $ExtOption
            $Tracker = $Tracker+";<30"
            $RebootOK = $False
        }Else{
            StatusMsg "- This WAP has been online for over 30 days.    Reboot OK to proceed..." "Yellow" $ExtOption
            $Tracker = $Tracker+";>30"
            $RebootOK = $True
            If (!(RebootWindow $ExtOption)){       
                StatusMsg "- Currently outside of the safe reboot window.  No reboot will occur..." "Green" $ExtOption
                $RebootOK = $False
            }Else{
                StatusMsg "- Safe reboot window is currently OPEN.        Reboot OK to proceed..." "Yellow" $ExtOption
            $RebootOK = $True
            }
        }
       
        If ($ExtOption.ReportOnly){
            StatusMsg "- Report Only Mode is active.                   No reboot will occur..." "Cyan" $ExtOption
            $RebootOK = $False
        }

        #--[ Perform the reboot ]--       
        If (($RebootOK) -or ($ForceAllReboot)){
            $Stream.WriteLine("reload")        #--[ Send the reload command ]--
            Start-Sleep -Milliseconds 250      #--[ Pause ]-- 
            $Stream.Read() | Out-Null          #--[ Clear the buffer ]--
            $Stream.WriteLine("")              #--[ Send a blank line ]--
            Start-Sleep -Milliseconds 250      #--[ Pause ]-- 
            $Response = $Stream.Read()         #--[ Clear the buffer ]--
            #--[ Typical response =  cli: AP Rebooting: CLI triggered reboot(reload command)  ]--
            StatusMsg ("WAP response                 : '"+$Response.Trim()+"'") "Cyan" $ExtOption
            If ($Response -like "*Rebooting*"){
                $Tracker = $Tracker+";GoodReload"
                StatusMsg "- Reload in progress... Pausing, Please stand by..." "Cyan" $ExtOption
            }Else{
                $Tracker = $Tracker+";BadReload"
                StatusMsg "- An invalid response was detected from WAP." "Red" $ExtOption
                StatusMsg "- Reboot may not have occurred.  Please check..." "Red" $ExtOption
            }
            #--[ Check for good ping response. Bail after 300 seconds. ]--
            Start-Sleep -Seconds 15
            $Timeout = [TimeSpan]::FromSeconds(300)
            $StopWatch = [System.Diagnostics.Stopwatch]::StartNew()
            $GoodPing = $false
            While (($StopWatch.Elapsed -lt $Timeout) -and (!($GoodPing))){
                If ($ExtOption.Debug){
                    $Msg = "DEBUG - Elapsed time = "+[int]$StopWatch.Elapsed.TotalSeconds+" Seconds"
                    StatusMsg $Msg "White" $ExtOption
                }
                If (Test-Connection -ComputerName $IP -Count 1 -Quiet) {
                    $GoodPing = $true
                    Break
                }
                Start-Sleep -Seconds 2
            }
            $StopWatch.Stop()
            If ($GoodPing){
                $Tracker = $Tracker+";GoodPing"
                StatusMsg "WAP Status                : Verified back online..." "Green" $ExtOption
            }Else{
                $Tracker = $Tracker+";BadPing"
                StatusMsg "WAP Status                : Not responding to ping.  Please check manually..." "Red" $ExtOption
            }

        }Else{
            $Tracker = $Tracker+";;;"
        }        
        Get-SSHSession | Select-Object SessionId | Remove-SSHSession | Out-Null  #--[ Remove the open session ]-- 
        If ($Session.Connected) {
            StatusMsg "SSH session status        : Disconnect FAILED" "Red" $ExtOption
        }else{
            StatusMsg "SSH session status        : Disconnected" "Cyan" $ExtOption
        }
    }Catch{
        StatusMsg "An error has occurred during the SSH session..." "Red" $ExtOption
        StatusMsg $_.Exception.Message "Red" $ExtOption
    }
    StatusMsg "" "Black" $ExtOption $Tracker  #--[ This ONE status adds $Tracker to the tracker log ]--
    Return #$ExtOption
}

#==[ End of Functions ]====================================================

#--[ Load external XML options file ]------------------------------------------------
$ConfigFile = $PSScriptRoot+"\"+($MyInvocation.MyCommand.Name.Split("_")[0]).Split(".")[0]+".xml"
$ExtOption = New-Object -TypeName psobject #--[ Object to hold runtime options ]--
$ExtOption = LoadConfig $ExtOption $ConfigFile
#--[ Detect Runspace ]--
$ExtOption = GetConsoleHost $ExtOption 
If ($ExtOption.ConsoleState){ 
    StatusMsg $ExtOption.ConsoleMessage "Cyan" $ExtOption
}
#--[ Lock in selected runtime options ]--
If ($Debug){
    $ExtOption | Add-Member -Force -MemberType NoteProperty -Name "Debug" -Value $True
}
If ($Console){
    $ExtOption | Add-Member -Force -MemberType NoteProperty -Name "ConsoleState" -Value $True
}
If ($ReportOnly){
    $ExtOption | Add-Member -Force -MemberType NoteProperty -Name "ReportOnly" -Value $True
}


#--[ Process Logon Credentials ]-------------------------------
$UID = "admin"
If ($Null -eq $ExtOption.PasswordFile){
    $Credential = Get-Credential -Message 'Enter the local WAP User and Password to continue.'
}Else{
    $PasswordFile = $PSScriptRoot+$ExtOption.PasswordFile
    $KeyFile = $PSScriptRoot+$ExtOption.KeyFile
    If (Test-Path -Path $PasswordFile){
        $Base64String = (Get-Content $KeyFile)
        $ByteArray = [System.Convert]::FromBase64String($Base64String)
        $Credential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $UID, (Get-Content $PasswordFile | ConvertTo-SecureString -Key $ByteArray)
    }
}
$ExtOption | Add-Member -Force -MemberType NoteProperty -Name "Credential" -Value $Credential

#==[ Main Process ]====================================================
LoadModules
StatusMsg ("Reboot window start time     : "+$ExtOption.WindowBegin+":00 Hrs") "Cyan" $ExtOption
StatusMsg ("Reboot window stop time      : "+$ExtOption.WindowEnd+":00 Hrs") "Cyan" $ExtOption

$TargetList = Get-content -Path $PSScriptRoot\IPlist.txt
$TargetList = $Targetlist | Sort-Object { Get-Random }
StatusMsg "- Randomizing target IP list..." "Yellow" $ExtOption

#$TargetList = "10.40.10.74"
#$TargetList = "10.40.70.104"

ForEach ($IP in $TargetList){
    $Now = Get-Date -Format MM-dd-yyyy 
    $Tracker = "$Now;$IP"
    StatusMsg "--------------------------------------------" "Magenta" $ExtOption
    StatusMsg ("Target IP Address            : "+$IP) "Cyan" $ExtOption
    If (Test-Connection -ComputerName $IP -Count 1 -Quiet) {
        StatusMsg "Ping check                   : Successful" "Green" $ExtOption
        GetSSH $IP $Tracker $ExtOption
    }Else{
        StatusMsg "Ping check                   : Failed" "Red" $ExtOption
        $Tracker = $Tracker+";- Failure to respond to ping -"
        Add-Content -Path "$PSScriptRoot\Failure.log" -Value $Tracker
    }
}

StatusMsg "-- Completed --" "Red" $ExtOption