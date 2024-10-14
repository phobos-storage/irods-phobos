#!/bin/bash

# All rights reserved (c) 2014-2024 CEA/DAM.
#
# This file is part of Phobos.
#
# Phobos is free software: you can redistribute it and/or modify it under
# the terms of the GNU Lesser General Public License as published by
# the Free Software Foundation, either version 2.1 of the License, or
# (at your option) any later version.

# Phobos is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Lesser General Public License for more details.
#
# You should have received a copy of the GNU Lesser General Public License
# along with Phobos. If not, see <http://www.gnu.org/licenses/>.
#
# \brief  Phobos UMSS script for iRODS


# This script is the Phobos implementation of an iRODS Universal Mass Storage
# System plugin (UMSS), enabling the use of Phobos as a storage tier by iRODS.
#
# In order to be detected by iRODS, the present file is to be placed in
# /var/lib/irods/msiExecCmd_bin/

VERSION=v1.0
ID=$RANDOM
STATUS="FINE"
LEVEL=1
DEBUG=1
DISPLAY=0
DISPLAY_COLOUR=1
DISPLAY_BLACK=0

LOGFILE=/var/lib/irods/$VERSION.log
sudo touch $LOGFILE
sudo chown "$(whoami)":"$(whoami)" $LOGFILE

# FANCY COLORS
Color_Off=$(tput sgr0)
# Regular Colors
Black=$(tput setaf 0)
Red=$(tput setaf 1)
Green=$(tput setaf 2)
#Yellow=$(tput setaf 3)
Blue=$(tput setaf 4)
Purple=$(tput setaf 5)
#Cyan=$(tput setaf 6)
#White=$(tput setaf 7)

# function for the synchronization of file $1 on local disk resource
# (i.e. the cache child of the Compound Resource) to file $2 in Phobos
syncToArch () {
    local rc
    local md_script
    local md
    local phobos
    local put_script
    local put
    save_log syncToArch "BEGIN syncToArch($*)"
    rc=0
    if [ -z "$1" ]; then
        save_log syncToArch "No object given to put"
        rc=1
    fi
    if [ -z "$2" ]; then
        save_log syncToArch "No OID given to put object \"$1\" to"
        rc=2
    fi

    # Get metadata from source.
    if [ $rc == 0 ]; then
        md_script="get_metadata ${1}"
        md=$($md_script)
        rc=$?
        save_log syncToArch "$md_script return integer ${rc} and value \n${md}"
    fi

    # Put the file and its metadata into Phobos.
    if [ $rc == 0 ]; then
        phobos=$(type -P phobos)
        echo "UNIVMSS $phobos \"$1\" \"$2\""
        put_script="sudo $phobos put --overwrite --metadata ${md} ${1} ${2}"
        put=$($put_script >> $LOGFILE 2>&1)
        rc=$?
        save_log syncToArch "$put_script return with status=$put($rc)"
    fi

    if [ "$rc" != 0 ]; then
        record_failure syncToArch "$rc"
    fi
    save_log syncToArch "END syncToArch($*)"
    return $rc
}

# function for staging a file $1 from Phobos to file $2 on disk
# (i.e. on the cache child of the Compound Resource).
stageToCache () {
    local rc
    local phobos
    local get_script
    local get
    save_log stageToCache "BEGIN stageToCache($*)"
    rc=0
    if [ -z "$1" ]; then
        save_log stageToCache "No object to get"
        rc=1
    fi
    if [ -z "$2" ]; then
        save_log stageToCache "No destination file to write object \"$1\" into"
        rc=2
    fi
    if [ -f "$2" ]; then
    # iRODS creates the destination cache file in advance for Phobos.
    # This is a kind attention, but we have to remove it.
        save_log stageToCache "\"$2\" already exists. Removing it"
        rm "$2"
        rc=$?
    fi

    # Get the object.
    if [ "$rc" == 0 ]; then
        phobos=$(type -P phobos)
        echo "UNIVMSS $phobos \"$1\" \"$2\""
        get_script="sudo $phobos get ${1} ${2}"
        get=$($get_script >> $LOGFILE 2>&1)
        rc=$?
        save_log stageToCache "$get_script return with status=$get($rc)"
    fi

    if [ "$rc" != 0 ]; then
        record_failure stageToCache "$rc"
    fi
    save_log stageToCache "END stageToCache($*)"
    return $rc
}

# function to create a new directory $1 in the MSS logical name space.
#
# Phobos does not encompass the notion of directories or iRODS-collections.
# And Phobos media/devices/dirs management is not to be done using iRODS.
# So this function does nothing.
_mkdir () {
    local rc
    save_log mkdir "BEGIN mkdir($*)"
    rc=0
    if [ "$rc" != 0 ]; then
        record_failure mkdir "$rc"
    fi
    save_log mkdir "END mkdir($*)"
    return $rc
}

# function to modify ACLs $2 (octal) in the
# MSS logical name space for a given directory $1.
#
# Phobos authorisations have nothing to do with iRODS/POSIX authorisations,
# as this function is used to manage. For further explanations, cf.
# `phobos-storage/phobos/doc/design/admin_resource_operation_control.md`.
# Considering Phobos cannot manage subdirectories, it is also unsafe to call
# for POSIX chmod.
# So this function does nothing.
_chmod () {
    local rc
    save_log chmod "BEGIN chmod($*)"
    rc=0
    if [ "$rc" != 0 ]; then
        record_failure chmod "$rc"
    fi
    save_log chmod "END chmod($*)"
    return $rc
}

# function to remove object $1 from Phobos.
# There is no way to remove a directory in a UMSS.
#
# This function is a hard remove, like the POSIX one.
# But Phobos only implements a soft delete, that moves objects out of
# its ``object`` DB table to its ``deprecated_object`` DB table.
_rm () {
    local rc
    local phobos
    local ph_del_script
    local ph_del
    save_log rm "BEGIN rm($*)"
    rc=0
    if [ -z "$1" ]; then
        save_log rm "No object given to remove"
        rc=1
    fi
    if [ $rc == 0 ]; then
        phobos=$(type -P phobos)
        ph_del_script="sudo $phobos del ${1}"
        ph_del=$($ph_del_script >> $LOGFILE 2>&1)
        rc=$?
        save_log rm "$ph_del_script return with status=$ph_del($rc)"
    fi
    if [ "$rc" != 0 ]; then
        record_failure rm "$rc"
    fi
    save_log rm "END rm($*)"
    return $rc
}

# function to move and rename a file $1 into $2 in Phobos.
#
# Considering Phobos does not implement directories,
# this function is only for renaming purposes.
_mv () {
    local rc
    local phobos
    local ph_rename_script
    local ph_rename
    save_log mv "BEGIN mv($*)"
    rc=0
    if [ -z "$1" ]; then
        save_log mv "No object given to rename"
        rc=1
    fi
    if [ -z "$2" ]; then
        save_log mv "No new name given to rename object \"$1\""
        rc=2
    fi
    if [ $rc != 0 ]; then
        record_failure mv "$rc"
        save_log mv "END mv($*)"
        return $rc
    fi

    phobos=$(type -P phobos)
    ph_rename_script="sudo $phobos rename ${1} ${2}"
    ph_rename=$($ph_rename_script >> $LOGFILE 2>&1)
    rc=$?
    save_log mv "$ph_rename_script return with status=$ph_rename($rc)"

    if [ $rc != 0 ]; then
        record_failure mv"$rc"
    fi

    save_log mv "END mv($*)"
    return $rc
}

# function to do a stat on a file $1 stored in Phobos.
#
# This function returns the required formated string that was recorded into
# the object's user_metadata field during syncToArch.
_stat () {
    # <your command to retrieve stats on the file> $1
    # e.g: output=$(/usr/local/bin/rfstat rfioServerFoo:$1)
    local rc
    local phbs
    local json_outpt_script
    local json_outpt
    local keys_order
    local irods_output
    save_log stat "BEGIN stat($*)"
    rc=0
    if [ -z "$1" ]; then
        save_log stat "No object given to return status from"
        rc=1
    fi
    if [ $rc != 0 ]; then
        record_failure stat "$rc"
        save_log stat "END stat($*)"
        return $rc
    fi
    phbs=$(type -P phobos)
    json_outpt_script="sudo $phbs object list $1 -t -o user_md -f human"
    json_outpt=$($json_outpt_script)
    rc=$?
    save_log stat "$json_outpt_script return with status=$json_outpt($rc)"
    if [ $rc != 0 ]; then
        record_failure stat "$rc"
        save_log stat "END stat($*)"
        return $rc
    fi
    if [ -z "$json_outpt" ]; then
        save_log stat "Object $1 not found. return with status=$json_outpt(1)"
        save_log stat "END stat($*)"
        return 1
    fi
    keys_order=("device" "inode" "mode" "nlink" "uid" "gid" "devid" "size"\
       "blksize" "blkcnt" "atime" "mtime" "ctime")
    irods_output=$(echo "$json_outpt" | jq -r --argjson keys "$(printf \
                   '%s\n' "${keys_order[@]}" | jq -R . | jq -s .)" \
                   '[ . as $in | $keys[] | $in[.] ] | join(":")')
    rc=$?
    save_log stat "function ends with status=($rc), \
                   exporting string:\n${irods_output}"
    if [ $rc == 0 ]; then
        echo "${irods_output}"
    else
        record_failure stat "$rc"
    fi
    save_log stat "END stat($*)"
    return $rc
}

#######################
# Secondary functions #
#######################

# Outputs a log line in $LOGFILE, if any.
save_log() {
    if [ $LEVEL -ne $DEBUG ]; then
        return 0
    fi
    local timestamp
    local message_colour
    local message_black

    timestamp=$(date +"%Y:%m:%d-%T.%N")
    # Messages building
    if [ "$2" ]; then
        message_colour="${Black}${ID} ${Green}[${timestamp}]\t"
        message_colour+="${Red}${1}(${Blue}${2}${Red})${Color_Off}"
        message_black="${ID} [${timestamp}] ${1}(${2})"
    else
        message_colour="${Black}${ID} ${Red}${1}${Color_Off}"
        message_black="${ID} ${1}"
    fi

    # Message(s) writing on file(s)
    if [ -n "${LOGFILE+x}" ]; then
        if [ "$LOGFILE" != "" ]; then
            echo -e "$message_colour" >> "$LOGFILE"
        fi
    fi

    # Message(s) displaying on screen
    if [ $DISPLAY == 1 ]; then
        if [ $DISPLAY_COLOUR == 1 ]; then
            echo -e "$message_colour"
        fi
        if [ $DISPLAY_BLACK == 1 ]; then
            echo -e "$message_black"
        fi
    fi
    return 0
}

record_failure() {
    STATUS="FAILURE"
    save_log "${1}" "STATUS=${STATUS}(${2})"
}

# Get metadata stores in user_md, parse it according to univMSS template,
# and return the output as a hash table.
get_metadata() {
    local rc
    local stat
    local output_script
    local output
    local md_str
    save_log get_metadata "BEGIN get_metadata($*)"
    rc=0
    if [ -z "$1" ]; then
        save_log get_metadata "No file given to get metadata from"
        rc=1
    fi
    stat=$(type -P stat)
    output_script="sudo $stat ${1}"
    output=$($output_script)
    rc=$?
    save_log get_metadata "$output_script return with status=${rc}(\n${output})"
    if [ $rc != 0 ]; then
        save_log get_metadata "END get_metadata($*)"
        return $rc
    fi
    # parse the output.
    # Parameters to retrieve:
    #     "device"  - device ID of device containing file
    #     "inode"   - file serial number
    #     "mode"    - ACL mode in octal
    #     "nlink"   - number of hard links to the file
    #     "uid"     - user id of file
    #     "gid"     - group id of file
    #     "devid"   - device id
    #     "size"    - file size
    #     "blksize" - block size in bytes
    #     "blkcnt"  - number of blocks
    #     "atime"   - last access time
    #     "mtime"   - last modification time
    #     "ctime"   - last change time
    #
    # e.g: device=$(echo $output | awk '{print $3}')
    # Note 1: if some of these parameters are not relevant, set them to 0.
    # Note 2: the time should have this format:
    #         YYYY-MM-dd-hh.mm.ss with:
    #         YYYY = 1900 to 2xxxx, MM = 1 to 12, dd = 1 to 31,
    #         hh = 0 to 24, mm = 0 to 59, ss = 0 to 59
    md_str=""
    md_str+="device=$( echo "$output" | sed -nr \
        's/.*\<Device: *(\S*)\>.*/\1/p'),"
    md_str+="inode=$(  echo "$output" | sed -nr \
        's/.*\<Inode: *(\S*)\>.*/\1/p'),"
    md_str+="mode=$(   echo "$output" | sed -nr \
        's/.*\<Access: *\(([0-9]*)\/.*/\1/p'),"
    md_str+="nlink=$(  echo "$output" | sed -nr \
        's/.*\<Links: *([0-9]*)\>.*/\1/p'),"
    md_str+="uid=$(    echo "$output" | sed -nr \
        's/.*\<Uid: *\( *([0-9]*)\/.*/\1/p'),"
    md_str+="gid=$(    echo "$output" | sed -nr \
        's/.*\<Gid: *\( *([0-9]*)\/.*/\1/p'),"
    md_str+="devid=0,"
    md_str+="size=$(   echo "$output" | sed -nr \
        's/.*\<Size: *([0-9]*)\>.*/\1/p'),"
    md_str+="blksize=$(echo "$output" | sed -nr \
        's/.*\<IO Block: *([0-9]*)\>.*/\1/p'),"
    md_str+="blkcnt=$( echo "$output" | sed -nr \
        's/.*\<Blocks: *([0-9]*)\>.*/\1/p'),"
    md_str+="atime=$(  echo "$output" | sed -nr \
        's/.*\<Access: *([0-9]{4,}-[01][0-9]-[0-3][0-9]) *([0-2][0-9]):([0-5][0-9]):([0-6][0-9])\..*/\1-\2.\3.\4/p'),"
    md_str+="mtime=$(  echo "$output" | sed -nr \
        's/.*\<Modify: *([0-9]{4,}-[01][0-9]-[0-3][0-9]) *([0-2][0-9]):([0-5][0-9]):([0-6][0-9])\..*/\1-\2.\3.\4/p'),"
    md_str+="ctime=$(  echo "$output" | sed -nr \
        's/.*\<Change: *([0-9]{4,}-[01][0-9]-[0-3][0-9]) *([0-2][0-9]):([0-5][0-9]):([0-6][0-9])\..*/\1-\2.\3.\4/p')"
    echo "${md_str}"

    save_log get_metadata "END get_metadata($*)"
    return $rc
}

# Saving first logs to identify the session
save_log ""
save_log "##########################"
save_log "# BEGIN EXPERIMENT $ID #"
save_log "##########################"
if [ $DISPLAY_COLOUR == 1 ]; then save_log "$Blue$0_$Purple$VERSION"; fi
if [ $DISPLAY_BLACK == 1 ]; then save_log "$0_$VERSION"; fi



case "$1" in
    syncToArch ) "syncToArch" "$2" "$3" ;;
    stageToCache ) "stageToCache" "$2" "$3" ;;
    mkdir ) "_mkdir" "$2" ;;
    chmod ) "_chmod" "$2" "$3" ;;
    rm ) "_rm" "$2" ;;
    mv ) "_mv" "$2" "$3" ;;
    stat ) "_stat" "$2" ;;
esac

exit $?
