#!/bin/bash

# ======================= SCRIPT PARAMETERS =======================

# MOM6 binary, keep this path absolute
MOM6_BIN=~/work/cesm/cesm2_3_alpha12b+mom6_marbl/components/mom/standalone/build/intel/MOM6/MOM6

# important filesystem paths, keep these absolute
MOM6_BATS_DIR=$(pwd)                         # working directory for MOM6
DART_MODEL_DIR=~/work/DART/models/MARBL_MOM6_1D     # location of DART model information
OBSSEQ_DIR=~/work/BATS_obsseq                       # location of obs-sequence files

# ensemble size (this should match the value in ${DART_MODEL_DIR}/work/input.nml)
ENS_SIZE=30

# other
LASTDAY_DART=142907     # last day of simulation (DART calendar)
MOM6_TO_DART=139157     # offset between MOM6 and DART calendars
MOM6_TIMESTEP=100.0     # timestep (seconds) to use when advancing ensemble members

# ======================= MAIN PROGRAM =======================

echo ""
echo "================================================================"
echo "============================ DRIVER ============================"
echo "================================================================"
echo ""

echo "deleting old ensemble data files..."

rm -rf ${MOM6_BATS_DIR}/ensemble/member_*

echo "deleting old analysis obs-sequence files..."

rm -f ${OBSSEQ_DIR}/final/*

echo "resetting the restart file list..."

truncate -s 0 ${DART_MODEL_DIR}/work/ensemble_members.txt

for i in $(seq ${ENS_SIZE}); do
    ensemble_subdir=${MOM6_BATS_DIR}/ensemble/member_$(printf "%04d" ${i})
    mkdir ${ensemble_subdir}
    echo "${ensemble_subdir}/RESTART/MOM.res.nc" >> ${DART_MODEL_DIR}/work/ensemble_members.txt
done

echo "initializing the ensemble members..."

for i in $(seq ${ENS_SIZE}); do
    ensemble_subdir=${MOM6_BATS_DIR}/ensemble/member_$(printf "%04d" ${i})
    baseline_subdir=${MOM6_BATS_DIR}/ensemble/baseline

    cp -r ${baseline_subdir}/RESTART ${ensemble_subdir}/RESTART
    cp -r ${baseline_subdir}/INPUT ${ensemble_subdir}/INPUT
    cp ${baseline_subdir}/MOM_input ${ensemble_subdir}/MOM_input
    cp -r ${baseline_subdir}/MOM_override ${ensemble_subdir}/MOM_override
    cp ${baseline_subdir}/MOM_override2 ${ensemble_subdir}/MOM_override2
    cp ${baseline_subdir}/data_table ${ensemble_subdir}/data_table
    cp ${baseline_subdir}/diag_table ${ensemble_subdir}/diag_table
    cp ${baseline_subdir}/input.nml ${ensemble_subdir}/input.nml

    sed -i "s/input_filename = .*/input_filename = 'r',/" ${ensemble_subdir}/input.nml
    sed -i "s%restart_input_dir = .*%restart_input_dir = 'RESTART/',%" ${ensemble_subdir}/input.nml
done

echo "determining the initial model time..."

timestr=$(ncdump ${MOM6_BATS_DIR}/ensemble/baseline/RESTART/MOM.res.nc | grep "Time = [0123456789]* ;")
timestr_length=${#timestr}
let timestr_lastindex=${timestr_length}-2
let timestamp_length=${timestr_lastindex}-8
currentday_mom6=${timestr:8:${timestamp_length}}
let currentday_dart=${currentday_mom6}+${MOM6_TO_DART}

echo "determined the initial model time to be ${currentday_mom6} (MOM6 calendar),"
echo "                                        ${currentday_dart} (DART calendar)."

echo "preparing temp directory..."
export TMPDIR=/glade/scratch/${USER}/marbl_mom6_dart_temp
mkdir -p ${TMPDIR}

echo "setting perturb_from_single_instance = .true. in DART..."
sed -i "s/perturb_from_single_instance = .*/perturb_from_single_instance = .true./" ${DART_MODEL_DIR}/work/input.nml

echo "beginning the assimilation loop..."

first_assimilation_complete=false

while [ $currentday_dart -lt $LASTDAY_DART ]
do
    echo "searching for an obs-sequence file for day ${currentday_mom6} (MOM6 calendar)..."
    echo "                                           ${currentday_dart} (DART calendar)..."

    if [ -f ${OBSSEQ_DIR}/out/BATS_${currentday_dart}.out ]
    then
        echo "found file, assimilating with DART..."

        sed -i "s%obs_sequence_in_name.*%obs_sequence_in_name         ='\\${OBSSEQ_DIR}/out/BATS_${currentday_dart}.out',%" ${DART_MODEL_DIR}/work/input.nml
        sed -i "s%obs_sequence_out_name.*%obs_sequence_out_name        ='\\${OBSSEQ_DIR}/final/BATS_${currentday_dart}.final',%" ${DART_MODEL_DIR}/work/input.nml

        back=$(pwd)
        cd ${DART_MODEL_DIR}/work

        echo ""
        echo "================================================================"
        echo "============================= DART ============================="
        echo "================================================================"
        echo ""

        ./filter

        echo ""
        echo "================================================================"
        echo "============================ DRIVER ============================"
        echo "================================================================"
        echo ""

        cd ${back}

        if ! ${first_assimilation_complete} 
        then
            first_assimilation_complete=true
            echo "setting MOM6 timestep to ${MOM6_TIMESTEP} seconds for each ensemble member..."

            for i in $(seq ${ENS_SIZE}); do
                sed -i "s/DT = .*/DT = ${MOM6_TIMESTEP}/" ${MOM6_BATS_DIR}/ensemble/member_$(printf "%04d" ${i})/MOM_input
            done
        fi
    else
        echo "no file found."
    fi

    let tomorrow_mom6=${currentday_mom6}+1
    let tomorrow_dart=${currentday_dart}+1

    echo "advancing the ensemble to day ${tomorrow_mom6} (MOM6 calendar)..."
    echo "                              ${tomorrow_dart} (DART calendar)..."
    echo ""

    for i in $(seq ${ENS_SIZE}); do
        sed -i "s/DAYMAX = .*/DAYMAX = ${tomorrow_mom6}/" ${MOM6_BATS_DIR}/ensemble/member_$(printf "%04d" ${i})/MOM_input
    done

    for i in $(seq ${ENS_SIZE}); do
        echo "advancing ensemble member ${i}..."
        cd ${MOM6_BATS_DIR}/ensemble/member_$(printf "%04d" ${i})
        rm -f logfile.txt
        ${MOM6_BIN} >> logfile.txt &
    done

    wait

    echo ""
    echo "finished advancing the ensemble."

    currentday_mom6=${tomorrow_mom6}
    currentday_dart=${tomorrow_dart}
done

echo "assimilation loop complete."
echo "exiting..."
echo ""
