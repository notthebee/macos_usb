#!/bin/bash
# Create a bootable macOS flash drive on Linux
# (c) notthebee, corpnewt
# url: https://github.com/notthebee/macos_usb

function checkdep {
	# check if running on Linux
	if [[ "$OSTYPE" != "linux-gnu" ]]; then
		echo "This script will only run on Linux-based operating systems!"
	fi

	# check for 7zip
	if [ -z "$(7z | grep 7-Zip)" ]; then
		echo "Please install p7zip"
		exit 1 
	fi

	# check for git
	if ! git --version > /dev/null 2>&1; then
		echo "Please install git"
		exit 1
	fi
	if ! python --version > /dev/null 2>&1; then
		echo "Please install python"
		exit 1
	fi
	
}

function gibmacos {
	echo "Fetching latest gibMacOS by corpnewt"
	git clone "https://github.com/corpnewt/gibMacOS" > /dev/null 2>&1
	python gibMacOS/gibMacOS.command -r -l
}

function unpackhfs {
	# Store the name of the file in a variable
	hfsfile="$(find . -type f -name '4.hfs' -o -name '5.hfs')"
	if [ -z "$hfsfile" ]; then
		echo "Unpacking the installation files"
		mv gibMacOS/macOS\ Downloads/publicrelease/*/*.pkg .
		7z e -txar *.pkg *.dmg; 7z e *.dmg */Base*; 7z e -tdmg Base*.dmg *.hfs
	else
		echo "Already unpacked"
	fi
}

function partition {
	# if we don't have the HFS file at this point,
	# let's not bother partitioning the drive
	hfsfile="$(find . -type f -name '4.hfs' -o -name '5.hfs')"
	# assigning the variable twice is the only way i was able to make it work
	# if you know a better way, please let me know
	if [ -z "$hfsfile" ]; then
		echo "ERROR! HFS image not found"
		exit 1
	fi
	lsblk
	printf "\nEnter the path to your flash drive (e.g. /dev/sdb)"
	printf "\nDOUBLE CHECK THE EXACT PATH WITH lsblk or diskutil\n"
	read flashdrive 2>/dev/tty
	usb="$(readlink /sys/block/$(echo ${flashdrive} | sed 's/^\/dev\///') | grep -o usb)"
	if [ -z ${usb} ]; then
		echo "WARNING! ${flashdrive} is NOT a USB device"
		echo "Are you sure you know what you're doing?"
		read -p " [Y/N] " answer 2>/dev/tty
		if [ ! "${answer^^}" == "Y" ]; then
			echo "Abort"
			exit 0
		fi	
	fi
	sudo umount ${flashdrive}*
	sudo sgdisk --zap-all ${flashdrive}
	sudo sgdisk -n 0:0:+200MiB -t 0:0700 ${flashdrive}
	sudo sgdisk -n 0:0:0 -t 0:af00 ${flashdrive}
	sudo mkfs.vfat -F 32 -n "CLOVER" ${flashdrive}1
}


function burn {
	echo "Flashing the image"
	sudo dd if=${hfsfile} of=${flashdrive}2 bs=8M status=progress oflag=sync
}

checkdep
gibmacos
unpackhfs
partition
burn

echo "Success!"
echo "Don't forget to install the Clover bootloader!"
