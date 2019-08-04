#!/bin/bash
# Semi-automatic script to create a bootable macOS flash drive on Linux
# (c) notthebee, myspaghetti, licensed under GPL2.0 or higher
# url: https://github.com/notthebee/macos_usb

# Dependencies: bash >= 4.0, unzip, wget, dmg2img

white_on_red="\e[48;2;255;0;0m\e[38;2;255;255;255m"
white_on_black="\e[48;2;0;0;9m\e[38;2;255;255;255m"
default_color="\033[0m"

# check dependencies
function check_dependencies() {
# check if running on macOS and non-GNU coreutils
if [ -n "$(sw_vers 2>/dev/null)" -a -z "$(csplit --help 2>/dev/null)" ]; then
    echo ""
    printf 'macOS detected. Please use a package manager such as '"${white_on_black}"'homebrew'"${default_color}"', '"${white_on_black}"'nix'"${default_color}"', or '"${white_on_black}"'MacPorts'"${default_color}"'.\n'
    echo "Please make sure the following packages are installed and that"
    echo "their path is in the PATH variable:"
    printf "${white_on_black}"'bash  coreutils  wget  unzip  dmg2img'"${default_color}"'\n'
    echo "Please make sure bash and coreutils are the GNU variant."
    exit
fi

# check Bash version
if [ -z "${BASH_VERSION}" ]; then
    echo "Can't determine BASH_VERSION. Exiting."
    exit
elif [ "${BASH_VERSION:0:1}" -lt 4 ]; then
    echo "Please run this script on BASH 4.0 or higher."
    exit
fi

# check for unzip, coreutils, wget
if [ -z "$(unzip -hh 2>/dev/null)" \
     -o -z "$(csplit --help 2>/dev/null)" \
     -o -z "$(wget --version 2>/dev/null)" ]; then
    echo "Please make sure the following packages are installed:"
    echo "coreutils   unzip   wget"
    echo "Please make sure coreutils is the GNU variant."
    exit
fi

# wget supports --show-progress from version 1.16
if [[ "$(wget --version 2>/dev/null | head -n 1)" =~ 1\.1[6-9]|1\.2[0-9] ]]; then
    wgetargs="--quiet --continue --show-progress"  # pretty
else
    wgetargs="--continue"  # ugly
fi

# dmg2img
if [ -z "$(dmg2img -d 2>/dev/null)" ]; then
    if [ -z "$(cygcheck -V 2>/dev/null)" ]; then
        echo "Please install the package dmg2img."
        exit
    elif [ -z "$(${PWD}/dmg2img -d 2>/dev/null)" ]; then
        echo "Locally installing dmg2img"
        wget "http://vu1tur.eu.org/tools/dmg2img-1.6.6-win32.zip" \
             ${wgetargs} \
             --output-document="dmg2img-1.6.6-win32.zip"
        if [ ! -s dmg2img-1.6.6-win32.zip ]; then
             echo "Error downloading dmg2img. Please provide the package manually."
             exit
        fi
        unzip -oj "dmg2img-1.6.6-win32.zip" "dmg2img.exe"
        rm "dmg2img-1.6.6-win32.zip"
        chmod +x "dmg2img.exe"
    fi
fi

# prompt for macOS version
HighSierra_sucatalog='https://swscan.apple.com/content/catalogs/others/index-10.13-10.12-10.11-10.10-10.9-mountainlion-lion-snowleopard-leopard.merged-1.sucatalog'
Mojave_sucatalog='https://swscan.apple.com/content/catalogs/others/index-10.14-10.13-10.12-10.11-10.10-10.9-mountainlion-lion-snowleopard-leopard.merged-1.sucatalog'
Catalina_beta_sucatalog='https://swscan.apple.com/content/catalogs/others/index-10.15seed-10.15-10.14-10.13-10.12-10.11-10.10-10.9-mountainlion-lion-snowleopard-leopard.merged-1.sucatalog'
# Catalina public release not yet available
# Catalina_sucatalog='https://swscan.apple.com/content/catalogs/others/index-10.15-10.14-10.13-10.12-10.11-10.10-10.9-mountainlion-lion-snowleopard-leopard.merged-1.sucatalog'
printf "${white_on_black}"'
Press a key to select the macOS version to install on the virtual machine:'"${default_color}"'
 [H]igh Sierra (10.13)
 [M]ojave (10.14)
 [C]atalina (10.15 beta)
'
read -n 1 -p " [H/M/C] " macOS_release_name 2>/dev/tty
echo ""
if [ "${macOS_release_name^^}" == "H" ]; then
    macOS_release_name="HighSierra"
    CFBundleShortVersionString="10.13"
    sucatalog="${HighSierra_sucatalog}"
elif [ "${macOS_release_name^^}" == "M" ]; then
    macOS_release_name="Mojave"
    CFBundleShortVersionString="10.14"
    sucatalog="${Mojave_sucatalog}"
else
    macOS_release_name="Catalina"
    CFBundleShortVersionString="10.15"
    sucatalog="${Catalina_beta_sucatalog}"
fi
echo "${macOS_release_name} selected"
}
# Done with dependencies

function prepare_macos_installation_files() {
# Find the correct download URL in the Apple catalog
echo ""
echo "Downloading Apple macOS ${macOS_release_name} software update catalog"
wget "${sucatalog}" \
     ${wgetargs} \
     --output-document="${macOS_release_name}_sucatalog"

# if file was not downloaded correctly
if [ ! -s "${macOS_release_name}_sucatalog" ]; then
    wget --debug -O /dev/null -o "${macOS_release_name}_wget.log" "${sucatalog}"
    echo ""
    echo "Couldn't download the Apple software update catalog."
    if [ "$(expr match "$(cat "${macOS_release_name}_wget.log")" '.*ERROR[[:print:]]*is not trusted')" -gt "0" ]; then
        printf '
Make sure certificates from a certificate authority are installed.
Certificates are often installed through the package manager with
a package named '"${white_on_black}"'ca-certificates'"${default_color}"
    fi
    echo "Exiting."
    exit
fi
echo "Trying to find macOS ${macOS_release_name} InstallAssistant download URL"
tac "${macOS_release_name}_sucatalog" | csplit - '/InstallAssistantAuto.smd/+1' '{*}' -f "${macOS_release_name}_sucatalog_" -s
for catalog in "${macOS_release_name}_sucatalog_"* "error"; do
    if [[ "${catalog}" == error ]]; then
        rm "${macOS_release_name}_sucatalog"*
        printf "Couldn't find the requested download URL in the Apple catalog. Exiting."
       exit
    fi
    urlbase="$(tail -n 1 "${catalog}" 2>/dev/null)"
    urlbase="$(expr match "${urlbase}" '.*\(http://[^<]*/\)')"
    wget "${urlbase}InstallAssistantAuto.smd" \
    ${wgetargs} \
    --output-document="${catalog}_InstallAssistantAuto.smd"
    found_version="$(head -n 6 "${catalog}_InstallAssistantAuto.smd" | tail -n 1)"
    if [[ "${found_version}" == *${CFBundleShortVersionString}* ]]; then
        echo "Found download URL: ${urlbase}"
        echo ""
        rm "${macOS_release_name}_sucatalog"*
        break
    fi
done
echo "Downloading macOS installation files from swcdn.apple.com"
for filename in "BaseSystem.chunklist" \
                "InstallInfo.plist" \
                "AppleDiagnostics.dmg" \
                "AppleDiagnostics.chunklist" \
                "BaseSystem.dmg" \
                "InstallESDDmg.pkg"; \
    do wget "${urlbase}${filename}" \
            ${wgetargs} \
            --output-document "${macOS_release_name}_${filename}"
done
echo ""
echo "Downloading open-source APFS EFI drivers"
wget 'https://github.com/acidanthera/AppleSupportPkg/releases/download/2.0.4/AppleSupport-v2.0.4-RELEASE.zip' \
    ${wgetargs} \
    --output-document 'AppleSupport-v2.0.4-RELEASE.zip'
unzip -oj 'AppleSupport-v2.0.4-RELEASE.zip'
echo ""
echo "Creating EFI startup script"
echo 'echo -off
load fs0:\EFI\driver\AppleImageLoader.efi
load fs0:\EFI\driver\AppleUiSupport.efi
load fs0:\EFI\driver\ApfsDriverLoader.efi
map -r
for %a run (1 5)
  fs%a:
  cd "macOS Install Data\Locked Files\Boot Files"
  boot.efi
  cd "System\Library\CoreServices"
  boot.efi
endfor' > "startup.nsh"
}

function create_macos_installation_files_viso() {
echo "Crating ISO"
echo ""
echo "Splitting the several-GB InstallESDDmg.pkg into 1GB parts because"
echo "VirtualBox hasn't implemented UDF/HFS VISO support yet and macOS"
echo "doesn't support ISO 9660 Level 3 with files larger than 2GB."
split -a 2 -d -b 1000000000 "${macOS_release_name}_InstallESDDmg.pkg" "${macOS_release_name}_InstallESD.part"
echo "--iprt-iso-maker-file-marker-bourne-sh 57c0ec7d-2112-4c24-a93f-32e6f08702b9
--volume-id=${macOS_release_name:0:5}-files
/AppleDiagnostics.chunklist=${macOS_release_name}_AppleDiagnostics.chunklist
/AppleDiagnostics.dmg=${macOS_release_name}_AppleDiagnostics.dmg
/BaseSystem.chunklist=${macOS_release_name}_BaseSystem.chunklist
/BaseSystem.dmg=${macOS_release_name}_BaseSystem.dmg
/InstallInfo.plist=${macOS_release_name}_InstallInfo.plist
/ApfsDriverLoader.efi=ApfsDriverLoader.efi
/AppleImageLoader.efi=AppleImageLoader.efi
/AppleUiSupport.efi=AppleUiSupport.efi
/startup.nsh=startup.nsh" > "${macOS_release_name}_installation_files.viso"
for part in "${macOS_release_name}_InstallESD.part"*; do
    echo "/InstallESD${part##*InstallESD}=${part}" >> "${macOS_release_name}_installation_files.img"
done

}

welcome
check_dependencies
prepare_macos_installation_files
create_macos_installation_files_viso
