# Cryptshot

Open and mount a LUKS volume before performing a backup with
[rsnapshot](http://rsnapshot.org/).

This script first checks to see if a volume with the given UUID exists.
If the volume is found, it is treated as a LUKS volume and decrypted with
the given key file, after which it is mounted. The script then runs
rsnapshot. After the backup is complete, the volume is unmounted and the
LUKS mapping is removed. Optionally, the mount point can be deleted to
complete the clean-up.

This provides for a way to achieve encrypted backups to an external drive
with a backup tool that does not inherently provide encryption. It can
easily be modified to execute a backup program other than rsnapshot. Since
the first step taken is to check if the given volume exists, it is
appropriate for situations where the external backup volume is not always
available to the machine (such as a USB backup drive and a laptop).

The rsnapshot interval should be passed with the -i argument. Cryptshot can
then replace rsnapshot in your crontab.

    # rsnapshot daily
    cryptshot.sh -i daily

See source for configuration.
