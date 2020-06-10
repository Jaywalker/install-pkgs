#!/bin/sh
# Jaywalker's MultiSystem Package Installer Script
# by Jaywalker
# Originally based on larbs.sh from LukeSmithxyz/LARBS
# Modified to be an pkg installer only, rather than a system setup + pkg installer.
# Expects to be ran on a system setup with one of my corresponding setup scripts.
# License: GNU GPLv3

### OPTIONS AND VARIABLES ###

while getopts ":a:r:b:p:h" o; do case "${o}" in
	h) printf "Optional arguments for custom use:\\n  -p: Dependencies and programs csv (local file or url)\\n  -a: AUR helper (must have pacman-like syntax)\\n  \\n  -h: Show this message\\n" && exit ;;
	p) progsfile=${OPTARG} ;;
	a) aurhelper=${OPTARG} ;;
	*) printf "Invalid option: -%s\\n" "$OPTARG" && exit ;;
esac done

# DEFAULTS:
[ -z "$progsfile" ] && progsfile="https://raw.githubusercontent.com/Jaywalker/dotfiles/master/.config/progs.csv"
[ -z "$aurhelper" ] && aurhelper="yay"
repodir="$HOME/.local/src"

### FUNCTIONS ###

#Detect system and setup the installpkg function accordingly
if type xbps-install >/dev/null 2>&1; then
	installpkg(){ sudo xbps-install -y "$1" >/dev/null 2>&1 ;}
	grepseq="\"^pip,\|^git,\|^void,\|^,\""
elif type pacman >/dev/null 2>&1; then
	distro="arch"
	installpkg(){ sudo pacman --noconfirm --needed -S "$1" >/dev/null 2>&1 ;}
	grepseq="\"^pip,\|^git,\|^AUR,\|^pacman,\|^,\""
elif type pkg >/dev/null 2>&1; then
	distro="bsd"
	grepseq="\"^pip,\|^git,\|^OBSD,\|^,\""
	case "$(uname -sp)" in
		"Darwin arm"*)
			distro="iOS"
			grepseq="\"^git,\|^Apkg,\|^,\""
			;;
		"Darwin "*)
			distro="macOS"
			grepseq="\"^pip,\|^git,\|^Apkg,\|^mas,\|^,\""
			;;
	esac
	installpkg() { pkg install "$1" >/dev/null 2>&1 ;}
elif [ "$(uname -sp)" = "Darwin i386" ]; then
	distro="macOS"
	# Don't worry, if it's not really there, we install it first
	installpkg() { brew install "$1" >/dev/null 2>&1 ;}
	grepseq="\"^pip,\|^git,\|^brew,\|^cask,\|^tap,\|^mas,\|^,\""
elif type apt >/dev/null 2>&1; then
	distro="debian"
	grepseq="\"^pip,\|^git,\|^deb,\|^,\""
	case "$(uname -sp)" in
		"Darwin arm"*)
			distro="iOS"
			grepseq="\"^git,\|^iOS,\|^,\""
			;;
	esac
	installpkg(){ sudo apt-get install -y "$1" >/dev/null 2>&1 ;}
else
	echo "Unsupported system! No known package manager. Failing."
	exit 1
fi

error() { clear; printf "ERROR: %s\\n" "$1"; exit;}

welcomemsg() {
	if [ "$distro" = arch ]; then
		dialog --colors --title "Ready to install?" --yes-label "All ready!" --no-label "Uh, not yet.." --yesno "Be sure the computer you are using has current pacman updates and refreshed Arch keyrings.\\n\\nIf it does not, the installation of some programs might fail." 8 70
	elif [ "$distro" = macOS ]; then
		dialog --colors --title "Ready to install?" --yes-label "All ready!" --no-label "Uh, not yet.." --yesno "Be sure you are using this script with access to the macOS desktop GUI and you are properly authenticated with the macOS App Store.\\n\\nIf you are not, the installation of some programs might fail." 8 70
	else
		dialog --colors --title "Ready to install?" --yes-label "All ready!" --no-label "Uh, not yet.." --yesno "Hi. There are no special instructions for this platform\\n\\nThis script will install the programs specified in progs.csv for this platform. Sound good?" 8 70
	fi
}

usercheck() {
	if [ "$(id -u)" -eq 0 ]; then echo "This script must be ran as a non-root user with sudo privileges." ; exit 1 ; fi
	echo "Checking for sudo powers..."
	if [ "$(sudo id -u)" -ne 0 ]; then echo "This script must be ran as a non-root user with sudo privileges." ; exit 1 ; fi
}

gitmakeinstall() {
	[ ! -d "$repodir" ] && mkdir -p "$HOME/.local/src"
	progname="$(basename "$1" .git)"
	dir="$repodir/$progname"
	dialog --title "Package Installation" --infobox "Installing \`$progname\` ($n of $total) via \`git\` and \`make\`. $(basename "$1") $2" 5 70
	git clone --depth 1 "$1" "$dir" >/dev/null 2>&1 || { cd "$dir" || return ; git pull --force origin master;}
	cd "$dir" || exit
	make >/dev/null 2>&1
	sudo make install >/dev/null 2>&1
	cd /tmp || return
}

pipinstall() {
	dialog --title "Package Installation" --infobox "Installing the Python package \`$1\` ($n of $total). $1 $2" 5 70
	if ! type pip >/dev/null 2>&1; then
		if [ "$distro" = "macOS" ]; then
			sudo easy_install pip >/dev/null 2>&1 || error "Failed to install pip."
		else
			installpkg python-pip
		fi
	fi
	yes | pip install "$1"
}

aurinstall() {
	dialog --title "Package Installation" --infobox "Installing \`$1\` ($n of $total) from the AUR. $1 $2" 5 70
	echo "$aurinstalled" | grep "^$1$" >/dev/null 2>&1 && return
	$aurhelper -S --noconfirm "$1" >/dev/null 2>&1
}

aurmanualinstall() { # Installs $1 manually if not installed. Used only for AUR helper here.
	[ -f "/usr/bin/$1" ] || (
	dialog --infobox "Installing \"$1\", an AUR helper..." 4 50
	cd /tmp || exit
	rm -rf /tmp/"$1"*
	curl -sO https://aur.archlinux.org/cgit/aur.git/snapshot/"$1".tar.gz &&
	tar -xvf "$1".tar.gz >/dev/null 2>&1 &&
	cd "$1" &&
	makepkg --noconfirm -si >/dev/null 2>&1
	cd /tmp || return)
}

bootstrapbrew() {
	#TODO: Make this completely hands free
	/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install.sh)"
}

maininstall() { # Installs all needed programs from main repo.
	dialog --title "Package Installation" --infobox "Installing \`$1\` ($n of $total). $1 $2" 5 70
	installpkg "$1"
}

brewcaskinstall() {
	dialog --title "Package Installation" --infobox "Installing \`$1\` ($n of $total). $1 $2" 5 70
	 brew cask install "$1" >/dev/null 2>&1
}

brewtap() {
	dialog --title "Package Installation" --infobox "Tapping brew repo \`$1\` ($n of $total). $1 $2" 5 70
	brew tap "$1" >/dev/null 2>&1
}

macappinstall() {
	dialog --title "Package Installation" --infobox "Installing \`$1\` ($n of $total). $1 $2" 5 70
	mas install "$1" >/dev/null 2>&1
}

installationloop() {
	([ -f "$progsfile" ] && cp "$progsfile" /tmp/progs.csv) || curl -Ls "$progsfile" | sed '/^#/d' | eval grep "$grepseq" > /tmp/progs.csv
	total=$(wc -l < /tmp/progs.csv)
	aurinstalled=$(pacman -Qqm)
	while IFS=, read -r tag program comment; do
		n=$((n+1))
		echo "$comment" | grep "^\".*\"$" >/dev/null 2>&1 && comment="$(echo "$comment" | sed "s/\(^\"\|\"$\)//g")"
		case "$tag" in
			"AUR") aurinstall "$program" "$comment" ;;
			"git") gitmakeinstall "$program" "$comment" ;;
			"pip") pipinstall "$program" "$comment" ;;
			"cask") brewcaskinstall "$program" "$comment" ;; # Brew cask for macOS binary tools
			"tap") brewtap "$program" "$comment" ;; # Brew tap for extra tools
			"mas") macappinstall "$program" "$comment" ;; # macOS Apple Store programs
			#"ias") iosappinstall "$program" "$comment" ;; # iOS Apple Store programs
			#"deb") maininstall "$program" "$comment" ;; # Debian specific packages (for names that aren't consistant across platforms)
			#"brew") maininstall "$program" "$comment" ;; # Brew (macOS) specific packages
			#"iOS") maininstall "$program" "$comment" ;; # Cydia (iOS) specific packages
			#"Apkg") maininstall "$program" "$comment" ;; # pkg for Apple (macOS/iOS/tvOS) specific packages
			#"OBSD") maininstall "$program" "$comment" ;; # OpenBSD specific packages
			#"pacman") maininstall "$program" "$comment" ;; # Arch specific packages
			*) maininstall "$program" "$comment" ;; # For the rest of the names that are shared across platforms
		esac
	done < /tmp/progs.csv ;
}


finalize() {
	dialog --title "All done!" --msgbox "Congrats! Provided there were no hidden errors, the script completed successfully and all the programs should be installed." 12 80
}

### THE ACTUAL SCRIPT ###
# function main() { for anyone looking for that :P

### This is how everything happens in an intuitive format and order.

# Give warning if user already exists.
usercheck || error "User exited."

[ "$distro" = macOS ] && { \
	if ! type brew >/dev/null 2>&1; then
		bootstrapbrew || error "Failed to install brew."
	fi
}

# Install dialog.
installpkg dialog || error "Are you sure you're running this with the correct privileges and have an internet connection?"

# Welcome user.
welcomemsg || error "User exited."

# System specific prereqs
[ "$distro" = macOS ] && { \
	if ! type mas >/dev/null 2>&1; then
		dialog --title "Package Installation" --infobox "Installing \`mas\` for installing other software required for the installation of other programs." 5 75
		installpkg mas || error "Failed to install mas."
		while true; do
			mas account && break
			dialog --colors --title "Sign In to the App Store" --yes-label "Try it now!" --no-label "Let's do this later." --yesno "You don't seem to be logged into the macOS App Store.\\n\\nPlease sign in and try again when you are properly authenticated with the macOS App Store." 8 70 || exit 1
		done
	fi
}

[ "$distro" != "macOS" ] && { \
	dialog --title "Package Installation" --infobox "Installing \`curl\` and \`git\` for installing other software required for the installation of other programs." 5 65
	installpkg curl
	installpkg git
}

[ "$distro" = arch ] && { \
	dialog --title "Package Installation" --infobox "Installing \`basedevel\` and \`yay\` for installing other software required for the installation of other programs." 5 70
	installpkg base-devel
	aurmanualinstall $aurhelper || error "Failed to install AUR helper."
}

# The actual install.
# Loop over all our tools and install them
installationloop

# Last message! Install complete!
finalize
clear
