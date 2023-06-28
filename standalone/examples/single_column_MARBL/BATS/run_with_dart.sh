#!/bin/bash

# ======================= SCRIPT PARAMETERS =======================

# important filesystem paths
MOM6_BIN=../../../build/intel/MOM6/MOM6                            # the MOM6 binary
MOM6_WORK_DIR=./                                                   # working directory for MOM6
DART_MODEL_DIR=../../../../../../../../DART/models/MARBL_MOM6_1D   # location of DART model information
INPUT_RES_DIR=$(pwd)/RESTART/DART_filter_input                     # location of input restart files for DART
OUTPUT_RES_DIR=$(pwd)/RESTART/DART_filter_output                   # location of output restart files for DART
BASE_RES_FILE=$(pwd)/RESTART/DART_baseline_restart/MOM.res.nc      # baseline restart file to initialize ensemble
RES_NAME=MOM.res.nc                                                # generic restart file name
OBSSEQ_DIR=~/work/BATS_obsseq                                      # location of obs-sequence files

# DA config options
ENS_SIZE=20

# ======================= MAIN PROGRAM =======================

echo "================================================================"
echo "============================ SCRIPT ============================"
echo "================================================================"

echo "deleting any old restart files..."

rm -rf ${INPUT_RES_DIR}/*
rm -rf ${OUTPUT_RES_DIR}/*

echo "resetting the input and output file lists..."

truncate -s 0 ${DART_MODEL_DIR}/work/filter_input_list.txt
truncate -s 0 ${DART_MODEL_DIR}/work/filter_output_list.txt

for i in $(seq ${ENS_SIZE}); do
    input_subdir=${INPUT_RES_DIR}/input_$(printf "%04d" $i)
    output_subdir=${OUTPUT_RES_DIR}/output_$(printf "%04d" $i)

    mkdir ${input_subdir}
    mkdir ${output_subdir}

    echo "${input_subdir}/${RES_NAME}" >> ${DART_MODEL_DIR}/work/filter_input_list.txt
    echo "${output_subdir}/${RES_NAME}" >> ${DART_MODEL_DIR}/work/filter_output_list.txt
done

echo "resetting the initial restart file..."

cp ${BASE_RES_FILE} ${INPUT_RES_DIR}/input_0001/${RES_NAME}

echo "determining the initial model time..."

timestr=$(ncdump ${BASE_RES_FILE} | grep "Time = [0123456789]* ;")
timestr_length=${#timestr}
let timestr_lastindex=${timestr_length}-2
let timestamp_length=${timestr_lastindex}-8
currentday_mom6=${timestr:8:${timestamp_length}}
let currentday_dart=${currentday_mom6}+139157

echo "determined the initial model time to be $(printf %06d ${currentday_mom6}) (MOM6 calendar)"
echo "                                        ${currentday_dart} (DART calendar)"

echo "determining the day of the last available observation..."

last_obsseq_file=$(ls ${OBSSEQ_DIR}/out | tail -n 1)
last_obs_day=${last_obsseq_file:5:6}

echo "determined the day of the last available observation to be ${last_obs_day} (DART calendar)"

echo "setting perturb_from_single_instance = .true. ..."
sed -i "s/perturb_from_single_instance = .*/perturb_from_single_instance = .true./" ${DART_MODEL_DIR}/work/input.nml

echo "beginning the assimilation loop..."
first_assimilation_complete=false

while [ $currentday_dart -le $last_obs_day ]
do
    echo "searching for an obs-sequence file for day ${currentday_dart}..."

    if [ -f "${OBSSEQ_DIR}/out/BATS_${currentday_dart}.out" ]
    then
        echo "found file, assimilating with DART..."

        sed -i "s%obs_sequence_in_name.*%obs_sequence_in_name         ='\\${OBSSEQ_DIR}/out/BATS_${currentday_dart}.out',%" ${DART_MODEL_DIR}/work/input.nml
        sed -i "s%obs_sequence_out_name.*%obs_sequence_out_name        ='\\${OBSSEQ_DIR}/final/BATS_${currentday_dart}.final',%" ${DART_MODEL_DIR}/work/input.nml

        echo "================================================================"
        echo "============================= DART ============================="
        echo "================================================================"
        
        gdb ${DART_MODEL_DIR}/work/filter
        
        echo "================================================================"
        echo "============================ SCRIPT ============================"
        echo "================================================================"

        exit

        if ! ${first_assimilation_complete} 
        then
            first_assimilation_complete=true

            echo "first assimilation complete, setting perturb_from_single_instance = .false. ..."
            sed -i "s/perturb_from_single_instance = .*/perturb_from_single_instance = .false./" ${DART_MODEL_DIR}/work/input.nml
        fi
    else
        echo "no file found."
    fi

    if ! ${first_assimilation_complete}
    then
        echo "advancing the model state by 1 day..."

        let tomorrow_mom6=$currentday_mom6+1
        sed -i "s/DAYMAX = [0123456789]*/DAYMAX = ${tomorrow_mom6}/" ${MOM6_WORK_DIR}/MOM_input
        sed -i "s%restart_input_dir = .*%restart_input_dir = '${INPUT_RES_DIR}/input_0001',%" ${MOM6_WORK_DIR}/input.nml
        sed -i "s%restart_output_dir = .*%restart_output_dir = '${INPUT_RES_DIR}/input_0001',%" ${MOM6_WORK_DIR}/input.nml

        echo "================================================================"
        echo "============================= MOM6 ============================="
        echo "================================================================"
        
        ${MOM6_BIN}

        echo "================================================================"
        echo "============================ SCRIPT ============================"
        echo "================================================================"    
    fi

    let currentday_dart=$currentday_dart+1
    currentday_mom6=$tomorrow_mom6
done
