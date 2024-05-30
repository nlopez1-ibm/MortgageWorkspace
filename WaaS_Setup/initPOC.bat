@ECHO OFF
cls 
rem Use this to init and validate a new WaaS stock image for a simple user POCs. Tested May 2024 ver Image 3.1.


:init_locals
    rem below lets me reuse vars like lm and & for singletons
    SETLOCAL enabledelayedexpansion      
    
    rem nelson test fip =163.109.87.254.  Set the ./ssh/config entry var and append /etc/profile for system default vars like DBB and Git ...
    set SH=SSH poc-waas . /etc/profile;

    echo ***  initPOC.bat Started- checking env and setting up DBB, RACF and sample CICS application ***  
    echo Press enter when prompted or CNTL/C to exit 
    echo .
 
    echo Checking if the system is up via SSH  ...
    %sh% "ls > /dev/nul "
    if %ERRORLEVEL% == 0 GOTO System_is_Up 
    
    echo. 
    echo [101m**********        ERROR         ************[0m 
    echo Cant access WaaS. Is the VSI up/IPLed and was its IP added to the local '.ssh/config' file as poc-waas?. Exit rc=12  
    pause
    exit /b 12


:System_is_Up            
    rem runan iplinfo cmd to see what volume zOS was ipl'ed from. The volume name is the zOS ver. this script supports only 3.1 (not now)
    set zOS31_sig='Z31VS1'
    set supportedOS=The system is up and supported by this script (IPL Vol %zOS31_sig%).
    %sh% "opercmd 'd iplinfo' | grep '%zOS31_sig%'" >_sig
    for %%A in (_sig) do if %%~zA equ 0 (
        set supportedOS=**Warning: The system is up but this version of zOS has not been tested. Will continue but errors may exists.
    )
    del _sig

    echo %supportedOS% 
    echo Current zOS version:
    %sh% "uname -Irsv"
    pause 

:cics_Shut_Down
    rem do this early to avoid waiting later 
    echo .
    echo Stopping CICSTS61 STC for application configuration ...             
    %sh% "opercmd 'F CICSTS61,CEMT PERFORM SHUTDOWN'> /dev/nul "    
    echo .

:checkTools    
    echo Checking required tools and versions on Z Unix ...
    echo .
    echo DBB v2 and JVM v11: 
        %sh%  dbb --version
        echo . 
    
    echo ZOAU v1:
        %sh% zoaversion
        echo .  
    
    echo Git v2:
        %sh% git --version  
        echo .  
        echo ... 


    echo Listing required zOS STCs (CICS, RSE, RSEAPI, JMON, DB2, zOSMF(IZU*)).  A code of 'AC' means its active.     
        %sh%  "jls  | grep -e 'CICS' -e 'RSE' -e 'DB2'  -e 'IZU'  | grep -e 'AC ' -e 'ABEND ' -e 'CANCELED ' -e 'END' "
        echo .  
        echo ... 

    pause 


:reset_IBMUSER_RacfID:
    set /p RSet=Enter y to reset the IBMUSER RACF password to SYS1. Need to do this once to access 3270 and IDz from this PC.  
    if "%RSet%" neq "y" goto skip_RSet

    rem  Tech Note: NOEXPIRED option is disabled 
    echo Setting a temp IBMUSER RACF password to sys1.  It must be reset under TSO. 
    %sh%   tsocmd 'ALTUSER IBMUSER PASSWORD(sys1) ' 
    echo .  
    echo ... 
    :Skip_RSet

:clone-zappbuild 
    echo .  
    echo Cloning dbb-zappbuild on IBMUSER's Z Unix Home dir ... 
    %sh%  git clone --depth 1 https://github.com/IBM/dbb-zappbuild.git 

    if %ERRORLEVEL% neq 0  (
        echo ReRun detected. You can ignore the failed clone above. Skipping build phase.
        goto SkipBuild
    )
    echo .  
    echo ... 
    pause 

    

:get_System_Complier_Libs	 
    rem Use zoau dls cmd to pull the latest version of the system lib like the compilers...
    rem Some HLQs now have ver# like CICSTS61. This makes it harder to keep this code generic. 
    rem The output is a properties file thats added the the sample mortgage in the fixed location 
    rem under /u/ibmuser/dbb-zappbuild/samples/MortgageApplication/application-conf

    set build-conf='/u/ibmuser/dbb-zappbuild/build-conf/datasets.properties'
    echo Adding system PDSs to DBB's %build-conf% ... 
    
    rem HARDCODED some versioned libs.  Cant find the latest mq libs so use dummy.
    rem Cant find the latest mq libs so use a know lib for now
    rem no spaces after the ^
	
    %sh% "echo '# DBB System Dataset.properties Generated by $initVSI-Stock.BAT' > "%build-conf% ;^
    "dls IGY.*.SIGYCOMP      | awk '{print ""SIGYCOMP_V6=""$1}' >> "%build-conf% ;^
    "dls CEE.*MAC            | awk '{print ""SCEEMAC=""$1}'     >> "%build-conf% ;^
    "dls CEE.*LKED           | awk '{print ""SCEELKED=""$1}'    >> "%build-conf% ;^
    "dls ASM.*MOD1           | awk '{print ""SASMMOD1=""$1}'    >> "%build-conf% ;^
    "dls SYS1.MAC*           | awk '{print ""MACLIB=""$1}'      >> "%build-conf% ;^
    "dls CICSTS61.**.SDFHMAC | awk '{print ""SDFHMAC=""$1}'     >> "%build-conf% ;^
    "dls CICSTS61.**.SDFHCOB | awk '{print ""SDFHCOB=""$1}'     >> "%build-conf% ;^
    "dls CICSTS61.**.SDFHLOAD| awk '{print ""SDFHLOAD=""$1}'    >> "%build-conf% ;^
    "dls PLI.*.AIBMZMOD      | awk '{print ""IBMZPLI_V61=""$1}' >> "%build-conf% ;^
    "echo SDSNLOAD=DB2V13.SDSNLOAD >> "%build-conf% ;^
    "echo SCSQCOBC=SYS1.MACLIB     >> "%build-conf% ;^
	"echo SCSQLOAD=SYS1.LINKLIB    >> "%build-conf%   
    
     echo Added the following system PDSs to %build-conf%
     %sh% "cat %build-conf% "
    echo .  
    echo ...     
    pause 

:build_MortgageApplication
    echo Building the sample CICS 'MortgageApplication' with DBB build.groovy in daemon mode.
    echo Artifacts are stored in 'DBB.POC.LOAD' which is the CICSTS61 RPL PDS configured by this script ...
	%sh% "mkdir dbb-logs"
    %sh% "groovyz -DBB_DAEMON_HOST 127.0.0.1 -DBB_DAEMON_PORT 8180 dbb-zappbuild/build.groovy -w dbb-zappbuild/samples -a MortgageApplication -h DBB.POC -o dbb-logs --fullBuild"
    echo .  
    echo ...     
    pause 
    :SkipBuild

:Installer_Helper_Scripts
    echo Installing helper scripts ... 
    scp -r scripts poc-waas:dbb-zappbuild
    echo .  
        

:Run_Init_JCL
    rem tips on cp https://www.ibm.com/docs/en/zos/2.4.0?topic=descriptions-cp-copy-file
    rem         CICS cant be update for copy of sip or run of dfhcsdup ... 
    
    echo ...
    echo Preparing subsystem init jobs and files - CICS, DB2, RACF ... 
    scp -r initVSI-JCL poc-waas:initVSI-JCL


    echo ...
    echo    Replacing 'SYS1.PROCLIB(CICSTS61)' with 'cicsts61-mod.jcl'
    echo    This version of the CICS STC includes the DBB RPL PDS 'DBB.POC.LOAD' for testing     
    %sh% "cp -A -F crnl initVSI-JCL/cicsts61-mod.jcl  ""//'sys1.proclib(cicsts61)'"" "
    sleep 3

    echo ...
    echo    Replacing 'CICSTS61.SYSIN(DFH$SIP1)'  with 'dfh$sip1'
    echo    This version of the SIP enables CICS to access DB2 (SSID=DBD1) via DB2CONN      
    %sh%    "cp -F crnl 'initVSI-JCL/dfh$sip1'  ""//'cicsts61.sysin'"" "

    echo ...
    echo    Submitting system init jobs  ...
    %sh% cp -A -F crnl  initVSI-JCL/racfdef.jcl     //INITVSI.RACFDEF  ; submit ""//'IBMUSER.INITVSI.RACFDEF'""    
    %sh% cp -A -F crnl  initVSI-JCL/dsntep2.jcl     //INITVSI.DSNTEP2  ; submit ""//'IBMUSER.INITVSI.DSNTEP2'""    
    %sh% cp -A -F crnl  initVSI-JCL/epsbind.jcl     //INITVSI.EPSBIND  ; submit ""//'IBMUSER.INITVSI.EPSBIND'""    
    %sh% cp -A -F crnl  initVSI-JCL/epsgrant.jcl    //INITVSI.EPSGRANT ; submit ""//'IBMUSER.INITVSI.EPSGRANT'""             
    %sh% cp -A -F crnl  initVSI-JCL/dfhcsdup.jcl    //INITVSI.DFHCSDUP ; submit ""//'IBMUSER.INITVSI.DFHCSDUP'""    
    pause     
       
    rem need to start to apply ceda and restart Install below -  
    echo ...    
    %sh% "opercmd 's CICSTS61' > /dev/nul "     
    sleep 5

    echo ...
    echo    Installing the CICS Sample Transaction 
    %sh% "opercmd 'F CICSTS61,CEDA INS GROUP(EPSMTM)'"
    echo ...
    %sh% "opercmd 'F CICSTS61,CEDA INS DB2CONN(DBD1) GROUP(EPSMTM)'"
    sleep 5
    echo ...    
    %sh% "opercmd 'F CICSTS61,CEMT INQ TRAN(EPSP)' | grep -e 'Trans' -e 'Prog' -e 'Stat' -e 'INQ '"   
    echo ...
    %sh% "opercmd 'F CICSTS61,CEMT INQ DB2CONN '   | grep -e 'Db2c' -e 'Authid' -e 'Plan(' -e 'Def' -e 'Db2id'"    
    echo ...     
    pause 

    rem  Stopping  CICS more time to persist CEDA installs. 
    %sh% "opercmd 'F CICSTS61,CEMT PERFORM SHUTDOWN'> /dev/nul "    
    echo Persisting changes. Takes about 15 sec ....    
    sleep 15    
    echo ...     


:Install_zOS_Cert
    set /p install=Enter y to install the zOS Cert for 3270 and IDz access on this PC. NOTE: requires Windows Admin rights.  
    if "%install%" neq "y" goto skip_Install

    echo Copying cert from Z unix and running windows Cert installer ... 
    set certDir=current-cert
    
    del /Q !certDir!  > nul 2>&1  &  mkdir !certDir!   > nul 2>&1 
    scp poc-waas:/u/ibmuser/common_cacert !certDir!\common-stock.cer

    echo. 
    echo [101m  ***  NOTE: SCRIPT PAUSED FOR MANUAL INTERVENTION.  WINDOWS ADMIN RIGHTS ARE REQUIRED! ***[0m
    echo FOLLOW THESE INSTRUCTIONS:   
    echo  - Press [[35mInstall Certificate[0m] on the following popup and select [[35mStore Location[0m] for the [[35mLocal Machine[0m]. 
    echo  - Then, select [[35mPlace all certs ...[0m] and press browse to [[35mStore[0m] it in the [[35mTrusted Root...[0m] location.        
    timeout /T 5 /NOBREAK 
    explorer /e,!certDir!\common-stock.cer
    echo  Press Enter when the Cert is installed or CNLT/C. 
    pause 
    echo .  
    echo ...     
    :skip_Install

:Final_CICS_Start
    echo .
    echo ...          
    echo    Final Stage -  CICS restarting ...  
    %sh% "opercmd 's CICSTS61' "
    
:Done 
    echo .-------------------------------------------------------------------------- & echo .& echo .& echo .
    echo *** initPOC.bat Completed 
    echo ...
    echo   . The sample CICS Mortgage application was installed and configured in this WaaS VSI. 
    echo   . Logon to 3270 with RACF user IBMUSER and default password 'sys1'. Reset it on the first login.  
    echo   . Use IDz or vsCode to edit and build it with DBB using the '-HLQ' of 'DBB.POC'. 
    echo   . See the readme.md in this repo for mmore details.    
    pause
    echo ***

    EXIT /b 0
