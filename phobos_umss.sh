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

# TODO Laisser à l'utilisateur la possibilité de choisir entre dirs et tapes, soit par un paramètre, soit en créant 2 tiers de stockage phobos (chacun serait en relation avec un cache, et chacun serait dans une compound resource distincte).

# function for the synchronization of file $1 on local disk resource to file $2 in phobos
syncToArch () {
    # <your command or script to copy from cache to phobos> $1 $2
    # e.g: /usr/local/bin/rfcp $1 rfioServerFoo:$2
    # Syntax remainder : phobos put </path/to/local/file> <object_id>
    
    save_log syncToArch "BEGIN syncToArch($*)"
    error_1=0
    if [ "$1" ]; then
        if [ "$2" ]; then
            op_ph=$(type -P phobos)
            md_script="get_metadata ${1}"
            md=$($md_script)
            error_1=$?
            save_log syncToArch "$md_script return with integer ${error_1} and value \n${md}"
            if [ $error_1 == 0 ]; then
                echo "UNIVMSS $op_ph \"$1\" \"$2\""
                put_script="sudo $op_ph put --metadata ${md} -f dir ${1} ${2}"
                put=$($put_script >> $LOGFILE_FANCY 2>&1)
                error_1=$?
                save_log syncToArch "$put_script return with status=$put($error_1)"
	        fi
        else
            save_log syncToArch "No OID given to put data \"$1\" to"
            error_1=1
        fi
    else
        save_log syncToArch "No object given to put"
        error_1=2
    fi

    if [ "$error_1" != 0 ]; then
        STATUS="FAILURE"
        save_log syncToArch "STATUS=$STATUS($error_1)"
    fi
    save_log syncToArch "END syncToArch($*)"
    return $error_1
}

# function for staging a file $1 from phobos to file $2 on disk
stageToCache () {
    # <your command to stage from phobos to cache> $1 $2
    # Syntax Remainder : $ phobos get <object_id> </path/to/local/output/file>
    # e.g: /usr/local/bin/rfcp rfioServerFoo:$1 $2
    
    save_log stageToCache "BEGIN stageToCache($*)"
    error_2=0
    if [ "$1" ]; then
        if [ "$2" ]; then
            op_ph=$(type -P phobos)
            echo "UNIVMSS $op_ph \"$1\" \"$2\""
            # Doit être retravaillé !
            if [ -f $2 ]; then
                sudo /bin/rm $2
            fi
            get_script="sudo $op_ph get ${1} ${2}"
            get=$($get_script >> $LOGFILE_FANCY 2>&1)
            error_2=$?
            save_log stageToCache "$get_script return with status=$get($error_2)"
        else
            save_log stageToCache "No destination file to get object \"$1\" to"
            error_2=11
        fi
    else
        save_log stageToCache "No object to get"
        error_2=12
    fi

    if [ "$error_2" != 0 ]; then
        STATUS="FAILURE"
        save_log stageToCache "STATUS=$STATUS($error_2)"
    fi
    save_log stageToCache "END stageToCache($*)"
    return $error_2
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
    op_mk=$(type -P mkdir)
    op_ph=$(type -P phobos)
    op_rd=$(type -P readlink)
    
    # Check that the directory is not yet registered in phobos.
    check_exist_script="sudo $op_ph dir list ${1}"
    check_exist=$($check_exist_script)
    error_3=$?
    save_log mkdir "$check_exist_script return with status=$check_exist($error_3)"
    if [ "${check_exist}" != "${1}" ]; then
        # Create a new directory in the file system
        create_dir_script="sudo $op_mk -p ${1}"
        create_dir=$($create_dir_script)
        error_3=$?
        save_log mkdir "$create_dir_script return with status=$create_dir($error_3)"
        if [ $error_3 == 0 ]; then
            # Phobos add this directory
            full_path_script="sudo $op_rd -f ${1}"
            full_path=$($full_path_script)
            dir_add_script="sudo $op_ph dir add ${full_path}"
            dir_add=$($dir_add_script >> $LOGFILE_FANCY 2>&1)
            error_3=$?
            save_log mkdir "$dir_add_script return with status=$dir_add($error_3)"
            if [ $error_3 == 0 ]; then
                # Phobos format this directory
                dir_format_script="sudo $op_ph dir format ${full_path}"
                dir_format=$($dir_format_script >> $LOGFILE_FANCY 2>&1)
                error_3=$?
                save_log mkdir "$dir_format_script return with status=$dir_format($error_3)"
                if [ $error_3 == 0 ]; then
                    # Phobos unlock this directory
                    dir_unlock_script="sudo $op_ph dir unlock ${full_path}"
                    dir_unlock=$($dir_unlock_script >> $LOGFILE_FANCY 2>&1)
                    error_3=$?
                    save_log mkdir "$dir_unlock_script return with status=$dir_unlock($error_3)"
                fi
            fi
        fi
    else
        save_log mkdir "$1 already exists and is within phobos scope"
    fi

    if [ "$error_3" != 0 ]; then
        STATUS="FAILURE"
        save_log mkdir "STATUS=$STATUS($error_3)"
    fi
    save_log mkdir "END mkdir($*)"
    return $error_3
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
    op_sys=$(type -P chmod)
    op_ph=$(type -P phobos)
    op_rd=$(type -P readlink)
    #chmood_script="sudo $op_sys '$2' '$1'"
    #chmood=$($chmood_script) # As oppsed to what iRODS expects, $1 is not supposed to be the path to a file in the system. We give it an erzatz of permissions by saying phobos to unlock all read, write and deletion on the related object.
    error_4=$?
    #save_log chmod "$chmood_script return with status=$chmood($error_4)"
    if [ $error_4 == 0 ]; then
        full_path_script="sudo $op_rd -f ${1}"
        full_path=$($full_path_script)
        ph_chmood_script="sudo $op_ph dir set-access +PGD ${full_path}"
        ph_chmood=$($ph_chmood_script >> $LOGFILE_FANCY 2>&1)
        error_4=$?
        save_log chmod "$ph_chmood_script return with status=$ph_chmood($error_4)"
    fi

    if [ "$error_4" != 0 ]; then
        STATUS="FAILURE"
        save_log chmod "STATUS=$STATUS($error_4)"
    fi
    save_log chmod "END chmod($*)"
    return $error_4
}

# function to remove a file $1 from phobos
rm () {
    # <your command to remove a file from phobos> $1
    # e.g: /usr/local/bin/rfrm rfioServerFoo:$1
    
    save_log rm "BEGIN rm($*)"
    op_ph=$(type -P phobos)
    ph_del_script="sudo $op_ph del ${1}"
    ph_del=$($ph_del_script >> $LOGFILE_FANCY 2>&1)
    error_5=$?
    save_log rm "$ph_del_script return with status=$ph_del($error_5)"
    
    if [ "$error_5" != 0 ]; then
        STATUS="FAILURE"
        save_log rm "STATUS=$STATUS($error_5)"
    fi
    save_log rm "END rm($*)"
    return $error_5
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
    op_ph=$(type -P phobos)
    op_sys=$(type -P rm)
    temp="/tmp/phobos_mv"

    # GET the object $1 into a temporary file.
    ph_get_script="sudo $op_ph get ${1} ${temp}"
    ph_get=$($ph_get_script >> $LOGFILE_FANCY 2>&1)
    error_6=$?
    save_log mv "$ph_get_script return with status=$ph_get($error_6)"
    if [ $error_6 == 0 ]; then
        # PUT the file /tmp/phobos_mv into an object $2.
        ph_put_script="sudo $op_ph put -f dir ${temp} ${2}"
        ph_put=$(ph_put_script >> $LOGFILE_FANCY 2>&1)
        error_6=$?
        save_log mv "$ph_put_script return with status=$ph_put($error_6)"
        if [ $error_6 == 0 ]; then
            # DEL the object $1 from phobos.
            ph_del_script="sudo $op_ph del ${1}"
            ph_del=$($ph_del_script >> $LOGFILE_FANCY 2>&1)
            error_6=$?
            save_log mv "$ph_del_script return with status=$ph_del($error_6)"
            if [ $error_6 == 0 ]; then
                rm_temp_script="sudo $op_sys -f ${temp}"
                rm_temp=$($rm_temp_script) # TODO Trouver un moyen plus sécuritaire serait utile.
                error_6=$?
                save_log mv "$rm_temp return with status=$rm_temp($error_6)"
            fi
        else # In case of failure, we still need to remove the temporary copy.
            rm_temp_script="sudo $op_sys -f ${temp}"
            rm_temp=$($rm_temp_script) # TODO Trouver un moyen plus sécuritaire serait utile.
            error_6=$?
            save_log mv "$rm_temp return with status=$rm_temp($error_6)"
        fi
    else # In case of failure, we still need to remove the temporary copy, (if it happened to be created).
        if [ -f "$2" ]; then
            rm_temp_script="sudo $op_sys -f ${temp}"
            rm_temp=$($rm_temp_script) # TODO TYrouver un moyen plus sécuritaire serait utile.
            error_6=$?
            save_log mv "$rm_temp return with status=$rm_temp($error_6)"
        fi
    fi

    if [ $error_6 != 0 ]; then
        STATUS="FAILURE"
        save_log mv "STATUS=$STATUS($error_6)"
    fi
    save_log mv "END mv($*)"
    return $error_6
}

# function to do a stat on a file $1 stored in phobos
# Pour l'heure, on se contente d'extraire via $(phobos extent list -o media_name,address) le chemin du premier extent retourné dans le système de fichiers, et d'appeler $(stat) dessus pour appliquer les Regexps présentées dans le template des UMSS.
stat () {
    # <your command to retrieve stats on the file> $1
    # e.g: output=$(/usr/local/bin/rfstat rfioServerFoo:$1)
    save_log stat "BEGIN stat($*)"
    op_ph=$(type -P phobos)
    json_output_script="sudo $op_ph object list ${1} -t -o user_md -f human"
    json_output=$($json_output_script)
    error_7=$?
    save_log stat "$json_output_script return with status=$json_output($error_7)"
    if [ $error_7 == 0 ]; then
        keys_order=("device" "inode" "mode" "nlink" "uid" "gid" "devid" "size" "blksize" "blkcnt" "atime" "mtime" "ctime")
        irods_output=$(echo "$json_output" | jq -r --argjson keys "$(printf '%s\n' "${keys_order[@]}" | jq -R . | jq -s .)" '
  [
    . as $in | $keys[] | $in[.]
  ] | join(":")
')
        error_7=$?
	save_log stat "function ends with status=($error_7), exporting string:\n${irods_output}"
        if [ $error_7 == 0 ]; then
            echo "${irods_output}"
        else
            echo "0:0:0:0:0:0:0:0:0:0:0:0:0"
        fi
    fi
    
    if [ $error_7 != 0 ]; then
        STATUS="FAILURE"
        save_log stat "STATUS=$STATUS($error_7)"
    fi
    save_log stat "END stat($*)"
    return $error_7
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
    op_ph=$(type -P phobos)
    phd_ping_script="sudo $op_ph ping phobosd"
    phd_ping=$($phd_ping_script >> $LOGFILE_FANCY 2>&1)
    error_8=$?
    save_log get_phobosd "$phd_ping_script return with status=$phd_ping($error_8)"
    if [ $error_8 != 0 ]; then
        # The ping failed. Try to start phobos daemon
        phd_start_script="sudo systemctl start phobosd"
        phd_start=$($phd_start_script)
        error_8=$?
        save_log get_phobosd "$phd_start_script return with status=$phd_start($error_8)"
        if [ $error_8 == 0 ]; then
            # Try to ping again phobosd after the start attempt
            phd_ping_script="sudo $op_ph ping phobosd"
            phd_ping=$($phd_ping_script >> $LOGFILE_FANCY 2>&1)
            error_8=$?
            save_log get_phobosd "$phd_ping_script return with status=$phd_ping($error_8)"
        else
            save_log get_phobosd "Impossible to communicate with Phobos daemon. Please check your Phobos and iRODS installation. Check that irods user has plain access to root privileges."
            exit $error_8
        fi
    fi

    if [ "$error_8" != 0 ]; then
        STATUS="FAILURE"
        save_log get_phobosd "STATUS=$STATUS($error_8)"
    fi
    save_log get_phobosd "END get_phobosd($*)"
    return $error_8
}

# Get metadata on file $1 using $(stat), parsing it according to univMSS template, and return the output as a hash table.
get_metadata() {
    save_log get_metadata "BEGIN get_metadata($*)"
    op=$(type -P stat)
    output_script="sudo $op ${1}"
    output=$($output_script)
    error_9=$?
    save_log get_metadata "$output_script return with status ${error_9} and output=\n${output}"
    if [ $error_9 == 0 ]; then
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
    return $error_9
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
