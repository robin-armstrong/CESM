#!/bin/bash

# ======================= SCRIPT PARAMETERS =======================

# important filesystem paths
MOM6_BIN=../../../build/intel/MOM6/MOM6                                     # the MOM6 binary
DART_MODEL_DIR=../../../../../../../../DART/models/MARBL_MOM6_1D            # location of DART model information
INPUT_RES_DIR=$(pwd)/RESTART/DART_filter_input                              # location of input restart files for DART
OUTPUT_RES_DIR=$(pwd)/RESTART/DART_filter_output                            # location of output restart files for DART
BASE_RES_FILE=$(pwd)/RESTART/DART_baseline_restart/MOM.res.nc               # baseline restart file to initialize ensemble

# DA config options
ENS_SIZE=20

# ======================= MAIN PROGRAM =======================

echo "deleting any old restart files..."

if [ ! -z "$(ls -A ${INPUT_RES_DIR})" ]; then rm ${INPUT_RES_DIR}/*; fi
if [ ! -z "$(ls -A ${OUTPUT_RES_DIR})" ]; then rm ${OUTPUT_RES_DIR}/*; fi

echo "resetting the initial restart file..."

cp ${BASE_RES_FILE} ${INPUT_RES_DIR}/input_0001.nc

echo "resetting the input and output file lists..."

truncate -s 0 ${DART_MODEL_DIR}/work/filter_input_list.txt
truncate -s 0 ${DART_MODEL_DIR}/work/filter_output_list.txt

for i in $(seq ${ENS_SIZE}); do
    echo "${INPUT_RES_DIR}/input_$(printf "%04d" $i).nc" >> ${DART_MODEL_DIR}/work/filter_input_list.txt
    echo "${OUTPUT_RES_DIR}/output_$(printf "%04d" $i).nc" >> ${DART_MODEL_DIR}/work/filter_output_list.txt
done

echo "determining the initial model time..."

timestr=$(ncdump ${BASE_RES_FILE} | grep "Time = [1234567890]* ;")
timestr_length=${#timestr}
let timestr_lastindex=${timestr_length}-2
let timestamp_length=${timestr_lastindex}-8
init_day_mom6=${timestr:8:${timestamp_length}}

echo "determined the initial model time to be "$(printf %06d ${init_day_mom6})" (MOM6 calendar)..."

let init_day_dart=${init_day_mom6}+139157

echo "                                        "${init_day_dart}" (DART calendar)..."
