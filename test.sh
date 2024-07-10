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

# Here are the unit tests related to the Phobos UnivMSS plugin for iRODS.
#
# This file is to be run using the shUnit2 framework :
# "https://github.com/kward/shunit2"
# The absolute path to the shUnit2 executable file must be set a the very
# bottom of this file.

############################################################################
# PLEASE ENTER HERE THE ABSOLUTE PATH TO IRODS_INIT FILE;
irods_init="~root/shunit2-2.1.8/examples/irods_init.exp"
############################################################################

# Run once before all tests.
oneTimeSetUp() {
    # Name and path of the UMMS script to test
    umssAbsolutePath="/var/lib/irods/msiExecCmd_bin" #Default path
    umssName="phobos_mss_20240506.sh"
    umss="${umssAbsolutePath}/${umssName}"

    # Info about the iRODS zone
    zoneIP=127.0.0.1
    zonePort=1247
    zoneName="tempZone"

    # Info about the iRODS resources
    unixResc="demoResc"
    compoundResc="CompoundTest"
    cacheResc="PosixTest"
    archiveResc="PhobosTest"

    # Info about the iRODS users
    adminName=rods
    adminPswd=rods
    userName=alice
    userPswd=alice

    # Init the Phobos and iRODS environment.
    systemctl start phobosd
    ~castellanv/shunit2-2.1.8/examples/irods_init.exp "${zoneIP}"\
    "${zonePort}" "${adminName}" "${zoneName}" "${adminPswd}"\
    >> /dev/null 2>&1

    # Init some files and directories to play with.
    counter=0
    mkdir -p ./testFiles/dir_0/dir_0_0
    mkdir -p ./testFiles/dir_1
    n=20
    for ((k=0; k<n; k++)); do
        filename="./testFiles/file_${k}.txt"
        echo "This '${k}' is provided to you by file_${k}." > "$filename"
        filename="./testFiles/dir_0/file_0_${k}.txt"
        echo "This '${k}' is provided to you by file_${k}." > "$filename"
        filename="./testFiles/dir_0/dir_0_0/file_0_0_${k}.txt"
        echo "This '${k}' is provided to you by file_${k}." > "$filename"
        filename="./testFiles/dir_1/file_1_${k}.txt"
        echo "This '${k}' is provided to you by file_${k}." > "$filename"
    done
    return 0
}

# Run once after all tests.
oneTimeTearDown() {
    rm -fr ./testFiles
    #systemctl stop phobosd
    iexit full
    rm -f ~/.irods/irods_environment.json
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
    local rc
    local fileName
    local objectName
    local copyName

    fileName="./testFiles/file_${counter}.txt"
    objectName="file_${counter}"
    copyName="./thisIsTheCopy_${counter}"

    sh ${umss} syncToArch "${fileName}" "${objectName}"
    rc=$?

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
    local rc
    local fileName
    local objectName
    local copyName

    fileName="./testFiles/file_${counter}.txt"
    objectName="file_${counter}"
    copyName="./thisIsTheCopy_${counter}"

    phobos put "${fileName}" "${objectName}"
    sh ${umss} stageToCache "${objectName}" "${copyName}"
    rc=$?

    assertEquals "Function ${FUNCNAME[0]} ends with code ${rc} != 0" ${rc} 0
    assertEquals "Object ${fileName} read corrupted" "$(cat ${copyName})"\
    "$(cat ${fileName})"

    # Ending the test
    phobos delete "${objectName}"
    rm -f "${copyName}"
}

test_basic_mkdir() {
    # iRODS-Phobos mkdir performs nothing. We only need it to return "success"
    local rc

    sh ${umss} mkdir "/${zoneName}/home/${adminName}/testdir"
    rc=$?

    assertEquals "Function ${FUNCNAME[0]} ends with code ${rc} != 0" ${rc} 0
}

test_basic_chmod() {
    # iRODS-Phobos chmod performs nothing. We only need it to return "success"
    local rc

    sh ${umss} chmod "/${zoneName}/home/${adminName}" 750
    rc=$?

    assertEquals "Function ${FUNCNAME[0]} ends with code ${rc} != 0" ${rc} 0
}

test_basic_rm() {
    local rc
    local fileName
    local objectName

    fileName="./testFiles/file_${counter}.txt"
    objectName="file_${counter}"
    phobos put "${fileName}" "${objectName}"

    sh ${umss} rm "${objectName}"
    rc=$?

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
    # We want to move metadata with the object on Phobo, and recording MDs is
    # possible iff it was stored using the UMSS script. If syncToArch fails,
    # it is not relevant to test mv on corrupted data in a basic_ test.
    sh ${umss} syncToArch "${fileName}" "${objectName}"
    rc=$?
    assertEquals "syncToArch ends with code ${rc} != 0" ${rc} 0
    assertEquals "Object ${objectName} not sync with Phobos"\
    "$(phobos object list ${objectName})" "${objectName}"

    originObjMD=$(phobos object list "${objectName}" -t -o user_md -f human)

    sh ${umss} mv "${objectName}" "${newObjectName}"
    rc=$?

    assertEquals "Function ${FUNCNAME[0]} ends with code ${rc} != 0" ${rc} 0
    assertEquals "Object ${objectName} still alive in Phobos."\
    "$(phobos object list ${objectName})" ""
    assertEquals "Object ${newObjectName} not found in Phobos"\
    "$(phobos object list ${newObjectName})" "${newObjectName}"

    newObjMD=$(phobos object list "${newObjectName}" -t -o user_md -f human)
    assertEquals "Object metadata not preserved" "${originObjMD}"\
    "${newObjMD}"

    phobos get "${newObjectName}" "${copyName}"
    assertEquals "Object ${fileName} copy corrupted" "$(cat ${copyName})"\
    "$(cat ${fileName})"

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

    metadata=$(sh ${umss} stat "${objectName}")
    rc=$?

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
    # When trying to put an inexistant file, synctoArch must return an error,
    # without creating any object in Phobos.
    local rc
    local fileName
    local objectName

    fileName="./This_is_inexistant_file_number_${counter}.idkm"
    objectName="file_${counter}"
    sh ${umss} syncToArch "${fileName}" "${objectName}"
    rc=$?

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

    # First put of a file.
    sh ${umss} syncToArch "${firstFileName}" "${objectName}"
    rc=$?

    assertEquals "Function ${FUNCNAME[0]}_1 ends with code ${rc} != 0" ${rc} 0
    assertEquals "Object ${objectName} not found in Phobos"\
    "$(phobos object list ${objectName})" "${objectName}"
    v1=$(phobos object list ${objectName} -o version)
    md1=$(sh ${umss} stat "${objectName}")

    sh ${umss} syncToArch "${secondFileName}" "${objectName}"
    rc=$?

    assertEquals "Function ${FUNCNAME[0]}_2 ends with code ${rc} != 0" ${rc} 0
    v2=$(phobos object list ${objectName} -o version)
    md2=$(sh ${umss} stat "${objectName}")
    assertTrue "Version changed from ${v1} to ${v2}" "[ $v2 -eq $((v1 + 1)) ]"
    # We know that, field "inode" is unique among files of the local
    # filesystem. So metadata must be changed from one version to the other.
    assertNotEquals "Metadata not updated" "${md1}" "${md2}"

    phobos get ${objectName} ${copyName}
    assertEquals "Object ${firstFileName} copy corrupted" "$(cat ${copyName})"\
    "$(cat ${secondFileName})"

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

    objectName="This_is_inexistant_object_number_${counter}"
    copyName="./thisIsTheCopy_${counter}"

    sh ${umss} stageToCache "${objectName}" "${copyName}"
    rc=$?

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
    echo ${oneString} > "${copyName}"

    phobos put "${fileName}" "${objectName}"
    sh ${umss} stageToCache "${objectName}" "${copyName}"
    rc=$?

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
}

# Load and run shUnit2
. ~root/shunit2-2.1.8/shunit2
