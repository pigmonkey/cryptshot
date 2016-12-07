#!/bin/bash
#
# Open and mount a LUKS volume before performing a backup with rsnapshot.
#
# This script first checks to see if a volume with the given UUID exists.
# If the volume is found, it is treated as a LUKS volume and decrypted with
# the given key file, after which it is mounted. The script then runs
# rsnapshot. After the backup is complete, the volume is unmounted and the
# LUKS mapping is removed. Optionally, the mount point can be deleted to
# complete the clean-up.
#
# This provides for a way to achieve encrypted backups to an external drive
# with a backup tool that does not inherently provide encryption. It can
# easily be modified to execute a backup program other than rsnapshot. Since
# the first step taken is to check if the given volume exists, it is
# appropriate for situations where the external backup volume is not always
# available to the machine (such as a USB backup drive and a laptop).
#
# The rsnapshot interval should be passed with the -i argument.
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

# Define the location of rsnapshot.
RSNAPSHOT="/usr/bin/rsnapshot"

# End configuration here.
###############################################################################
# define exit codes (from /usr/include/sysexits.h) for code legibility
# see also: http://tldp.org/LDP/abs/html/exitcodes.html
EX_OK=0
EX_USAGE=64
EX_NOINPUT=66
EX_CANTCREAT=73
EX_NOPERM=77
EX_CONFIG=78

# Exit if not root
if [ x"`whoami`" != x"root" ]; then
    echo 'Not super-user.'
    exit $EX_NOPERM
fi

# Get any arguments.
while getopts "c:i:" opt; do
    case $opt in
        c)
            source "$OPTARG"
            ;;
        i)
            INTERVAL=$OPTARG
            ;;
    esac
done

# Exit if no volume is specified.
if [ "$UUID" = "" ]; then
    echo 'No volume specified.'
    exit $EX_CONFIG
fi

# Exit if no key file is specified.
if [ "$KEYFILE" = "" ]; then
    echo 'No key file specified.'
    exit $EX_CONFIG
fi

# Exit if no mount root is specified.
if [ "$MOUNTROOT" = "" ]; then
    echo 'No mount root specified.'
    exit $EX_CONFIG
fi

# Exit if no interval was specified.
if [ -z "$INTERVAL" ]; then
    echo "No interval specified."
    exit $EX_USAGE
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
    # Attempt to open the LUKS volume.
    cryptsetup luksOpen --key-file $KEYFILE $volume $name
    # If the volume was decrypted, mount it. 
    if [ $? -eq 0 ];
    then
        mount /dev/mapper/$name $MOUNTPOINT
        # If the volume was mounted, run the backup.
        if [ $? -eq 0 ];
        then
            $RSNAPSHOT "$INTERVAL"
            # Unmount the volume
            umount $MOUNTPOINT
            # If the volume was unmounted and the user has requested that the
            # mount point be removed, remove it.
            if [ $? -eq 0 -a $REMOVEMOUNT -ne 0 ]; then
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
