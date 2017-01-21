#!/bin/bash
#
# Open and mount a LUKS volume before performing a backup.
#
# This script first checks to see if a volume with the given UUID exists.  If
# the volume is found, it is treated as a LUKS volume and decrypted with the
# given key file, after which it is mounted. The script then runs the specified
# backup program. After the backup is complete, the volume is unmounted and the
# LUKS mapping is removed. Optionally, the mount point can be deleted to
# complete the clean-up.
#
# Since the first step taken is to check if the given volume exists, it is
# appropriate for situations where the external backup volume is not always
# available to the machine (such as a USB backup drive and a laptop).
#
# If using rsnapshot, the interval should be passed with the -i argument.
#
# Author:   Pig Monkey (pm@pig-monkey.com)
# Website:  https://github.com/pigmonkey/backups
#
###############################################################################

# Define the UUID of the backup volume.
UUID=""

# Define the location of the LUKS key file.
KEYFILE=""

# Define the root of the mount point for the backup volume.
# This will be created if it does not already exist.
MOUNTROOT="/mnt/"

# Any non-zero value here will caused the mount point to be deleted after the
# volume is unmounted.
REMOVEMOUNT=1

# Define the location of the backup program.
BACKUP="/usr/bin/rsnapshot"

# End configuration here.
###############################################################################
# define exit codes (from /usr/include/sysexits.h) for code legibility
# see also: http://tldp.org/LDP/abs/html/exitcodes.html
EX_OK=0
EX_NOINPUT=66
EX_CANTCREAT=73
EX_NOPERM=77
EX_CONFIG=78

# Check for config file at standard locations (XDG first)
config=""
if [ "$XDG_CONFIG_HOME" != "" ] && [ -f "$XDG_CONFIG_HOME/cryptshot.conf" ]; then
    config="$XDG_CONFIG_HOME/cryptshot.conf"
elif [ -f "$HOME/.cryptshot.conf" ]; then
    config="$HOME/.cryptshot.conf"
fi

# Get any arguments.
while getopts "c:i:h" opt; do
    case $opt in
        c)
            config="$OPTARG"
            ;;
        i)
            BACKUP_ARGS=$OPTARG
            ;;
        h)
            echo "Usage: $0 [ -i BACKUP_ARGS ] [ -c CONFIG ]"
            exit $EX_OK
            ;;
    esac
done

# Exit if not root
if [ x"$(whoami)" != x"root" ]; then
    echo 'Not super-user.'
    exit $EX_NOPERM
fi

# If a config file is given, use that file
if [ "$config" != "" ]; then
    source "$config"
    exitcode=$?
    if [ $exitcode -ne 0 ]; then
        echo 'Failed to source configuration file.'
        exit $exitcode
    fi
fi

# Exit if no volume is specified.
if [ "$UUID" = "" ]; then
    echo 'No volume specified.'
    exit $EX_CONFIG
fi

# Exit if no key file is specified.
FD_STDIN=1
if [ "$KEYFILE" = "" ] && [ ! -t $FD_STDIN ]; then
    echo 'No key file specified and not on terminal for password input.'
    exit $EX_CONFIG
fi

# Exit if no mount root is specified.
if [ "$MOUNTROOT" = "" ]; then
    echo 'No mount root specified.'
    exit $EX_CONFIG
fi

# Create the mount point from the mount root and UUID.
MOUNTPOINT="$MOUNTROOT$UUID"

# If the mount point does not exist, create it.
if [ ! -d "$MOUNTPOINT" ]; then
    mkdir $MOUNTPOINT
    # Exit if the mount point was not created.
    if [ $? -ne 0 ]; then
        echo "Failed to create mount point."
        exit $EX_CANTCREAT
    fi
fi

# Build the reference to the volume.
volume="/dev/disk/by-uuid/$UUID"

# Create a unique name for the LUKS mapping.
name="crypt-$UUID"

# Set the default exit code.
exitcode=$EX_OK

# Continue if the volume exists.
if [ -e $volume ];
then
    # Attempt to open the LUKS volume, using keyfile if given.
    if [ "$KEYFILE" = "" ]; then
        cryptsetup luksOpen $volume $name
    else
        cryptsetup luksOpen --key-file $KEYFILE $volume $name
    fi
    # If the volume was decrypted, mount it. 
    if [ $? -eq 0 ];
    then
        mount /dev/mapper/$name $MOUNTPOINT
        # If the volume was mounted, run the backup.
        if [ $? -eq 0 ];
        then
            $BACKUP $BACKUP_ARGS
            # Unmount the volume
            umount $MOUNTPOINT
            # If the volume was unmounted and the user has requested that the
            # mount point be removed, remove it.
            if [ $? -eq 0 ] && [ $REMOVEMOUNT -ne 0 ]; then
                rmdir $MOUNTPOINT
            fi
        else
            exitcode=$?
            echo "Failed to mount $volume at $MOUNTPOINT."
        fi
        # Close the LUKS volume.
        cryptsetup luksClose $name
    else
        exitcode=$?
        echo "Failed to open $volume with key $KEYFILE."
    fi
else
    exitcode=$EX_NOINPUT
    echo "Volume $UUID not found."
fi

exit $exitcode
