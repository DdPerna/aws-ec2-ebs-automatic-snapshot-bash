#!/bin/bash
export PATH=$PATH:/usr/local/bin/:/usr/bin

# Safety feature: exit script if error is returned, or if variables not set.
# Exit if a pipeline results in an error.
set -ue
set -o pipefail

## Automatic EBS Volume Snapshot Creation & Clean-Up Script
#
# Written by Casey Labs Inc. (https://www.caseylabs.com)
#
# Customized by David Diperna
#
# Script Github repo: https://github.com/DdPerna/aws-ec2-ebs-automatic-snapshot-bash
#
# Additonal credits: Log function by Alan Franzoni; Pre-req check by Colin Johnson
#
# PURPOSE: This Bash script can be used to take automatic snapshots of your Linux EC2 volumes. Script process:
# - Gather a list of all volume IDs attached to an instance with the tag Backup with a value of yes
# - Take a snapshot of each volume  
# - The script will then delete all snapshots taken by this script that are older than 27 days
#
# DISCLAIMER: This script deletes snapshots (though only the ones that it creates).
# Make sure that you understand how the script works. No responsibility accepted in event of accidental data loss.
#


## Variable Declartions ##

# set region
region=us-east-1

# create list of all ec2 instances with Backup tag with value yes
instance_list=$(aws ec2 describe-instances --region $region --output=text --filters "Name=tag:Backup,Values=yes" --query 'Reservations[].Instances[].InstanceId[]')

# Set Logging Options
logfile="/var/log/ebs-snapshot.log"
logfile_max_lines="5000"

# How many days do you wish to retain backups for? Default: 7 days
retention_days="27"
retention_date_in_seconds=$(date +%s --date "$retention_days days ago")

# Create a list of the volumes that are attached to instances with the Backup tag
# The list is used in the cleanup_snapshots function
for instance_id in $instance_list; do

                # Get volume ids attached to instance and increment to list
                volume_list+=" "$(aws ec2 describe-instances --region $region --output=text --instance-ids $instance_id --query 'Reservations[].Instances[].BlockDeviceMappings[].Ebs[].VolumeId[]')

done


## Function Declarations ##

# Function: Setup logfile and redirect stdout/stderr.
log_setup() {
    # Check if logfile exists and is writable.
    ( [ -e "$logfile" ] || touch "$logfile" ) && [ ! -w "$logfile" ] && echo "ERROR: Cannot write to $logfile. Check permissions or sudo access." && exit 1

    tmplog=$(tail -n $logfile_max_lines $logfile 2>/dev/null) && echo "${tmplog}" > $logfile
    exec > >(tee -a $logfile)
    exec 2>&1
}

# Function: Log an event.
log() {
    echo "[$(date +"%Y-%m-%d"+"%T")]: $*"
}

# Function: Confirm that the AWS CLI and related tools are installed.
prerequisite_check() {
        for prerequisite in aws wget; do
                hash $prerequisite &> /dev/null
                if [[ $? == 1 ]]; then
                        echo "In order to use this script, the executable \"$prerequisite\" must be installed." 1>&2; exit 70
                fi
        done
}

snapshot_volumes() {

        for instance_id in $instance_list; do

                # Get the instance's tag name
                instance_name=$(aws ec2 describe-instances --region $region --output=text --instance-ids $instance_id  --query 'Reservations[].Instances[].Tags[?Key==`Name`].Value[]')

                log "creating new snapshot of volumes attached to instance $instance_name"

                # Create a list of volumes attached to this instance
                volumes=$(aws ec2 describe-instances --region $region --output=text --instance-ids $instance_id --query 'Reservations[].Instances[].BlockDeviceMappings[].Ebs[].VolumeId[]')

                # loop through the instance's volume list and create a snapshot of each
                for volume_id in $volumes; do

                        # Create a description for the snapshot
                        snapshot_description="$instance_name-$volume_id-backup-$(date +%Y-%m-%d)"

                        # Take snapshots of the volumes, and capture the resulting snapshot ID
                        snapshot_id=$(aws ec2 create-snapshot --region $region --output=text --description $snapshot_description --volume-id $volume_id --query SnapshotId)

                        # Add a "CreatedBy:AutomatedBackup" tag to the resulting snapshot.
                        # Why? Because we only want to purge snapshots taken by the script later, and not delete snapshots manually taken.
                        aws ec2 create-tags --region $region --resource $snapshot_id --tags Key=CreatedBy,Value=AutomatedBackup

                        log "New snapshot is $snapshot_id"
                done
        done
}


# Function: Cleanup all snapshots created by this script that are older than $retention_days
cleanup_snapshots() {
        for volume_id in $volume_list; do
                snapshot_list=$(aws ec2 describe-snapshots --region $region --output=text --filters "Name=volume-id,Values=$volume_id" "Name=tag:CreatedBy,Values=AutomatedBackup" --query Snapshots[].SnapshotId)
                for snapshot in $snapshot_list; do
                        log "Checking $snapshot..."
                        # Check age of snapshot
                        snapshot_date=$(aws ec2 describe-snapshots --region $region --output=text --snapshot-ids $snapshot --query Snapshots[].StartTime | awk -F "T" '{printf "%s\n", $1}')
                        snapshot_date_in_seconds=$(date "--date=$snapshot_date" +%s)
                        snapshot_description=$(aws ec2 describe-snapshots --snapshot-id $snapshot --region $region --query Snapshots[].Description)

                        if (( $snapshot_date_in_seconds <= $retention_date_in_seconds )); then
                                log "DELETING snapshot $snapshot. Description: $snapshot_description ..."
                                aws ec2 delete-snapshot --region $region --snapshot-id $snapshot
                        else
                                log "Not deleting snapshot $snapshot. Description: $snapshot_description ..."
                        fi
                done
        done
}


## SCRIPT COMMANDS ##

log_setup
prerequisite_check

snapshot_volumes
cleanup_snapshots
