#!/bin/bash

#
##
## Downloading files...
##
#

# Which branch?
devMode=$1
case $devMode in
  "BETA")
	branch="beta"
  ;;
  "DEV")
	  branch="dev"
	;;  
  *)
	branch="main"
  ;;
esac

#Clean up previous installations
rm ~/emudek.log 2>/dev/null # This is emudeck's old log file, it's not a typo!
rm -rf ~/dragoonDoriseTools
mkdir -p ~/emudeck

#Creating log file
echo "" > ~/emudeck/emudeck.log
LOGFILE=~/emudeck/emudeck.log
exec > >(tee ${LOGFILE}) 2>&1

#Mark if this not a fresh install
FOLDER=~/emudeck/
if [ -d "$FOLDER" ]; then
	echo "" > ~/emudeck/.finished
fi
sleep 1
SECONDTIME=~/emudeck/.finished

# Seeting up the progress Bar for the rest of the installation
finished=false
echo "0" > ~/emudeck/msg.log
echo "# Downloading files from $branch channel..." >> ~/emudeck/msg.log
MSG=~/emudeck/msg.log
(	
	while [ $finished == false ]
	do 
		  cat $MSG		    
		  if grep -q "100" "$MSG"; then
			  finished=true
			break
		  fi
							  
	done &
) |
zenity --progress \
  --title="Installing EmuDeck" \
  --text="Downloading files from $branch channel..." \
  --percentage=0 \
  --no-cancel \
  --pulsate \
  --auto-close \
  --width=300 \ &

if [ "$?" = -1 ] ; then
	zenity --error \
	--text="Update canceled."
fi

#We create all the needed folders for installation
mkdir -p dragoonDoriseTools
mkdir -p dragoonDoriseTools/EmuDeck
cd dragoonDoriseTools

#Cloning EmuDeck files
git clone https://github.com/dragoonDorise/EmuDeck.git ~/dragoonDoriseTools/EmuDeck 
if [ ! -z "$devMode" ]; then
	cd ~/dragoonDoriseTools/EmuDeck
	git checkout $branch 
fi

#Test if we have a successful clone
EMUDECKGIT=~/dragoonDoriseTools/EmuDeck
if [ -d "$EMUDECKGIT" ]; then
	echo -e "Files Downloaded!"
else
	echo -e ""
	echo -e "We couldn't download the needed files, exiting in a few seconds"
	echo -e "Please close this window and try again in a few minutes"
	sleep 999999
	exit
fi

#
##
## EmuDeck is installed, start setting up stuff
##
#


#
## Settings
#
#Check for config file
FILE=~/emudeck/settings.sh
if [ -f "$FILE" ]; then
	source "$EMUDECKGIT"/settings.sh
	else
	cp "$EMUDECKGIT"/settings.sh ~/emudeck/settings.sh	
fi

#
## Functions
#

source "$EMUDECKGIT"/functions/all.sh

#
## Splash screen
#

latest=$(cat ~/dragoonDoriseTools/EmuDeck/latest.md)	
if [ -f "$SECONDTIME" ]; then
	 text="$(printf "<b>Hi, this is the changelog of the new features added in this version</b>\n\n${latest}")"
	 width=1000
else
	text="$(printf "<b>Welcome to EmuDeck!</b>")"
	width=300
fi 
 zenity --info \
--title="EmuDeck" \
--width=${width} \
--text="${text}" 2>/dev/null
	
#
#Hardware Check for Holo Users
#
if [[ "$(cat /sys/devices/virtual/dmi/id/product_name)" =~ Jupiter ]]; then
	isRealDeck=true
else
	isRealDeck=false
fi

#
# Initialize locations
#
locationTable=()
locationTable+=(TRUE "Internal" "$HOME") #always valid

#built in SD Card reader
if [ -b "/dev/mmcblk0p1" ]; then	
	#test if card is writable and linkable
	sdCardFull="$(findmnt -n --raw --evaluate --output=target -S /dev/mmcblk0p1)"
	echo "SD Card found; testing $sdCardFull for validity."
	sdValid=$(testLocationValid "SD" $sdCardFull)
	echo "SD Card at $sdCardFull is valid? Return val: $sdValid"
	if [[ $sdValid == "valid" ]]; then
		locationTable+=(FALSE "SD Card" "$sdCardFull") 
	fi
fi

#
# Installation mode selection
#

text="`printf "<b>Hi!</b>\nDo you want to run EmuDeck on Easy or Expert mode?\n\n<b>Easy Mode</b> takes care of everything for you, it is an unattended installation.\n\n<b>Expert mode</b> gives you a bit more of control on how EmuDeck configures your system like giving you the option to install PowerTools or keep your custom configurations per Emulator"`"
zenity --question \
		 --title="EmuDeck" \
		 --width=250 \
		 --ok-label="Expert Mode" \
		 --cancel-label="Easy Mode" \
		 --text="${text}" 2>/dev/null
ans=$?
if [ $ans -eq 0 ]; then
	expert=true
	locationTable+=(FALSE "Custom" "CUSTOM") #in expert mode we'll allow the user to pick an arbitrary place.
else
	expert=false
fi

#
#Storage Selection
#

if [[ ${#locationTable[@]} -gt 3 ]]; then # -gt 3 because there's 3 entries per row.
	destination=$(zenity --list \
	--title="Where would you like Emudeck to be installed?" \
	--radiolist \
	--width=400 --height=225 \
	--column="" --column="Install Location" --column="value" \
	--hide-column=3 --print-column=3 \
		"${locationTable[@]}"  2>/dev/null)
	ans=$?
	if [ $ans -eq 0 ]; then
		echo "Storage: ${destination}"
	else
		echo "No storage choice made"
		exit
	fi
else
	destination="$HOME"
fi

if [[ $destination == "CUSTOM" ]]; then
	destination=$(zenity --file-selection --directory --title="Select a destination for the Emulation directory." 2>/dev/null)
	if [[ $destination != "CUSTOM" ]]; then
		echo "Storage: ${destination}"
		customValid=$(testLocationValid "Custom" "${destination}")

		if [[ $customValid != "valid" ]]; then
			echo "Valid location not chosen. Exiting"
			exit
		fi

	else
		echo "User didn't choose. Exiting."
		exit
	fi
fi

#New paths based on where the user picked.
setSetting emulationPath "${destination}/Emulation/"
setSetting romsPath "${destination}/Emulation/roms/"
setSetting toolsPath "${destination}/Emulation/tools/"
setSetting biosPath "${destination}/Emulation/bios/"
setSetting savesPath "${destination}/Emulation/saves/"
ESDEscrapData="${destination}/Emulation/tools/downloaded_media"

#Folder creation...
mkdir -p "$emulationPath"
mkdir -p "$toolsPath"launchers 
mkdir -p "$savesPath"
mkdir -p "$romsPath"
mkdir -p "$biosPath"
mkdir -p "$biosPath"/yuzu/

##Generate rom folders
setMSG "Creating roms folder in $destination"

sleep 3
rsync -r --ignore-existing ~/dragoonDoriseTools/EmuDeck/roms/ "$romsPath" 

#
# Start of Expert mode configuration
# The idea is that Easy mode is unatended, so everything that's out
# out of the ordinary has to had its flag enabled/disabled on Expert mode
#	

if [ $expert == true ]; then

		#set all features to false
		doInstallCHD=false
		doInstallPowertools=false
		doInstallGyro=false
		doUpdateSRM=false
		doInstallESDE=false
		doSelectEmulators=false
		doCustomEmulators=false
		doSelectRABezels=false
		doSelectRAAutoSave=false
		doSNESAR87=false
		doSelectWideScreen=false
		doRASignIn=false
		doRAEnable=false
		doESDEThemePicker=false
		doXboxButtons=false		
	
		#one entry per expert mode feature
		table=()
		table+=(TRUE "CHDScript" "Install the latest version of our CHD conversion script?")
		table+=(TRUE "PowerTools" "Install Power Tools for CPU control? (password required)")
		table+=(TRUE "SteamGyro" "Setup the SteamDeckGyroDSU for gyro control (password required)")
		table+=(TRUE "updateSRM" "Install/Update Steam Rom Manager?")
		table+=(TRUE "updateESDE" "Install/Update Emulation Station DE?")
		table+=(TRUE "selectEmulators" "Select the emulators to install.")
		table+=(TRUE "selectEmulatorConfig" "Customize the emulators who's config we override (note: Fixes will be skipped)")
		table+=(TRUE "selectRABezels" "Turn on Bezels for Retroarch?")
		table+=(TRUE "selectRAAutoSave" "Turn on Retroarch AutoSave/Restore state?")
		table+=(TRUE "snesAR" "SNES 8:7 Aspect Ratio? (unchecked is 4:3)")
		table+=(TRUE "selectWideScreen" "Customize Emulator Widescreen Selection?")
		table+=(TRUE "setRAEnabled" "Enable Retroachievments in Retroarch?")
		table+=(TRUE "setRASignIn" "Change RetroAchievements Sign in?")
		table+=(TRUE "doESDEThemePicker" "Choose your EmulationStation-DE Theme?")		
		#table+=(TRUE "doXboxButtons" "Should facebutton letters match between Nintendo and Steamdeck? (default is matched location)")

		declare -i height=(${#table[@]}*50)

		expertModeFeatureList=$(zenity  --list --checklist --width=1000 --height=${height} \
		--column="Select?"  \
		--column="Features"  \
		--column="Description" \
		--hide-column=2 \
		"${table[@]}" 2>/dev/null)

		#set flags to true for selected expert mode features
		if [[ "$expertModeFeatureList" == *"CHDScript"* ]]; then
			doInstallCHD=true
		fi
		if [[ "$expertModeFeatureList" == *"PowerTools"* ]]; then
			doInstallPowertools=true
		fi
		if [[ "$expertModeFeatureList" == *"SteamGyro"* ]]; then
			doInstallGyro=true
		fi
		if [[ "$expertModeFeatureList" == *"updateSRM"* ]]; then
			doUpdateSRM=true
		else
			doUpdateSRM=false
		fi
		if [[ "$expertModeFeatureList" == *"updateESDE"* ]]; then
			doInstallESDE=true
		else
			doInstallESDE=false
		fi
		if [[ "$expertModeFeatureList" == *"selectEmulators"* ]]; then
			doSelectEmulators=true
		fi
		if [[ "$expertModeFeatureList" == *"selectEmulatorConfig"* ]]; then
			doCustomEmulators=true
		fi
		if [[ "$expertModeFeatureList" == *"selectRABezels"* ]]; then
			RABezels=true
		else
			RABezels=false
		fi
		if [[ "$expertModeFeatureList" == *"selectRAAutoSave"* ]]; then
			RAautoSave=true
		else
			RAautoSave=false
		fi
		if [[ "$expertModeFeatureList" == *"snesAR"* ]]; then
			SNESAR=43
		else
			SNESAR=83		
		fi
		if [[ "$expertModeFeatureList" == *"selectWideScreen"* ]]; then
			doSelectWideScreen=true			
		fi
		if [[ "$expertModeFeatureList" == *"setRASignIn"* ]]; then
			doRASignIn=true
		fi
		if [[ "$expertModeFeatureList" == *"setRAEnable"* ]]; then
			doRAEnable=true
		fi
		if [[ "$expertModeFeatureList" == *"doESDEThemePicker"* ]]; then
			doESDEThemePicker=true
		fi	
		

		if [[ $doInstallPowertools == true || $doInstallGyro == true || $isRealDeck == false ]]; then
			hasPass=$(passwd -S $(whoami) | awk -F " " '{print $2}' )
			if [[ $hasPass == "NP" ]]; then
				echo "You don't have a password set. Please set one now. once set, you will be prompted to enter it in a new window."
				passwd 
			fi
			PASSWD="$(zenity --password --title="Enter Deck User Password" 2>/dev/null)"
			echo $PASSWD | sudo -v -S 
		fi
		
	
	if [[ $doSelectEmulators == true ]]; then
		
		emuTable=()
		emuTable+=(TRUE "RetroArch")
		emuTable+=(TRUE "PrimeHack")
		emuTable+=(TRUE "PCSX2")
		emuTable+=(TRUE "RPCS3")
		emuTable+=(TRUE "Citra")
		emuTable+=(TRUE "Dolphin")
		emuTable+=(TRUE "Duckstation")
		emuTable+=(TRUE "PPSSPP")
		emuTable+=(TRUE "Yuzu")
		emuTable+=(TRUE "Cemu")
		emuTable+=(TRUE "Xemu")
		
		#Emulator selector
		text="`printf "What emulators do you want to install?"`"
		emusToInstall=$(zenity --list \
				--title="EmuDeck" \
				--height=500 \
				--width=250 \
				--ok-label="OK" \
				--cancel-label="Exit" \
				--text="${text}" \
				--checklist \
				--column="Select" \
				--column="Emulator" \
				"${emuTable[@]}" 2>/dev/null)
		clear
		ans=$?	
		if [ $ans -eq 0 ]; then
		
			if [[ "$emusToInstall" == *"RetroArch"* ]]; then
				doInstallRA=true
			fi
			if [[ "$emusToInstall" == *"PrimeHack"* ]]; then
				doInstallPrimeHacks=true
			fi
			if [[ "$emusToInstall" == *"PCSX2"* ]]; then
				doInstallPCSX2=true
			fi
			if [[ "$emusToInstall" == *"RPCS3"* ]]; then
				doInstallRPCS3=true
			fi
			if [[ "$emusToInstall" == *"Citra"* ]]; then
				doInstallCitra=true
			fi
			if [[ "$emusToInstall" == *"Dolphin"* ]]; then
				doInstallDolphin=true
			fi
			if [[ "$emusToInstall" == *"Duckstation"* ]]; then
				doInstallDuck=true
			fi
			if [[ "$emusToInstall" == *"PPSSPP"* ]]; then
				doInstallPPSSPP=true
			fi
			if [[ "$emusToInstall" == *"Yuzu"* ]]; then
				doInstallYuzu=true
			fi
			if [[ "$emusToInstall" == *"Cemu"* ]]; then
				doInstallCemu=true
			fi
			if [[ "$emusToInstall" == *"Xemu"* ]]; then
				doInstallXemu=true
			fi
			if [[ "$emusToInstall" == *"Xenia"* ]]; then
				doInstallXenia=false
			fi
			#if [[ "$emusToInstall" == *"MelonDS"* ]]; then
			#	doInstallMelon=true
			#fi
		
		
		else
			exit
		fi
	fi
	#We force new Cemu install if we detect an older version exists
	DIR=$romsPath/wiiu/roms/
	if [ -d "$DIR" ]; then	
		doInstallCemu=true	
	fi	
	

	if [[ $doSelectWideScreen == true ]]; then
		#Emulators screenHacks
		emuTable=()
		emuTable+=(TRUE "Dolphin")
		emuTable+=(TRUE "Duckstation")
		emuTable+=(TRUE "BeetlePSX")
		emuTable+=(TRUE "Dreamcast")

		text="`printf "Selected Emulators will use WideScreen Hacks"`"
		wideToInstall=$(zenity --list \
					--title="EmuDeck" \
					--height=500 \
					--width=250 \
					--ok-label="OK" \
					--cancel-label="Exit" \
					--text="${text}" \
					--checklist \
					--column="Widescreen?" \
					--column="Emulator" \
					"${emuTable[@]}"  2>/dev/null)
		clear
		ans=$?	
		if [ $ans -eq 0 ]; then
			
			if [[ "$wideToInstall" == *"Duckstation"* ]]; then
				duckWide=true
			else
				duckWide=false
			fi
			if [[ "$wideToInstall" == *"Dolphin"* ]]; then
				DolphinWide=true
			else
				DolphinWide=false
			fi
			if [[ "$wideToInstall" == *"Dreamcast"* ]]; then
				DreamcastWide=true
			else
				DreamcastWide=false
			fi		
			if [[ "$wideToInstall" == *"BeetlePSX"* ]]; then
				BeetleWide=true
				else
				BeetleWide=false
			fi				
					
			
		else		
			exit		
		fi			
	fi
	#We mark we've made a custom configuration for future updates
	echo "" > ~/emudeck/.custom
	
if [[ $doCustomEmulators == true ]]; then
	# Configuration that only appplies to previous users
	if [ -f "$SECONDTIME" ]; then
		#We make sure all the emus can write its saves outside its own folders.
		#Also needed for certain emus to open certain menus for adding rom directories in the front end.
		#flatpak override net.pcsx2.PCSX2 --filesystem=host --user
		flatpak override net.pcsx2.PCSX2 --share=network --user # for network access / online play
		flatpak override io.github.shiiion.primehack --filesystem=host --user
		flatpak override net.rpcs3.RPCS3 --filesystem=host --user
		flatpak override org.citra_emu.citra --filesystem=host --user
		flatpak override org.DolphinEmu.dolphin-emu --filesystem=host --user
		#flatpak override org.duckstation.DuckStation --filesystem=host --user
		#flatpak override org.libretro.RetroArch --filesystem=host --user
		#flatpak override org.ppsspp.PPSSPP --filesystem=host --user
		flatpak override org.yuzu_emu.yuzu --filesystem=host --user
		flatpak override app.xemu.xemu --filesystem=/run/media:rw --user
		flatpak override app.xemu.xemu --filesystem="$savesPath"xemu:rw --user

		installString='Updating'

		emuTable=()
		emuTable+=(TRUE "RetroArch")
		emuTable+=(TRUE "PrimeHack")
		emuTable+=(TRUE "PCSX2")
		emuTable+=(TRUE "RPCS3")
		emuTable+=(TRUE "Citra")
		emuTable+=(TRUE "Dolphin")
		emuTable+=(TRUE "Duckstation")
		emuTable+=(TRUE "PPSSPP")
		emuTable+=(TRUE "Yuzu")
		emuTable+=(TRUE "Cemu")
		emuTable+=(TRUE "Xemu")
		emuTable+=(TRUE "Steam Rom Manager")
		emuTable+=(TRUE "EmulationStation DE")

		text="`printf "<b>EmuDeck will overwrite the following Emulators configurations by default</b> \nWhich systems do you want <b>reconfigure</b>?\nWe recommend to keep all of them checked so everything gets updated and known issues are fixed.\n If you want to mantain any custom configuration on some emulator unselect its name on this list"`"
		emusToReset=$(zenity --list \
							--title="EmuDeck" \
							--height=500 \
							--width=250 \
							--ok-label="OK" \
							--cancel-label="Exit" \
							--text="${text}" \
							--checklist \
							--column="Reconfigure?" \
							--column="Emulator" \
							"${emuTable[@]}"  2>/dev/null)
		clear
		cat ~/dragoonDoriseTools/EmuDeck/logo.ans
		echo -e "EmuDeck ${version}"
		ans=$?
		if [ $ans -eq 0 ]; then
			
			if [[ "$emusToReset" == *"RetroArch"* ]]; then
				doUpdateRA=true
			fi
			if [[ "$emusToReset" == *"PrimeHack"* ]]; then
				doUpdatePrimeHacks=true
			fi
			if [[ "$emusToReset" == *"PCSX2"* ]]; then
				doUpdatePCSX2=true
			fi
			if [[ "$emusToReset" == *"RPCS3"* ]]; then
				doUpdateRPCS3=true
			fi
			if [[ "$emusToReset" == *"Citra"* ]]; then
				doUpdateCitra=true
			fi
			if [[ "$emusToReset" == *"Dolphin"* ]]; then
				doUpdateDolphin=true
			fi
			if [[ "$emusToReset" == *"Duckstation"* ]]; then
				doUpdateDuck=true
			fi
			if [[ "$emusToReset" == *"PPSSPP"* ]]; then
				doUpdatePPSSPP=true
			fi
			if [[ "$emusToReset" == *"Yuzu"* ]]; then
				doUpdateYuzu=true
			fi
			if [[ "$emusToReset" == *"Cemu"* ]]; then
				doUpdateCemu=true
			fi
			if [[ "$emusToReset" == *"Xemu"* ]]; then
				doUpdateXemu=true
			fi
			if [[ "$emusToReset" == *"Xenia"* ]]; then
				doUpdateXenia=false #false until we add above
			fi
			#if [[ "$emusToReset" == *"MelonDS"* ]]; then
			#	doUpdateMelon=false
			#fi
			if [[ "$emusToReset" == *"Steam Rom Manager"* ]]; then
				doUpdateSRM=true
			fi
			if [[ "$emusToReset" == *"EmulationStation DE"* ]]; then
				doUpdateESDE=true
			fi
			
			
			else
				echo ""
			fi
			
		fi
	fi
else
	#easy mode settings
	doInstallRA=true
	doInstallDolphin=true
	doInstallPCSX2=true
	doInstallRPCS3=true
	doInstallYuzu=true
	doInstallCitra=true
	doInstallDuck=true
	doInstallCemu=true
	doInstallXenia=false
	doInstallPrimeHacks=true
	doInstallPPSSPP=true
	doInstallXemu=true
	#doInstallMelon=true

fi # end Expert if

##
##
## End of configuration
##	
##
	
	
	
	
##
##
## Start of installation
##	
##


#ESDE Installation
if [ $doInstallESDE == true ]; then
	installESDE		
fi
	
#SRM Installation
if [ $doInstallSRM == true ]; then
	installSRM
fi

#Support for non-valve hardware.
if [[ $isRealDeck == false ]]; then
	 setUpHolo
fi

#Emulators Installation
if [ $doInstallPCSX2 == "true" ]; then	
	installEmuFP "PCSX2" "net.pcsx2.PCSX2"		
fi
if [ $doInstallPrimeHacks == "true" ]; then
	installEmuFP "PrimeHack" "io.github.shiiion.primehack"		
fi
if [ $doInstallRPCS3 == "true" ]; then
	installEmuFP "RPCS3" "net.rpcs3.RPCS3"		
fi
if [ $doInstallCitra == "true" ]; then
	installEmuFP "Citra" "org.citra_emu.citra"		
fi
if [ $doInstallDolphin == "true" ]; then
	installEmuFP "Dolphin" "org.DolphinEmu.dolphin-emu"		
fi
if [ $doInstallDuck == "true" ]; then
	installEmuFP "DuckStation" "org.duckstation.DuckStation"		
fi
if [ $doInstallRA == "true" ]; then
	installEmuFP "RetroArch" "org.libretro.RetroArch"		
fi
if [ $doInstallPPSSPP == "true" ]; then
	installEmuFP "PPSSPP" "org.ppsspp.PPSSPP"		
fi
if [ $doInstallYuzu == "true" ]; then
	installEmuFP "Yuzu" "org.yuzu_emu.yuzu"		
fi
if [ $doInstallXemu == "true" ]; then
	installEmuFP "Xemu" "app.xemu.xemu"		
fi




#Cemu - We need to install Cemu after creating the Roms folders!
if [ $doInstallCemu == "true" ]; then
	setMSG "Installing Cemu"		
	FILE="${romsPath}/wiiu/Cemu.exe"	
	if [ -f "$FILE" ]; then
		echo "" 2>/dev/null
	else
		curl https://cemu.info/releases/cemu_1.26.2.zip --output $romsPath/wiiu/cemu_1.26.2.zip 
		mkdir -p $romsPath/wiiu/tmp
		unzip -o "$romsPath"/wiiu/cemu_1.26.2.zip -d "$romsPath"/wiiu/tmp 
		mv "$romsPath"/wiiu/tmp/*/* "$romsPath"/wiiu 
		rm -rf "$romsPath"/wiiu/tmp 
		rm -f "$romsPath"/wiiu/cemu_1.26.2.zip 		
	fi

	#because this path gets updated by sed, we really should be installing it every time and allowing it to be updated every time. In case the user changes their path.
	cp ~/dragoonDoriseTools/EmuDeck/tools/proton-launch.sh "${toolsPath}"proton-launch.sh
	chmod +x "${toolsPath}"proton-launch.sh
	cp ~/dragoonDoriseTools/EmuDeck/tools/launchers/cemu.sh "${toolsPath}"launchers/cemu.sh
	sed -i "s|/run/media/mmcblk0p1/Emulation/tools|${toolsPath}|" "${toolsPath}"launchers/cemu.sh
	sed -i "s|/run/media/mmcblk0p1/Emulation/roms/wiiu|${romsPath}wiiu|" "${toolsPath}"launchers/cemu.sh
	chmod +x "${toolsPath}"launchers/cemu.sh

	#Commented until we get CEMU flatpak working
	#echo -e "EmuDeck will add Witherking25's flatpak repo to your Discorver App.this is required for cemu now"	
	#flatpak remote-add --user --if-not-exists withertech https://repo.withertech.com/flatpak/withertech.flatpakrepo 
	#flatpak install withertech info.cemu.Cemu -y 
	#flatpak install flathub org.winehq.Wine -y 
	#
	##We move roms to the new path
	#DIR=$romsPath/wiiu/roms/
	#if [ -d "$DIR" ]; then			
	#	echo -e "Moving your WiiU games and configuration to the new Cemu...This might take a while"
	#	mv $romsPath/wiiu/roms/ $romsPath/wiiutemp 
	#	mv $romsPath/wiiu/Cemu.exe $romsPath/wiiu/Cemu.bak 
	#	rsync -ri $romsPath/wiiu/ ~/.var/app/info.cemu.Cemu/data/cemu/ 
	#	mv $romsPath/wiiu/ $romsPath/wiiu_delete_me 
	#	mv $romsPath/wiiutemp/ $romsPath/wiiu/ 
	#	
	#	zenity --info \
	#	   --title="EmuDeck" \
	#	   --width=250 \
	#	   --text="We have updated your CEMU installation, you will need to open Steam Rom Manager and add your Wii U games again. This time you don't need to set CEMU to use Proton ever again :)" 2>/dev/null
	#	   
	#fi
	
fi

#Xenia - We need to install Xenia after creating the Roms folders!
if [ $doInstallXenia == "true" ]; then
	setMSG "Installing Xenia"		
	FILE="${romsPath}/xbox360/xenia.exe"	
	if [ -f "$FILE" ]; then
		echo "" 2>/dev/null
	else
		curl -L https://github.com/xenia-project/release-builds-windows/releases/latest/download/xenia_master.zip --output $romsPath/xbox360/xenia_master.zip 
		mkdir -p $romsPath/xbox360/tmp
		unzip -o "$romsPath"/xbox360/xenia_master.zip -d "$romsPath"/xbox360/tmp 
		mv "$romsPath"/xbox360/tmp/* "$romsPath"/xbox360 
		rm -rf "$romsPath"/xbox360/tmp 
		rm -f "$romsPath"/xbox360/xenia_master.zip 		
	fi
	
fi

#Steam RomManager Config

if [ $doUpdateSRM == true ]; then
	configSRM
fi

#ESDE Config
if [ $doUpdateESDE == true ]; then
	configESDE
fi	

#Emus config
setMSG "Configuring Steam Input for emulators.."
rsync -r ~/dragoonDoriseTools/EmuDeck/configs/steam-input/ ~/.steam/steam/controller_base/templates/

setMSG "Configuring emulators.."
echo -e ""
if [ $doUpdateRA == true ]; then

	mkdir -p ~/.var/app/org.libretro.RetroArch
	mkdir -p ~/.var/app/org.libretro.RetroArch/config
	mkdir -p ~/.var/app/org.libretro.RetroArch/config/retroarch
	
	RACores
	
	raConfigFile=~/.var/app/org.libretro.RetroArch/config/retroarch/retroarch.cfg
	FILE=~/.var/app/org.libretro.RetroArch/config/retroarch/retroarch.cfg.bak
	if [ -f "$FILE" ]; then
		echo -e "" 2>/dev/null
	else
		setMSG "Backing up RA..."
		cp ~/.var/app/org.libretro.RetroArch/config/retroarch/retroarch.cfg ~/.var/app/org.libretro.RetroArch/config/retroarch/retroarch.cfg.bak 	
	fi
	#mkdir -p ~/.var/app/org.libretro.RetroArch/config/retroarch/overlays
	
	#Cleaning up cfg files that the user could have created on Expert mode
	find ~/.var/app/org.libretro.RetroArch/config/retroarch/config/ -type f -name "*.cfg" | while read f; do rm -f "$f"; done 
	find ~/.var/app/org.libretro.RetroArch/config/retroarch/config/ -type f -name "*.bak" | while read f; do rm -f "$f"; done 
	
	rsync -r ~/dragoonDoriseTools/EmuDeck/configs/org.libretro.RetroArch/config/ ~/.var/app/org.libretro.RetroArch/config/
	
	sed -i "s|/run/media/mmcblk0p1/Emulation|${emulationPath}|g" $raConfigFile	
	
fi
echo -e ""
setMSG "Applying Emu configurations..."
if [ $doUpdatePrimeHacks == true ]; then
	configEmuFP "PrimeHack" "io.github.shiiion.primehack"
	sed -i "s|/run/media/mmcblk0p1/Emulation/roms/|${romsPath}|g" ~/.var/app/io.github.shiiion.primehack/config/dolphin-emu/Dolphin.ini
fi
if [ $doUpdateDolphin == true ]; then
	configEmuFP "Dolphin" "org.DolphinEmu.dolphin-emu"
	sed -i "s|/run/media/mmcblk0p1/Emulation/roms/|${romsPath}|g" ~/.var/app/org.DolphinEmu.dolphin-emu/config/dolphin-emu/Dolphin.ini
fi
if [ $doUpdatePCSX2 == true ]; then
	configEmuFP "PCSX2" "net.pcsx2.PCSX2"
	#Bios Fix
	sed -i "s|/run/media/mmcblk0p1/Emulation/bios|${biosPath}|g" ~/.var/app/net.pcsx2.PCSX2/config/PCSX2/inis/PCSX2_ui.ini 
fi
if [ $doUpdateRPCS3 == true ]; then
	configEmuFP "RPCS3" "net.rpcs3.RPCS3"
	#HDD Config
	sed -i 's| $(EmulatorDir)dev_hdd0/| '$savesPath'/rpcs3/dev_hdd0/|g' /home/deck/.var/app/net.rpcs3.RPCS3/config/rpcs3/vfs.yml 
	mkdir -p $savesPath/rpcs3/ 
fi
if [ $doUpdateCitra == true ]; then
	configEmuFP "Citra" "org.citra_emu.citra"
	#Roms Path
	sed -i "s|/run/media/mmcblk0p1/Emulation/roms/|${romsPath}|g" ~/.var/app/org.citra_emu.citra/config/citra-emu/qt-config.ini
fi
if [ $doUpdateDuck == true ]; then
	configEmuFP "DuckStation" "org.duckstation.DuckStation"
	#Bios Path
	sed -i "s|/run/media/mmcblk0p1/Emulation/bios/|${biosPath}|g" ~/.var/app/org.duckstation.DuckStation/data/duckstation/settings.ini
fi
if [ $doUpdateYuzu == true ]; then
	configEmuFP "Yuzu" "org.yuzu_emu.yuzu"
	#Roms Path
	sed -i "s|/run/media/mmcblk0p1/Emulation/roms/|${romsPath}|g" ~/.var/app/org.yuzu_emu.yuzu/config/yuzu/qt-config.ini
fi

if [ $doUpdatePPSSPP == true ]; then
	configEmuFP "PPSSPP" "org.ppsspp.PPSSPP"
fi
if [ $doUpdateXemu == true ]; then
	configEmuFP "Xemu" "app.xemu.xemu"	
	#Bios Fix
	sed -i "s|/run/media/mmcblk0p1/Emulation/bios/|${biosPath}|g" ~/.var/app/app.xemu.xemu/data/xemu/xemu/xemu.ini
	sed -i "s|/run/media/mmcblk0p1/Emulation/bios/|${biosPath}|g" ~/.var/app/app.xemu.xemu/data/xemu/xemu/xemu.toml
	sed -i "s|/run/media/mmcblk0p1/Emulation/saves/|${savesPath}|g" ~/.var/app/app.xemu.xemu/data/xemu/xemu/xemu.toml
fi

#Proton Emus
if [ $doUpdateCemu == true ]; then
	echo "" 
	#Commented until we get CEMU flatpak working
	#rsync -avhp ~/dragoonDoriseTools/EmuDeck/configs/info.cemu.Cemu/ ~/.var/app/info.cemu.Cemu/ 
	rsync -avhp ~/dragoonDoriseTools/EmuDeck/configs/info.cemu.Cemu/data/cemu/ "$romsPath"/wiiu 
	sed -i "s|/run/media/mmcblk0p1/Emulation/roms/|${romsPath}|g" "$romsPath"/wiiu/settings.xml 
fi
if [ $doUpdateXenia == true ]; then
	echo "" 
	rsync -avhp ~/dragoonDoriseTools/EmuDeck/configs/xenia/ "$romsPath"/xbox360 
fi




cd $(echo $biosPath | tr -d '\r')
cd yuzu
ln -sn ~/.var/app/org.yuzu_emu.yuzu/data/yuzu/keys/ ./keys 
ln -sn ~/.var/app/org.yuzu_emu.yuzu/data/yuzu/nand/system/Contents/registered/ ./firmware 

#Fixes repeated Symlink for older installations
cd ~/.var/app/org.yuzu_emu.yuzu/data/yuzu/keys/
unlink keys 
cd ~/.var/app/org.yuzu_emu.yuzu/data/yuzu/nand/system/Contents/registered/
unlink registered 



#
##
##End of installation
##
#


#
##
##Validations
##
#

#PS Bios
checkPSBIOS

#Yuzu Keys & Firmware
FILE=~/.var/app/org.yuzu_emu.yuzu/data/yuzu/keys/prod.keys
if [ -f "$FILE" ]; then
	echo -e "" 2>/dev/null
else
		
	text="`printf "<b>Yuzu is not configured</b>\nYou need to copy your Keys and firmware to: \n${biosPath}yuzu/keys\n${biosPath}yuzu/firmware\n\nMake sure to copy your files inside the folders. <b>Do not overwrite them</b>"`"
	zenity --error \
			--title="EmuDeck" \
			--width=400 \
			--text="${text}" 2>/dev/null
fi


##
##
## RetroArch Customizations.
##
##


#RA Bezels	
RABezels

#RA SNES Aspect Ratio
RASNES

#RA AutoSave	
RAautoSave


##
##
## Other Customizations.
##
##

#Widescreen hacks
setWide

#We move all the saved folders to the emulation path
createSaveFolders

#RetroAchievments
RAAchievment

if [ $doInstallCHD == true ]; then
	installCHD
fi

if [ $doInstallGyro == true ]; then	
		InstallGyro=$(bash <(curl -sL https://github.com/kmicki/SteamDeckGyroDSU/raw/master/pkg/update.sh))
		echo $InstallGyro 
fi

if [ $doInstallPowertools == true ]; then
	installPowerTools	
fi

if [ $branch == 'main' ];then
	createDesktopIcons
fi

setMSG "Cleaning up downloaded files..."	
rm -rf ~/dragoonDoriseTools	
clear

# We mark the script as finished	
echo "" > ~/emudeck/.finished
echo "100" > ~/emudeck/msg.log
echo "# Installation Complete" >> ~/emudeck/msg.log
finished=true

text="`printf "<b>Done!</b>\n\nRemember to add your games here:\n<b>${romsPath}</b>\nAnd your Bios (PS1, PS2, Yuzu) here:\n<b>${biosPath}</b>\n\nOpen Steam Rom Manager on your Desktop to add your games to your SteamUI Interface.\n\nThere is a bug in RetroArch that if you are using Bezels you can not set save configuration files unless you close your current game. Use overrides for your custom configurations or use expert mode to disabled them\n\nIf you encounter any problem please visit our Discord:\n<b>https://discord.gg/b9F7GpXtFP</b>\n\nTo Update EmuDeck in the future, just run this App again.\n\nEnjoy!"`"

zenity --question \
		 --title="EmuDeck" \
		 --width=450 \
		 --ok-label="Open Steam Rom Manager" \
		 --cancel-label="Exit" \
		 --text="${text}" 2>/dev/null
ans=$?
if [ $ans -eq 0 ]; then
	kill -15 `pidof steam`
	cd ${toolsPath}/srm
	./Steam-ROM-Manager.AppImage
	zenity --question \
		 --title="EmuDeck" \
		 --width=350 \
		 --text="Return to Game Mode?" \
		 --ok-label="Yes" \
		 --cancel-label="No" 2>/dev/null
	ans2=$?
	if [ $ans2 -eq 0 ]; then
		qdbus org.kde.Shutdown /Shutdown org.kde.Shutdown.logout
	fi
	exit
else
	exit
	echo -e "Exit" 2>/dev/null
fi
