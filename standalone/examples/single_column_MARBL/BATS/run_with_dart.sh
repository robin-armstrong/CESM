#!/bin/bash

# ======================= SCRIPT PARAMETERS =======================

# important filesystem paths
MOM6_BIN=../../../build/intel/MOM6/MOM6                            # the MOM6 binary
MOM6_WORK_DIR=./                                                   # working directory for MOM6
DART_MODEL_DIR=../../../../../../../../DART/models/MARBL_MOM6_1D   # location of DART model information
ENSEMBLE_DIR=$(pwd)/RESTART/DART_ensemble                          # directory containing restart files
BASE_RES_FILE=$(pwd)/RESTART/DART_baseline_restart/MOM.res.nc      # baseline restart file to initialize ensemble
OBSSEQ_DIR=~/work/BATS_obsseq                                      # location of obs-sequence files

# DA config options
ENS_SIZE=15

# other
MOM_RES_NAME=MOM.res.nc         # generic restart file name
SOLO_RES_NAME=ocean_solo.res    # seems like there are important files with this name?
MOM6_TO_DART=139157             # offset between MOM6 and DART calendars

# ======================= MAIN PROGRAM =======================

echo ""
echo "================================================================"
echo "============================ SCRIPT ============================"
echo "================================================================"
echo ""

echo "old restart files and analysis obs-sequence files will be deleted."
read -p "continue? [y/n] " userchoice

if [ "${userchoice}" != "y" ] && [ "${userchoice}" != "Y" ]
then
    echo ""
    echo "exiting..."
    echo ""
    exit
fi

echo "deleting old restart files..."

rm -rf ${ENSEMBLE_DIR}/*

echo "deleting old analysis obs-sequence files..."

rm -f ${OBSSEQ_DIR}/final/*

echo "resetting the restart file list..."

truncate -s 0 ${DART_MODEL_DIR}/work/ensemble_members.txt

for i in $(seq ${ENS_SIZE}); do
    ensemble_subdir=${ENSEMBLE_DIR}/member_$(printf "%04d" ${i})
    mkdir ${ensemble_subdir}
    echo "${ensemble_subdir}/${MOM_RES_NAME}" >> ${DART_MODEL_DIR}/work/ensemble_members.txt
done

echo "resetting the initial restart file..."

cp ${BASE_RES_FILE} ${ENSEMBLE_DIR}/member_0001/${MOM_RES_NAME}

echo "determining the initial model time..."

timestr=$(ncdump ${BASE_RES_FILE} | grep "Time = [0123456789]* ;")
timestr_length=${#timestr}
let timestr_lastindex=${timestr_length}-2
let timestamp_length=${timestr_lastindex}-8
currentday_mom6=${timestr:8:${timestamp_length}}
let currentday_dart=${currentday_mom6}+${MOM6_TO_DART}

echo "determined the initial model time to be ${currentday_mom6} (MOM6 calendar),"
echo "                                        ${currentday_dart} (DART calendar)."

echo "determining the day of the last available observation..."

last_obsseq_file=$(ls ${OBSSEQ_DIR}/out | tail -n 1)
lastday_dart=${last_obsseq_file:5:6}
let lastday_mom6=${lastday_dart}-${MOM6_TO_DART}

echo "determined the day of the last available observation to be ${lastday_mom6} (MOM6 calendar),"
echo "                                                           ${lastday_dart} (DART calendar)."

read -p "simulate until day of last observation? [y/n] " userchoice

if [ "${userchoice}" != "y" ] && [ "${userchoice}" != "Y" ]
then
    read -p "enter last day of simulation (DART calendar): " lastday_dart
    let lastday_mom6=${lastday_dart}-${MOM6_TO_DART}
fi

echo "will simulate until day ${lastday_dart} (DART calendar),"
echo "                        ${lastday_mom6} (MOM6 calendar)."

exit

echo "setting perturb_from_single_instance = .true. ..."
sed -i "s/perturb_from_single_instance = .*/perturb_from_single_instance = .true./" ${DART_MODEL_DIR}/work/input.nml

echo "beginning the assimilation loop..."
first_assimilation_complete=false

while [ $currentday_dart -lt $lastday_dart ]
do
    echo "searching for an obs-sequence file for day ${currentday_mom6} (MOM6 calendar)..."
    echo "                                           ${currentday_dart} (DART calendar)..."

    if [ -f "${OBSSEQ_DIR}/out/BATS_${currentday_dart}.out" ]
    then
        if ! ${first_assimilation_complete}
        then
            echo "found file."
            echo "preparing restart files for ensemble members 2 through ${ENS_SIZE}..."

            for i in $(seq ${ENS_SIZE}); do
                if [ 2 -le ${i} ]
                then
                    cp ${ENSEMBLE_DIR}/member_0001/${MOM_RES_NAME} ${ENSEMBLE_DIR}/member_$(printf "%04d" ${i})/${MOM_RES_NAME}
                    cp ${ENSEMBLE_DIR}/member_0001/${SOLO_RES_NAME} ${ENSEMBLE_DIR}/member_$(printf "%04d" ${i})/${SOLO_RES_NAME}
                fi
            done

            echo "assimilating obs-sequence file with DART..."
        else
            echo "found file, a/ssimilating with DART..."
        fi

        sed -i "s%obs_sequence_in_name.*%obs_sequence_in_name         ='\\${OBSSEQ_DIR}/out/BATS_${currentday_dart}.out',%" ${DART_MODEL_DIR}/work/input.nml
        sed -i "s%obs_sequence_out_name.*%obs_sequence_out_name        ='\\${OBSSEQ_DIR}/final/BATS_${currentday_dart}.final',%" ${DART_MODEL_DIR}/work/input.nml
        
        back=$(pwd)
        cd ${DART_MODEL_DIR}/work

        echo ""
        echo "================================================================"
        echo "============================= DART ============================="
        echo "================================================================"
        echo ""

        ./filter | tee ${back}/program_output.txt
        
        echo ""
        echo "================================================================"
        echo "============================ SCRIPT ============================"
        echo "================================================================"
        echo ""

        cd ${back}

        grep -q "FATAL" program_output.txt
        status=${?}
        rm program_output.txt

        if [ ${status} -eq 0 ]
        then
            echo "fatal error detected from DART."
            echo "exiting..."
            echo ""
            exit
        fi

        if ! ${first_assimilation_complete} 
        then
            first_assimilation_complete=true

            echo "first assimilation complete."
            echo "setting perturb_from_single_instance = .false. ..."
            sed -i "s/perturb_from_single_instance = .*/perturb_from_single_instance = .false./" ${DART_MODEL_DIR}/work/input.nml
        else
            echo "assimilation complete."
        fi
    else
        echo "no file found."
    fi

    let tomorrow_mom6=${currentday_mom6}+1
    let tomorrow_dart=${currentday_dart}+1

    if ! ${first_assimilation_complete}
    then
        echo "advancing the model to day ${tomorrow_mom6} (MOM6 calendar)..."
        echo "                           ${tomorrow_dart} (DART calendar)..."

        sed -i "s/DAYMAX = [0123456789]*/DAYMAX = ${tomorrow_mom6}/" ${MOM6_WORK_DIR}/MOM_input
        sed -i "s%restart_input_dir = .*%restart_input_dir = '${ENSEMBLE_DIR}/member_0001',%" ${MOM6_WORK_DIR}/input.nml
        sed -i "s%restart_output_dir = .*%restart_output_dir = '${ENSEMBLE_DIR}/member_0001',%" ${MOM6_WORK_DIR}/input.nml
        back=$(pwd)
        cd ${MOM6_WORK_DIR}

        echo ""
        echo "================================================================"
        echo "========================= MOM6 + MARBL ========================="
        echo "================================================================"
        echo ""

        ${MOM6_BIN} | tee ${back}/program_output.txt

        echo ""
        echo "================================================================"
        echo "============================ SCRIPT ============================"
        echo "================================================================"
        echo ""

        cd ${back}

        grep -q "FATAL" program_output.txt
        status=${?}
        rm program_output.txt

        if [ ${status} -eq 0 ]
        then
            echo "fatal error detected from MOM6 + MARBL."
            echo "exiting..."
            echo ""
            exit
        fi

        echo "finished advancing model."
    else
        echo "advancing the ensemble to day ${tomorrow_mom6} (MOM6 calendar)..."
        echo "                              ${tomorrow_dart} (DART calendar)..."

        sed -i "s/DAYMAX = [0123456789]*/DAYMAX = ${tomorrow_mom6}/" ${MOM6_WORK_DIR}/MOM_input
        
        for i in $(seq ${ENS_SIZE}); do
            sed -i "s%restart_input_dir = .*%restart_input_dir = '${ENSEMBLE_DIR}/member_$(printf "%04d" $i)',%" ${MOM6_WORK_DIR}/input.nml
            sed -i "s%restart_output_dir = .*%restart_output_dir = '${ENSEMBLE_DIR}/member_$(printf "%04d" $i)',%" ${MOM6_WORK_DIR}/input.nml
            
            echo "advancing ensemble member ${i}..."
            back=$(pwd)
            cd ${MOM6_WORK_DIR}

            echo ""
            echo "================================================================"
            echo "========================= MOM6 + MARBL ========================="
            echo "================================================================"
            echo ""
            
            ${MOM6_BIN} | tee ${back}/program_output.txt

            echo ""
            echo "================================================================"
            echo "============================ SCRIPT ============================"
            echo "================================================================"
            echo ""

            cd ${back}

            grep -q "FATAL" program_output.txt
            status=${?}
            rm program_output.txt

            if [ ${status} -eq 0 ]
            then
                echo "fatal error detected from MOM6 + MARBL."
                echo "exiting..."
                echo ""
                exit
            fi

            echo "finished advancing emsemble member ${i}."
        done

        echo "finished advancing the ensemble."
    fi

    currentday_mom6=${tomorrow_mom6}
    currentday_dart=${tomorrow_dart}
done

echo "assimilation loop complete."
echo "exiting..."
echo ""