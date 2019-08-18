#!/bin/bash
# Create a bootable macOS flash drive on Linux and macOS
# (c) notthebee, corpnewt
# url: https://github.com/notthebee/macos_usb

function checkdep {
	# check if running on Linux or macOS
	case "$OSTYPE" in
		"linux-gnu"|"darwin"*)
			;;
		*)
			echo "This script will only run on Linux or macOS!"
			exit 1
			;;
	esac


	for n in git python 7z lsblk find grep sgdisk mkfs.vfat sed readlink dd; do
		if ! $n --help > /dev/null 2>&1; then
			echo "Please install $n"
			exit 1
		fi
	done
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

	# Execute diskutil list if running on macOS
	lsblk 2>/dev/null || diskutil list
	printf "\nEnter the path to your flash drive (e.g. /dev/sdb or /dev/disk3)"
	printf "\nDOUBLE CHECK THE EXACT PATH WITH lsblk or diskutil\n"
	read flashdrive 2>/dev/tty

	# Check if user specified a USB device
	if [[ "$OSTYPE" == "linux-gnu" ]]; then
		usb="$(readlink /sys/block/$(echo ${flashdrive} | sed 's/^\/dev\///') | grep -o usb)"
	elif [[ "$OSTYPE" == "darwin"* ]]; then
		usb=$(diskutil list | grep -e ".*$flashdrive.*external")
	fi

	if [ -z "$usb" ]; then
		echo "WARNING! ${flashdrive} is NOT a USB device"
		echo "Are you sure you know what you're doing?"
		read -p " [Y/N] " answer 2>/dev/tty
		if [[ ! $answer =~ ^[Yy]$ ]]; then
			echo "Abort"
			exit 0
		fi	
	fi

	# Destroy the GPT and partition the drive anew 
	if [[ "$OSTYPE" == "linux-gnu" ]]; then
		sudo umount ${flashdrive}*
		sudo sgdisk --zap-all ${flashdrive}
		sudo sgdisk -n 0:0:+200MiB -t 0:0700 ${flashdrive}
		sudo sgdisk -n 0:0:0 -t 0:af00 ${flashdrive}
		sudo mkfs.vfat -F 32 -n "CLOVER" ${flashdrive}1

	elif [[ "$OSTYPE" == "darwin"* ]]; then
		sudo diskutil eraseDisk JHFS+ INSTALL ${flashdrive}
		sudo diskutil umountDisk ${flashdrive}
	fi
}

function burn {
	echo "Flashing the image"
	sudo dd if=${hfsfile} of=${flashdrive}2 bs=8M status=progress oflag=sync 2>/dev/null || sudo dd if=${hfsfile} of=${flashdrive}s2 bs=8m
}


checkdep
gibmacos
unpackhfs
partition
burn

echo "Success!"
echo "Don't forget to install the Clover bootloader in case you plan to use the media on a non-Apple computer!"
