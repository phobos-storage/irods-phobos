#!/bin/bash
#
#  All rights reserved (c) 2014-2022 CEA/DAM.
#
#  This file is part of Phobos.
#
#  Phobos is free software: you can redistribute it and/or modify it under
#  the terms of the GNU Lesser General Public License as published by
#  the Free Software Foundation, either version 2.1 of the License, or
#  (at your option) any later version.
#
#  Phobos is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU Lesser General Public License for more details.
#
#  You should have received a copy of the GNU Lesser General Public License
#  along with Phobos. If not, see <http://www.gnu.org/licenses/>.
#

# This file contains unit tests related to the Phobos UnivMSS plugin for iRODS.
#
####
########
############
# This file is to be run using the shUnit2 framework:
# "https://github.com/kward/shunit2"
# The absolute path to the shUnit2 executable file must be set below.
# Note that Phobos commands require super-user prvileges to run.
#
# This script can automate the connexion to iRODS as a given user, using the
# `irods_init.exp` script, which requires the Linux `expect` tool installed
# to work: "https://github.com/aeruder/expect". Its path should also be given
# below.
############
########
####
#
############################################################################
# PLEASE ENTER HERE THE ABSOLUTE PATH TO IRODS_INIT FILE
irods_init="/root/shunit2-2.1.8/examples/irods_init.exp"
# PLEASE ENTER HERE THE ABSOLUTE PATH TO SHUNIT2 EXECUTABLE
shunit2="/root/shunit2-2.1.8/shunit2"
############################################################################

# Run once before all tests.
oneTimeSetUp() {
    # Name and path of the UMMS script to test
    umssRepo="/var/lib/irods/msiExecCmd_bin" #Default path
    umssName="phobos_mss_20240506.sh"
    umss="${umssRepo}/${umssName}"

    # Info about the iRODS zone
    zoneIP=127.0.0.1
    zonePort=1247
    zoneName="tempZone"

    # Info about the iRODS resources
    unixResc="demoResc"
    compoundResc="CompoundTest"
    cacheRescRepo="/var/lib/irods"
    cacheRescName="PosixTest"
    cacheResc="${cacheRescRepo}/${cacheRescName}"
    archiveRescRepo="/var/lib/irods"
    archiveRescName="PhobosTest"
    archiveResc="${archiveRescRepo}/${archiveRescName}"

    # Info about the iRODS users registered on the zone
    adminName="rods" #Default in iRODS tutorial
    adminPswd="rods" #Default in iRODS tutorial
    non_adminName="alice"
    non_adminPswd="alice"

    # Info about the user account that will perform the tests
    userName="${adminName}"
    userPswd="${adminPswd}"

    # Init the Phobos and iRODS environment.
    systemctl start phobosd
    expect "${irods_init}" "${zoneIP}" "${zonePort}" "${userName}"\
    "${zoneName}" "${userPswd}" >> /dev/null 2>&1

    # Init some files and directories to play with.
    counter=0
    mkdir -p ./testFiles/dir_0/dir_0_0
    mkdir -p ./testFiles/dir_1
    n=30
    for ((k=0; k<n; k++)); do
        local f
        f="./testFiles/file_${k}.txt"
        echo "This '${k}' is provided to you by file_${k}." > "$f"
        f="./testFiles/dir_0/file_0_${k}.txt"
        echo "This '${k}' is provided to you by file_0_${k}." > "$f"
        f="./testFiles/dir_0/dir_0_0/file_0_0_${k}.txt"
        echo "This '${k}' is provided to you by file_0_0_${k}." > "$f"
        f="./testFiles/dir_1/file_1_${k}.txt"
        echo "This '${k}' is provided to you by file_1_${k}." > "$f"
    done
    return 0
}

# Run once after all tests.
oneTimeTearDown() {
    rm -fr ./testFiles
    #systemctl stop phobosd
    iexit full
    rm -f /root/.irods/irods_environment.json
    return 0
}

# Run before each test.
setUp() {
    return 0
}

# Run after each test.
tearDown() {
    counter=$((counter+1))
    if [ ${counter} -ge ${n} ]; then
        echo "WARNING: file_counter=${counter} >= number_of_files=${n}"
    fi
    return 0
}

####
########
####
# The basic_ test set is about the behaviour of all iRODS functions of
# the script in optimal conditions, i.e. the environment of these\
# executions is free of traps, all files exist and no failure should occur.
####

test_basic_syncToArch() {
    # Init variables
    local rc
    local fileName
    local objectName
    local copyName

    # Setting variables
    fileName="./testFiles/file_${counter}.txt"
    objectName="file_${counter}"
    copyName="./thisIsTheCopy_${counter}"

    # Operation of interest
    ####
    sh ${umss} syncToArch "${fileName}" "${objectName}"
    rc=$?
    ####

    # Examining resulting environment.
    assertEquals "Function ${FUNCNAME[0]} ends with code ${rc} != 0" ${rc} 0
    assertEquals "Object ${objectName} not found in Phobos"\
    "$(phobos object list ${objectName})" "${objectName}"

    phobos get "${objectName}" "${copyName}"
    assertEquals "Object ${fileName} write corrupted" "$(cat ${copyName})"\
    "$(cat ${fileName})"

    # Ending the test
    phobos delete "${objectName}"
    rm -f "${copyName}"
}


test_basic_stageToCache() {
    # Init variables
    local rc
    local fileName
    local objectName
    local copyName

    # Setting variables
    fileName="./testFiles/file_${counter}.txt"
    objectName="file_${counter}"
    copyName="./thisIsTheCopy_${counter}"

    # Setting up the environment
    phobos put "${fileName}" "${objectName}"

    # Operation of interest
    ####
    sh ${umss} stageToCache "${objectName}" "${copyName}"
    rc=$?
    ####

    # Examining resulting environment
    assertEquals "Function ${FUNCNAME[0]} ends with code ${rc} != 0" ${rc} 0
    assertEquals "${fileName} data has been corrupted"\
    "$(cat ${copyName})" "$(cat ${fileName})"

    # Ending the test
    phobos delete "${objectName}"
    rm -f "${copyName}"
}


test_basic_mkdir() {
    # iRODS-Phobos mkdir performs nothing. We only need it to return "success"
    local rc

    ####
    sh ${umss} mkdir "/${zoneName}/home/${userName}/testdir"
    rc=$?
    ####

    assertEquals "Function ${FUNCNAME[0]} ends with code ${rc} != 0" ${rc} 0
}


test_basic_chmod() {
    # iRODS-Phobos chmod performs nothing. We only need it to return "success"
    local rc

    ####
    sh ${umss} chmod "/${zoneName}/home/${userName}" 750
    rc=$?
    ####

    assertEquals "Function ${FUNCNAME[0]} ends with code ${rc} != 0" ${rc} 0
}


test_basic_rm() {
    local rc
    local fileName
    local objectName

    fileName="./testFiles/file_${counter}.txt"
    objectName="file_${counter}"
    phobos put "${fileName}" "${objectName}"

    ####
    sh ${umss} rm "${objectName}"
    rc=$?
    ####

    assertEquals "Function ${FUNCNAME[0]} ends with code ${rc} != 0" ${rc} 0
    assertEquals "Object ${objectName} still alive in Phobos."\
    "$(phobos object list ${objectName})" ""
}


test_basic_mv() {
    local rc
    local fileName
    local objectName
    local newObjectName
    local copyName
    local originObjMD
    local newObjMD

    fileName="./testFiles/file_${counter}.txt"
    objectName="file_${counter}"
    newObjectName="my_${counter}"
    copyName="./thisIsTheCopy_${counter}"
    # We want to move metadata with the object on Phobos, and recording MDs is
    # possible iff it was stored using the UMSS script. If syncToArch fails,
    # it is not relevant to test mv on corrupted data in a basic_ test.
    sh ${umss} syncToArch "${fileName}" "${objectName}"
    rc=$?
    assertEquals "syncToArch ends with code ${rc} != 0" ${rc} 0
    assertEquals "Object ${objectName} not sync with Phobos"\
    "$(phobos object list ${objectName})" "${objectName}"

    originObjMD=$(phobos object list "${objectName}" -t -o user_md -f human)

    ####
    sh ${umss} mv "${objectName}" "${newObjectName}"
    rc=$?
    ####

    assertEquals "Function ${FUNCNAME[0]} ends with code ${rc} != 0" ${rc} 0
    assertEquals "Object ${objectName} still alive in Phobos."\
    "$(phobos object list ${objectName})" ""
    assertEquals "Object ${newObjectName} not found in Phobos"\
    "$(phobos object list ${newObjectName})" "${newObjectName}"

    newObjMD=$(phobos object list "${newObjectName}" -t -o user_md -f human)
    assertEquals "Object metadata not preserved" "${originObjMD}"\
    "${newObjMD}"

    phobos get "${newObjectName}" "${copyName}"
    assertEquals "${fileName} data has been corrupted"\
    "$(cat ${copyName})" "$(cat ${fileName})"

    # Ending the test.
    phobos delete "${newObjectName}"
    rm -f "${copyName}"
}


test_basic_stat() {
    local rc
    local fileName
    local objectName
    local metadata

    fileName="./testFiles/file_${counter}.txt"
    objectName="file_${counter}"
    # Get stats on a Phobos object is possible iff it was stored
    # using the UMSS script. If syncToArch fails, it is not relevant to test
    # stat on corrupted data in a basic_ test.
    sh ${umss} syncToArch "${fileName}" "${objectName}"
    rc=$?
    assertEquals "syncToArch ends with code ${rc} != 0" ${rc} 0
    assertEquals "Object ${objectName} not sync with Phobos"\
    "$(phobos object list ${objectName})" "${objectName}"

    ####
    metadata=$(sh ${umss} stat "${objectName}")
    rc=$?
    ####

    assertEquals "Function ${FUNCNAME[0]} ends with code ${rc} != 0" ${rc} 0
    assertFalse "No metadata returned" "[ -z ${metadata} ]"

    # Ending the test.
    phobos delete "${objectName}"
}

####
########
####
# The following functions test the behaviour of UMSS functions in unusual
# cases.
####

test_STA_nonexistant_file() {
    # When trying to put an nonexistant file, synctoArch must return an error,
    # without creating any object in Phobos.
    local rc
    local fileName
    local objectName

    fileName="./This_is_nonexistant_file_number_${counter}.idkm"
    objectName="file_${counter}"

    ####
    sh ${umss} syncToArch "${fileName}" "${objectName}"
    rc=$?
    ####

    assertNotEquals "Function ${FUNCNAME[0]} ends with code ${rc} = 0" ${rc} 0
    assertEquals "Object ${objectName} found in Phobos"\
    "$(phobos object list ${objectName})" ""
}


test_STA_update_existing_object() {
    # When trying to put a file in an already existing object, syncToArch must
    # update the object, creating a new Phobos version of it.
    local rc
    local firstFileName
    local objectName
    local v1
    local md1
    local secondFileName
    local v2
    local md2
    local copyName

    firstFileName="./testFiles/file_${counter}.txt"
    objectName="file_${counter}"
    secondFileName="./testFiles/dir_0/file_0_${counter}.txt"
    copyName="./thisIsTheCopy_${counter}"

    # Put a file, first.
    sh ${umss} syncToArch "${firstFileName}" "${objectName}"
    rc=$?

    assertEquals "Function ${FUNCNAME[0]}_1 ends with code ${rc} != 0" ${rc} 0
    assertEquals "Object ${objectName} not found in Phobos"\
    "$(phobos object list ${objectName})" "${objectName}"
    v1=$(phobos object list ${objectName} -o version)
    md1=$(sh ${umss} stat "${objectName}")

    ####
    sh ${umss} syncToArch "${secondFileName}" "${objectName}"
    rc=$?
    ####

    assertEquals "Function ${FUNCNAME[0]}_2 ends with code ${rc} != 0" ${rc} 0
    v2=$(phobos object list ${objectName} -o version)
    md2=$(sh ${umss} stat "${objectName}")
    assertTrue "Version changed from ${v1} to ${v2}" "[ $v2 -eq $((v1 + 1)) ]"
    # We know that, field "inode" is unique among files of the local
    # filesystem. So metadata must be changed from one version to the other.
    assertNotEquals "Metadata not updated" "${md1}" "${md2}"

    phobos get ${objectName} ${copyName}
    assertEquals "${secondFileName} data has been corrupted"\
    "$(cat ${copyName})" "$(cat ${secondFileName})"

    # Ending the test
    phobos delete "${objectName}"
    rm -f "${copyName}"
}


test_STC_nonexistant_object() {
    # For this test, stageToCache must return an error, without creating any
    # file on the targeted system.
    local rc
    local objectName
    local copyName

    objectName="This_is_nonexistant_object_number_${counter}"
    copyName="./thisIsTheCopy_${counter}"

    ####
    sh ${umss} stageToCache "${objectName}" "${copyName}"
    rc=$?
    ####

    assertNotEquals "Function ${FUNCNAME[0]} ends with code ${rc} = 0" ${rc} 0
    assertFalse "File ${copyName} exists" "[ -f ${copyName} ]"
}


test_STC_existant_file() {
    # For this test, stageToCache must erase the existing file to allow Phobos
    # to get the object into a new eponym file.
    local rc
    local fileName
    local objectName
    local oneString
    local copyName

    fileName="./testFiles/file_${counter}.txt"
    objectName="file_${counter}"
    copyName="./thisIsTheCopy_${counter}"
    oneString="I'm sorry Dave, I'm afraid I can't do that."

    # Creating a destination file.
    echo "${oneString}" > "${copyName}"
    phobos put "${fileName}" "${objectName}"

    ####
    sh ${umss} stageToCache "${objectName}" "${copyName}"
    rc=$?
    ####

    assertEquals "Function ${FUNCNAME[0]} ends with code ${rc} != 0" ${rc} 0
    assertNotEquals "${copyName} not erased." "$(cat ${copyName})"\
    "${oneString}"
    assertEquals "${copyName} not properly modified." "$(cat ${copyName})"\
    "$(cat ${fileName})"

    # Ending the test
    phobos delete "${objectName}"
    rm -f "${copyName}"
}


test_rm_nonexistant_object() {
    # For this test, rm must return an error.
    local rc
    local objectName

    objectName="This_is_nonexistant_object_number_${counter}"

    ####
    sh ${umss} rm "${objectName}"
    rc=$?
    ####

    assertNotEquals "Function ${FUNCNAME[0]} ends with code ${rc} = 0" ${rc} 0
}


test_mv_nonexistant_object() {
    # For this test, mv must return an error and no modification shall occur.
    local rc
    local objectName
    local newObjectName

    objectName="This_is_nonexistant_object_number_${counter}"
    newObjectName="my_${counter}"

    ####
    sh ${umss} mv "${objectName}" "${newObjectName}"
    rc=$?
    ####

    assertNotEquals "Function ${FUNCNAME[0]} ends with code ${rc} = 0" ${rc} 0
    assertNotEquals "Object ${objectName} found in Phobos."\
    "$(phobos object list ${objectName})" "${objectName}"
    assertNotEquals "Object ${newObjectName} found in Phobos"\
    "$(phobos object list ${newObjectName})" "${newObjectName}"
}


test_mv_to_already_taken_oid() {
    # For this test, mv must return an error and no modification shall occur.
    local rc
    local fileName_1
    local objectName_1
    local objMD_1_bfr
    local objMD_1_aft
    local copyName_2
    local fileName_2
    local objectName_2
    local objMD_2_bfr
    local objMD_2_aft
    local copyName_2

    # Put first object
    fileName_1="./testFiles/file_${counter}.txt"
    objectName_1="file_1_${counter}"
    sh ${umss} syncToArch "${fileName_1}" "${objectName_1}"
    rc=$?
    assertEquals "syncToArch ends with code ${rc} != 0" ${rc} 0
    assertEquals "Object ${objectName_1} not sync with Phobos"\
    "$(phobos object list ${objectName_1})" "${objectName_1}"
    objMD_1_bfr=$(phobos object list "${objectName_1}" -t -o user_md -f human)

    # Put second object
    fileName_2="./testFiles/dir_0/file_0_${counter}.txt"
    objectName_2="file_2_${counter}"
    sh ${umss} syncToArch "${fileName_2}" "${objectName_2}"
    rc=$?
    assertEquals "syncToArch ends with code ${rc} != 0" ${rc} 0
    assertEquals "Object ${objectName_2} not sync with Phobos"\
    "$(phobos object list ${objectName_2})" "${objectName_2}"
    objMD_2_bfr=$(phobos object list "${objectName_2}" -t -o user_md -f human)

    ####
    sh ${umss} mv "${objectName_1}" "${objectName_2}"
    rc=$?
    ####

    assertNotEquals "Function ${FUNCNAME[0]} ends with code ${rc} = 0" ${rc} 0
    assertEquals "Object ${objectName_1} still alive in Phobos."\
    "$(phobos object list ${objectName_1})" "${objectName_1}"
    assertEquals "Object ${objectName_2} still alive in Phobos"\
    "$(phobos object list ${objectName_2})" "${objectName_2}"

    # Assert that the content of objects has not been modified.
    copyName_1="./thisIsTheCopy_number_1_${counter}"
    copyName_2="./thisIsTheCopy_number_2_${counter}"
    phobos get "${objectName_1}" "${copyName_1}"
    phobos get "${objectName_2}" "${copyName_2}"
    assertEquals "${objectName_1} has been modified" "$(cat ${fileName_1})"\
    "$(cat ${copyName_1})"
    assertEquals "${objectName_2} has been modified" "$(cat ${fileName_2})"\
    "$(cat ${copyName_2})"
    assertNotEquals "Objects are eventually bot: \n$(cat ${copyName_1})"\
    "$(cat ${copyName_1})" "$(cat ${copyName_2})"

    # Assert that metadata of objects have not been modified.
    objMD_1_aft=$(phobos object list "${objectName_1}" -t -o user_md -f human)
    assertEquals "${objectName_1} metadata modified." "${objMD_1_bfr}"\
    "${objMD_1_aft}"
    objMD_2_aft=$(phobos object list "${objectName_2}" -t -o user_md -f human)
    assertEquals "${objectName_2} metadata modified." "${objMD_2_bfr}"\
    "${objMD_2_aft}"
    assertNotEquals "Metadata of objects are eventually the same."\
    "${objMD_1_aft}" "${objMD_2_aft}"

    # Ending the test.
    phobos delete "${objectName_1}" "${objectName_2}"
    rm -f "${copyName_1}" "${copyName_2}"
}

test_stat_nonexistant_file() {
    local rc
    local objectName
    local metadata

    objectName="This_is_nonexistant_object_number_${counter}"

    ####
    metadata=$(sh ${umss} stat "${objectName}")
    rc=$?
    ####

    assertNotEquals "Function ${FUNCNAME[0]} ends with code ${rc} = 0" ${rc} 0
    assertTrue "Some metadata returned: \n${metadata}" "[ -z ${metadata} ]"
    assertNotEquals "Object ${objectName} found in Phobos"\
    "$(phobos object list ${objectName})" "${objectName}"
}

####
########
####
# The remaining functions test the irods calls to UMSS functions.
# The objective here is to assert whether the UMSS can make to make iRODS
# communicate with a Phobos-based Storage Resource as intended, or not.

# NOTE 1: only normal cases are tested in this section: cases that should not
# fail. Because we only want to assert that irods operations can call for UMSS
# script's functions to communicate with iRODS. Failures from these functions
# have already been tested above, and if one of them is called on a bad
# environment, it is iRODS' responsibility to detect it in advance and stop the
# process.
#
# NOTE 2: only `iput`, `iget`, `irm` and `imv` are tested, because the
# behaviour of other iRODS functions is based on (at least) one of these,
# depending on the options and arguments passed.
####
test_iput_and_irm() {
    local rc
    local fileName
    local parentCollec
    local collection
    local objName
    local objPath_iRODS
    local objPath_Phobos # Remember that path in Phobos is a nonsense. In the
    # Phobos-UMSS implementation, the name (oid) of an object in Phobos is the
    # absolute path of the object in the iRODS zone.
    local metadata
    local copyName

    fileName="./testFiles/file_${counter}.txt"
    parentCollec="what"
    collection="${parentCollec}/a/nice/collection"
    objName="file_${counter}"
    objPath_iRODS="${collection}/${objName}"
    objPath_Phobos="${archiveResc}/home/${userName}/${collection}/${objName}"
    copyName="./thisIsTheCopy_${counter}"

    imkdir -p "${collection}"
    ####
    iput -R "${compoundResc}" "${fileName}" "${objPath_iRODS}"
    rc=$?
    ####

    assertEquals "Function ${FUNCNAME[0]} ends with code ${rc} != 0" ${rc} 0
    assertEquals "Object ${objPath_Phobos} not found in Phobos"\
    "$(phobos object list ${objPath_Phobos})" "${objPath_Phobos}"
    assertEquals "Data object ${objPath_iRODS} not found in iRODS"\
    "$(ils ${objPath_iRODS})"\
    "  /${zoneName}/home/${userName}/${objPath_iRODS}"

    metadata=$(sh ${umss} stat "${objPath_Phobos}")
    assertFalse "No metadata stored for ${fileName}" "[ -z ${metadata} ]"

    phobos get "${objPath_Phobos}" "${copyName}"
    assertEquals "${fileName} data has been corrupted"\
    "$(cat ${fileName})" "$(cat ${copyName})"

    # In order to end this test, we must call for `irm -f`, so we test it too.
    rm -f "${copyName}"
    ####
    irm -f "${objPath_iRODS}"
    rc=$?
    ####

    assertEquals "Function ${FUNCNAME[0]} ends with code ${rc} != 0" ${rc} 0
    ils "${objPath_iRODS}"
    rc=$?
    assertEquals "Data object ${objPath_iRODS} not deleted"\
    "$rc" "4"
    assertEquals "Object ${objPath_Phobos} found in Phobos."\
    "$(phobos object list ${objPath_Phobos})" ""

    ####
    irm -fr "${parentCollec}"
    rc=$?
    ####

    assertEquals "Function ${FUNCNAME[0]} ends with code ${rc} != 0" ${rc} 0
    ils "${collection}"
    rc=$?
    assertEquals "Collection ${collection} not deleted" "$rc" "4"
    ils "${parentCollec}"
    rc=$?
    assertEquals "Parent collection ${parentCollec} not deleted" "$rc" "4"
}

test_iget() {
    local rc
    local fileName
    local parentCollec
    local collection
    local objName
    local objPath_iRODS
    local objPath_Phobos
    local copyName

    fileName="./testFiles/file_${counter}.txt"
    parentCollec="what"
    collection="${parentCollec}/a/nice/collection"
    objName="file_${counter}"
    objPath_iRODS="${collection}/${objName}"
    objPath_Phobos="${archiveResc}/home/${userName}/${collection}/${objName}"
    copyName="./thisIsTheCopy_${counter}"

    imkdir -p "${collection}"
    iput -R "${compoundResc}" "${fileName}" "${objPath_iRODS}"
    rc=$?
    assertEquals "Function ${FUNCNAME[0]} ends with code ${rc} != 0" ${rc} 0

    ####
    iget "${objPath_iRODS}" "${copyName}"
    rc=$?
    ####

    assertEquals "Function ${FUNCNAME[0]} ends with code ${rc} != 0" ${rc} 0
    assertEquals "${fileName} data has been corrupted"\
    "$(cat ${fileName})" "$(cat ${copyName})"

    irm -fr "${parentCollec}"
    rm ${copyName}
}

test_imv() {
    local rc
    local fileName
    local parentCollec
    local collection
    local new_collection
    local objName
    local new_objName
    local objPath_iRODS
    local new_objPath_iRODS
    local objPath_Phobos
    local new_objPath_Phobos
    local metadata
    local new_metadata
    local copyName

    fileName="./testFiles/file_${counter}.txt"
    parentCollec="what"
    collection="${parentCollec}/a/nice/collection"
    objName="file_${counter}"
    objPath_iRODS="${collection}/${objName}"
    objPath_Phobos="${archiveResc}/home/${userName}/${collection}/${objName}"

    imkdir -p "${collection}"
    iput -R "${compoundResc}" "${fileName}" "${objPath_iRODS}"
    rc=$?
    assertEquals "Function ${FUNCNAME[0]} ends with code ${rc} != 0" ${rc} 0

    metadata=$(sh ${umss} stat "${objPath_Phobos}")

    new_collection="${parentCollec}/another/good/collec"
    new_objName="file_renamed_${counter}"
    new_objPath_iRODS="${new_collection}/${new_objName}"
    new_objPath_Phobos="${archiveResc}/home/${userName}/"
    new_objPath_Phobos+="${new_collection}/${new_objName}"
    copyName="./thisIsTheCopy_${counter}"

    imkdir -p "${new_collection}"
    ####
    imv "${objPath_iRODS}" "${new_objPath_iRODS}"
    rc=$?
    ####

    assertEquals "Function ${FUNCNAME[0]} ends with code ${rc} != 0" ${rc} 0
    new_metadata=$(sh ${umss} stat "${new_objPath_Phobos}")
    ils "${objPath_iRODS}"
    rc=$?
    assertEquals "Data object ${objPath_iRODS} not deleted" "$rc" "4"
    assertEquals "Data object ${new_objPath_iRODS} not found in iRODS"\
    "$(ils ${new_objPath_iRODS})"\
    "  /${zoneName}/home/${userName}/${new_objPath_iRODS}"
    assertEquals "Object ${objPath_Phobos} found in Phobos."\
    "$(phobos object list ${objPath_Phobos})" ""
    assertEquals "Object ${new_objPath_Phobos} not found in Phobos"\
    "$(phobos object list ${new_objPath_Phobos})" "${new_objPath_Phobos}"
    assertEquals "Metadata have been modified."\
    "${metadata}" "${new_metadata}"

    iget "${new_objPath_iRODS}" "${copyName}"
    assertEquals "${fileName} data has been corrupted"\
    "$(cat ${fileName})" "$(cat ${copyName})"

    # Ending function
    irm -fr "${parentCollec}"
    rm -f "${copyName}"
}

# Load and run shunit2. Shellcheck does not support the "expect" language.
# shellcheck disable=SC1090
. "${shunit2}"
