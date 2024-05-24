#!/bin/bash

## Copyright (c) 2009 Data Intensive Cyberinfrastructure Foundation. All rights reserved.
## For full copyright notice please refer to files in the COPYRIGHT directory
## Written by Jean-Yves Nief of CCIN2P3 and copyright assigned to Data Intensive Cyberinfrastructure Foundation

# This script is an implementation of an iRODS-phobos connector via a Universal Mass Storage Service plugin.
# To be placed in /var/lib/irods/msiExecCmd_bin

VERSION=v1.0
ID=$RANDOM
STATUS="FINE"
LEVEL=1
DEBUG=1
DISPLAY=0
DISPLAY_COLOUR=1
DISPLAY_BLACK=0

LOGFILE_FANCY=/var/lib/irods/$VERSION.log
#LOGFILE_SOBRE=/var/lib/irods/$VERSION.txt
sudo touch $LOGFILE_FANCY
#sudo touch $LOGFILE_SOBRE
sudo chown "$(whoami)":"$(whoami)" $LOGFILE_FANCY
#sudo chown "$(whoami)":"$(whoami)" $LOGFILE_SOBRE

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

# function for the synchronization of file $1 on local disk resource to file $2 in phobos
syncToArch () {
    # <your command or script to copy from cache to phobos> $1 $2
    # e.g: /usr/local/bin/rfcp $1 rfioServerFoo:$2
    # Syntax remainder : phobos put </path/to/local/file> <object_id>
    
    save_log syncToArch "BEGIN syncToArch($*)"
    rc=0
    if [ "$1" ]; then
        if [ "$2" ]; then
            phobos=$(type -P phobos)
            md_script="get_metadata ${1}"
            md=$($md_script)
            rc=$?
            save_log syncToArch "$md_script return with integer ${rc} and value \n${md}"
            if [ $rc == 0 ]; then
                echo "UNIVMSS $phobos \"$1\" \"$2\""
                put_script="sudo $phobos put --metadata ${md} -f dir ${1} ${2}"
                put=$($put_script >> $LOGFILE_FANCY 2>&1)
                rc=$?
                save_log syncToArch "$put_script return with status=$put($rc)"
	        fi
        else
            save_log syncToArch "No OID given to put data \"$1\" to"
            rc=1
        fi
    else
        save_log syncToArch "No object given to put"
        rc=2
    fi

    if [ "$rc" != 0 ]; then
        STATUS="FAILURE"
        save_log syncToArch "STATUS=$STATUS($rc)"
    fi
    save_log syncToArch "END syncToArch($*)"
    return $rc
}

# function for staging a file $1 from phobos to file $2 on disk
stageToCache () {
    # <your command to stage from phobos to cache> $1 $2
    # Syntax Remainder : $ phobos get <object_id> </path/to/local/output/file>
    # e.g: /usr/local/bin/rfcp rfioServerFoo:$1 $2
    
    save_log stageToCache "BEGIN stageToCache($*)"
    rc=0
    if [ "$1" ]; then
        if [ "$2" ]; then
            phobos=$(type -P phobos)
            echo "UNIVMSS $phobos \"$1\" \"$2\""
            if [ -f $2 ]; then
                sudo /bin/rm $2
            fi
            get_script="sudo $phobos get ${1} ${2}"
            get=$($get_script >> $LOGFILE_FANCY 2>&1)
            rc=$?
            save_log stageToCache "$get_script return with status=$get($rc)"
        else
            save_log stageToCache "No destination file to get object \"$1\" to"
            rc=11
        fi
    else
        save_log stageToCache "No object to get"
        rc=12
    fi

    if [ "$rc" != 0 ]; then
        STATUS="FAILURE"
        save_log stageToCache "STATUS=$STATUS($rc)"
    fi
    save_log stageToCache "END stageToCache($*)"
    return $rc
}

# function to create a new directory $1 in the MSS logical name space
# phobos is not supposed to create subdirectories within its media, beacause it is an Object Store system.
# Thus...
# - In the case of a phobos instance managing POSIX directories, we can only see the creation of a new directory as the creation of a new media, which doesn't feature any link with its relatives.
# - In the case of a phobos instance managing Tapes, apart from the very specific case of adding a new tape or driver to phobos scope, there is no sense in $(mkdir).
mkdir () {
    # <your command to make a directory in the MSS> $1
    # e.g.: /usr/local/bin/rfmkdir -p rfioServerFoo:$1

    save_log mkdir "BEGIN mkdir($*)"
    mkdir=$(type -P mkdir)
    phobos=$(type -P phobos)
    readlink=$(type -P readlink)
    
    # Check that the directory is not yet registered in phobos.
    check_exist_script="sudo $phobos dir list ${1}"
    check_exist=$($check_exist_script)
    rc=$?
    save_log mkdir "$check_exist_script return with status=$check_exist($rc)"
    if [ "${check_exist}" != "${1}" ]; then
        # Create a new directory in the file system
        create_dir_script="sudo $mkdir -p ${1}"
        create_dir=$($create_dir_script)
        rc=$?
        save_log mkdir "$create_dir_script return with status=$create_dir($rc)"
        if [ $rc == 0 ]; then
            # Phobos add this directory
            full_path_script="sudo $readlink -f ${1}"
            full_path=$($full_path_script)
            dir_add_script="sudo $phobos dir add ${full_path}"
            dir_add=$($dir_add_script >> $LOGFILE_FANCY 2>&1)
            rc=$?
            save_log mkdir "$dir_add_script return with status=$dir_add($rc)"
            if [ $rc == 0 ]; then
                # Phobos format this directory
                dir_format_script="sudo $phobos dir format ${full_path}"
                dir_format=$($dir_format_script >> $LOGFILE_FANCY 2>&1)
                rc=$?
                save_log mkdir "$dir_format_script return with status=$dir_format($rc)"
                if [ $rc == 0 ]; then
                    # Phobos unlock this directory
                    dir_unlock_script="sudo $phobos dir unlock ${full_path}"
                    dir_unlock=$($dir_unlock_script >> $LOGFILE_FANCY 2>&1)
                    rc=$?
                    save_log mkdir "$dir_unlock_script return with status=$dir_unlock($rc)"
                fi
            fi
        fi
    else
        save_log mkdir "$1 already exists and is within phobos scope"
    fi

    if [ "$rc" != 0 ]; then
        STATUS="FAILURE"
        save_log mkdir "STATUS=$STATUS($rc)"
    fi
    save_log mkdir "END mkdir($*)"
    return $rc
}

# function to modify ACLs $2 (octal) in the MSS logical name space for a given directory $1
# phobos authorisations have nothing to do with POSIX authorisations.
# So we can only call for the later ones on the arguments and hope for the best...
chmod () {
    # <your command to modify ACL> $2 $1
    # e.g: /usr/local/bin/rfchmod $2 rfioServerFoo:$1
    ############
    # LEAVING THE PARAMETERS "OUT OF ORDER" ($2 then $1)
    #    because the driver provides them in this order
    # $2 is mode
    # $1 is directory
    ############

    #ichmod -r write bobby ./training_jpgs # i.e. op='ichmod -r' $2='write bobby' $1='./training_jpgs'
    #phobos tape set-access +PGD 07300[0-9]L8 # i.e. op='phobos ... -access' $2='+PGD' $1='tape_id'
    save_log chmod "BEGIN chmod($*)"
    chmod=$(type -P chmod)
    phobos=$(type -P phobos)
    readlink=$(type -P readlink)
    #chmood_script="sudo $chmod '$2' '$1'"
    #chmood=$($chmood_script) # As oppsed to what iRODS expects, $1 is not supposed to be the path to a file in the system. We give it an erzatz of permissions by saying phobos to unlock all read, write and deletion on the related object.
    rc=$?
    #save_log chmod "$chmood_script return with status=$chmood($rc)"
    if [ $rc == 0 ]; then
        full_path_script="sudo $readlink -f ${1}"
        full_path=$($full_path_script)
        ph_chmood_script="sudo $phobos dir set-access +PGD ${full_path}"
        ph_chmood=$($ph_chmood_script >> $LOGFILE_FANCY 2>&1)
        rc=$?
        save_log chmod "$ph_chmood_script return with status=$ph_chmood($rc)"
    fi

    if [ "$rc" != 0 ]; then
        STATUS="FAILURE"
        save_log chmod "STATUS=$STATUS($rc)"
    fi
    save_log chmod "END chmod($*)"
    return $rc
}

# function to remove a file $1 from phobos
rm () {
    # <your command to remove a file from phobos> $1
    # e.g: /usr/local/bin/rfrm rfioServerFoo:$1
    
    save_log rm "BEGIN rm($*)"
    phobos=$(type -P phobos)
    ph_del_script="sudo $phobos del ${1}"
    ph_del=$($ph_del_script >> $LOGFILE_FANCY 2>&1)
    rc=$?
    save_log rm "$ph_del_script return with status=$ph_del($rc)"
    
    if [ "$rc" != 0 ]; then
        STATUS="FAILURE"
        save_log rm "STATUS=$STATUS($rc)"
    fi
    save_log rm "END rm($*)"
    return $rc
}

# function to rename a file $1 into $2 in the MSS
# phobos doesn't have the ability to rename a file, or to change its location in its database.
# The only way currently is to copy $1 into a new object $2, which can be done in two steps :
# - GET the object $1 into a /tmp/phobos_mv file ;
# - PUT the file /tmp/phobos_mv into an object $2 ;
# - DEL the object $1 from phobos.
mv () {
    # <your command to rename a file in the MSS> $1 $2
    # e.g: /usr/local/bin/rfrename rfioServerFoo:$1 rfioServerFoo:$2
    
    save_log mv "BEGIN mv($*)"
    phobos=$(type -P phobos)
    rm=$(type -P rm)
    temp="/tmp/phobos_mv"

    # GET the object $1 into a temporary file.
    ph_get_script="sudo $phobos get ${1} ${temp}"
    ph_get=$($ph_get_script >> $LOGFILE_FANCY 2>&1)
    rc=$?
    save_log mv "$ph_get_script return with status=$ph_get($rc)"
    if [ $rc == 0 ]; then
        # PUT the file /tmp/phobos_mv into an object $2.
        ph_put_script="sudo $phobos put -f dir ${temp} ${2}"
        ph_put=$(ph_put_script >> $LOGFILE_FANCY 2>&1)
        rc=$?
        save_log mv "$ph_put_script return with status=$ph_put($rc)"
        if [ $rc == 0 ]; then
            # DEL the object $1 from phobos.
            ph_del_script="sudo $phobos del ${1}"
            ph_del=$($ph_del_script >> $LOGFILE_FANCY 2>&1)
            rc=$?
            save_log mv "$ph_del_script return with status=$ph_del($rc)"
            if [ $rc == 0 ]; then
                rm_temp_script="sudo $rm -f ${temp}"
                rm_temp=$($rm_temp_script)
	        rc=$?
                save_log mv "$rm_temp return with status=$rm_temp($rc)"
            fi
        else # In case of failure, we still need to remove the temporary copy.
            rm_temp_script="sudo $rm -f ${temp}"
            rm_temp=$($rm_temp_script)
            rc=$?
            save_log mv "$rm_temp return with status=$rm_temp($rc)"
        fi
    else # In case of failure, we still need to remove the temporary copy, (if it happened to be created).
        if [ -f "$2" ]; then
            rm_temp_script="sudo $rm -f ${temp}"
	    rm_temp=$($rm_temp_script)
            rc=$?
            save_log mv "$rm_temp return with status=$rm_temp($rc)"
        fi
    fi

    if [ $rc != 0 ]; then
        STATUS="FAILURE"
        save_log mv "STATUS=$STATUS($rc)"
    fi
    save_log mv "END mv($*)"
    return $rc
}

# function to do a stat on a file $1 stored in phobos
stat () {
    # <your command to retrieve stats on the file> $1
    # e.g: output=$(/usr/local/bin/rfstat rfioServerFoo:$1)
    save_log stat "BEGIN stat($*)"
    phobos=$(type -P phobos)
    json_output_script="sudo $phobos object list ${1} -t -o user_md -f human"
    json_output=$($json_output_script)
    rc=$?
    save_log stat "$json_output_script return with status=$json_output($rc)"
    if [ $rc == 0 ]; then
        keys_order=("device" "inode" "mode" "nlink" "uid" "gid" "devid" "size" "blksize" "blkcnt" "atime" "mtime" "ctime")
        irods_output=$(echo "$json_output" | jq -r --argjson keys "$(printf '%s\n' "${keys_order[@]}" | jq -R . | jq -s .)" '
  [
    . as $in | $keys[] | $in[.]
  ] | join(":")
')
        rc=$?
	save_log stat "function ends with status=($rc), exporting string:\n${irods_output}"
        if [ $rc == 0 ]; then
            echo "${irods_output}"
        else
            echo "0:0:0:0:0:0:0:0:0:0:0:0:0"
        fi
    fi
    
    if [ $rc != 0 ]; then
        STATUS="FAILURE"
        save_log stat "STATUS=$STATUS($rc)"
    fi
    save_log stat "END stat($*)"
    return $rc
}

#######################
# Secondary functions #
#######################

# Outputs a log line in stdout, or in $LOGFILE if any.
save_log() {
    if [ $LEVEL -eq $DEBUG ]; then
        timestamp=$(date +"%Y:%m:%d-%T.%N")
        # Messages building
        if [ "$2" ]; then
            message_colour="${Black}${ID} ${Green}[${timestamp}] ${Red}${1}(${Blue}${2}${Red})${Color_Off}"
            message_black="${ID} [${timestamp}] ${1}(${2})"
        else
            message_colour="${Black}${ID} ${Red}${1}${Color_Off}"
            message_black="${ID} ${1}"
        fi

        # Message(s) writing on file(s)
        if [ -n "${LOGFILE_FANCY+x}" ]; then
            if [ "$LOGFILE_FANCY" != "" ]; then
                echo -e "$message_colour" >> "$LOGFILE_FANCY"
            fi
        fi

        if [ -n "${LOGFILE_SOBRE+x}" ]; then
            if [ "$LOGFILE_SOBRE" != "" ]; then
                echo -e "$message_black" >> "$LOGFILE_SOBRE"
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
    fi
    return 0
}

# Checks whether phobos daemon is started. If not, tries to start it.
# If start fails, raises an error.
get_phobosd() {
    save_log get_phobosd "BEGIN get_phobosd($*)"
    phobos=$(type -P phobos)
    phd_ping_script="sudo $phobos ping phobosd"
    phd_ping=$($phd_ping_script >> $LOGFILE_FANCY 2>&1)
    rc=$?
    save_log get_phobosd "$phd_ping_script return with status=$phd_ping($rc)"
    if [ $rc != 0 ]; then
        # The ping failed. Try to start phobos daemon
        phd_start_script="sudo systemctl start phobosd"
        phd_start=$($phd_start_script)
        rc=$?
        save_log get_phobosd "$phd_start_script return with status=$phd_start($rc)"
        if [ $rc == 0 ]; then
            # Try to ping again phobosd after the start attempt
            phd_ping_script="sudo $phobos ping phobosd"
            phd_ping=$($phd_ping_script >> $LOGFILE_FANCY 2>&1)
            rc=$?
            save_log get_phobosd "$phd_ping_script return with status=$phd_ping($rc)"
        else
            save_log get_phobosd "Impossible to communicate with Phobos daemon. Please check your Phobos and iRODS installation. Check that irods user has plain access to root privileges."
            exit $rc
        fi
    fi

    if [ "$rc" != 0 ]; then
        STATUS="FAILURE"
        save_log get_phobosd "STATUS=$STATUS($rc)"
    fi
    save_log get_phobosd "END get_phobosd($*)"
    return $rc
}

# Get metadata on file $1 using $(stat), parsing it according to univMSS template, and return the output as a hash table.
get_metadata() {
    save_log get_metadata "BEGIN get_metadata($*)"
    stat=$(type -P stat)
    output_script="sudo $stat ${1}"
    output=$($output_script)
    rc=$?
    save_log get_metadata "$output_script return with status ${rc} and output=\n${output}"
    if [ $rc == 0 ]; then
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
        # Note 2: the time should have this format: YYYY-MM-dd-hh.mm.ss with:
        #                                           YYYY = 1900 to 2xxxx, MM = 1 to 12, dd = 1 to 31,
        #                                           hh = 0 to 24, mm = 0 to 59, ss = 0 to 59
        md_str=""
        md_str+="device=$( echo "$output" | sed -nr 's/.*\<Device: *(\S*)\>.*/\1/p'),"
        md_str+="inode=$(  echo "$output" | sed -nr 's/.*\<Inode: *(\S*)\>.*/\1/p'),"
        md_str+="mode=$(   echo "$output" | sed -nr 's/.*\<Access: *\(([0-9]*)\/.*/\1/p'),"
        md_str+="nlink=$(  echo "$output" | sed -nr 's/.*\<Links: *([0-9]*)\>.*/\1/p'),"
        md_str+="uid=$(    echo "$output" | sed -nr 's/.*\<Uid: *\( *([0-9]*)\/.*/\1/p'),"
        md_str+="gid=$(    echo "$output" | sed -nr 's/.*\<Gid: *\( *([0-9]*)\/.*/\1/p'),"
        md_str+="devid=0,"
        md_str+="size=$(   echo "$output" | sed -nr 's/.*\<Size: *([0-9]*)\>.*/\1/p'),"
        md_str+="blksize=$(echo "$output" | sed -nr 's/.*\<IO Block: *([0-9]*)\>.*/\1/p'),"
        md_str+="blkcnt=$( echo "$output" | sed -nr 's/.*\<Blocks: *([0-9]*)\>.*/\1/p'),"
        md_str+="atime=$(  echo "$output" | sed -nr 's/.*\<Access: *([0-9]{4,}-[01][0-9]-[0-3][0-9]) *([0-2][0-9]):([0-5][0-9]):([0-6][0-9])\..*/\1-\2.\3.\4/p'),"
        md_str+="mtime=$(  echo "$output" | sed -nr 's/.*\<Modify: *([0-9]{4,}-[01][0-9]-[0-3][0-9]) *([0-2][0-9]):([0-5][0-9]):([0-6][0-9])\..*/\1-\2.\3.\4/p'),"
        md_str+="ctime=$(  echo "$output" | sed -nr 's/.*\<Change: *([0-9]{4,}-[01][0-9]-[0-3][0-9]) *([0-2][0-9]):([0-5][0-9]):([0-6][0-9])\..*/\1-\2.\3.\4/p')"
        echo "${md_str}"
    fi

    save_log get_metadata "END get_metadata($*)"
    return $rc
}



save_log ""
save_log "##########################"
save_log "# BEGIN EXPERIMENT $ID #"
save_log "##########################"
if [ $DISPLAY_COLOUR == 1 ]; then save_log "$Blue$0_$Purple$VERSION"; fi
if [ $DISPLAY_BLACK == 1 ]; then save_log "$0_$VERSION"; fi

#get_daemon=$(get_phobosd)
#if [ $? != 0 ]; then exit $?; fi
#check_avail_dir=$(check_dir)
#if [ $? != 0 ]; then exit $?; fi


#############################################
# below this line, nothing should be changed.
#############################################

case "$1" in
    syncToArch ) "$1" "$2" "$3" ;;
    stageToCache ) "$1" "$2" "$3" ;;
    mkdir ) "$1" "$2" ;;
    chmod ) "$1" "$2" "$3" ;;
    rm ) "$1" "$2" ;;
    mv ) "$1" "$2" "$3" ;;
    stat ) "$1" "$2" ;;
esac

exit $?
