#!/bin/bash

# ======================= SCRIPT PARAMETERS =======================

# important filesystem paths
MOM6_BIN=../../../build/intel/MOM6/MOM6                                     # the MOM6 binary
DART_MODEL_DIR=../../../../../../../../DART/models/MARBL_MOM6_1D            # location of DART model information
DART_OBS_DIR=../../../../../../../../DART/observations/obs_converters/BATS  # location of DART obs-seq generating files
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

echo "generating the observation sequence file..."

back=$(pwd)
cd ${DART_OBS_DIR}/work
./text_to_obs
cd ${back}
