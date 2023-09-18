#!/bin/bash

# ======================= SCRIPT PARAMETERS =======================

# if 'true', then the script will erase old DART outputs and start clean
START_CLEAN=true

# MOM6 binary, keep this path absolute
MOM6_BIN=~/work/cesm/cesm2_3_alpha12b+mom6_marbl/components/mom/standalone/build/intel-cheyenne/MOM6/MOM6

# important filesystem paths, keep these absolute
MOM6_BATS_DIR=$(pwd)                        # working directory for MOM6
OBSSEQ_DIR=~/work/BATS_obsseq               # location of obs-sequence files

# ensemble size
ENS_SIZE=80

# other
LASTDAY_DART=147977     # last day of simulation (DART calendar)
MOM6_TO_DART=139157     # offset between MOM6 and DART calendars
MOM6_TIMESTEP=3600.0    # timestep (seconds) to use when advancing ensemble members

# ======================= MAIN PROGRAM =======================

module load nco

echo ""
echo "================================================================"
echo "============================ DRIVER ============================"
echo "================================================================"
echo ""

if ${START_CLEAN}; then
    echo "backing up the initial ensemble..."

    rm -rf ${MOM6_BATS_DIR}/ensemble_backup
    cp -r ${MOM6_BATS_DIR}/ensemble ensemble_backup

    echo "deleting old DART output files..."

    rm -rf ${MOM6_BATS_DIR}/output/*
    mkdir ${MOM6_BATS_DIR}/output/member_0001_archive
    rm -f ${MOM6_BATS_DIR}/DART/template_priorinf*
    rm -f ${MOM6_BATS_DIR}/DART/input_priorinf*
    rm -f ${MOM6_BATS_DIR}/DART/output_priorinf*

    echo "configuring the DART namelist file..."

    sed -i "32 s%input_state_files = .*%input_state_files = '',%" ${MOM6_BATS_DIR}/DART/input.nml
    sed -i "33 s%input_state_file_list = .*%input_state_file_list = '${MOM6_BATS_DIR}/DART/ensemble_states.txt', ${MOM6_BATS_DIR}/DART/ensemble_params.txt',%" ${MOM6_BATS_DIR}/DART/input.nml
    sed -i "38 s%output_state_files = .*%output_state_files = '',%" ${MOM6_BATS_DIR}/DART/input.nml
    sed -i "39 s%output_state_file_list = .*%output_state_file_list = '${MOM6_BATS_DIR}/DART/ensemble_states.txt', ${MOM6_BATS_DIR}/DART/ensemble_params.txt',%" ${MOM6_BATS_DIR}/DART/input.nml
    sed -i "42 s/num_output_state_members = .*/num_output_state_members = ${ENS_SIZE},/" ${MOM6_BATS_DIR}/DART/input.nml
    sed -i "47 s/ens_size = .*/ens_size = ${ENS_SIZE},/" ${MOM6_BATS_DIR}/DART/input.nml
    sed -i "49 s/perturb_from_single_instance = .*/perturb_from_single_instance = .false.,/" ${MOM6_BATS_DIR}/DART/input.nml
    sed -i "58 s/num_output_obs_members = .*/num_output_obs_members = ${ENS_SIZE},/" ${MOM6_BATS_DIR}/DART/input.nml
    sed -i "142 s%state_template_file = .*%state_template_file = '${MOM6_BATS_DIR}/ensemble/member_0001/RESTART/MOM.res.nc',%" ${MOM6_BATS_DIR}/DART/input.nml

    echo "generating inflation restart files..."

    back=$(pwd)
    cd ${MOM6_BATS_DIR}/DART

    echo ""
    echo "================================================================"
    echo "==================== FILL INFLATION RESTART ===================="
    echo "================================================================"
    echo ""

    ./fill_inflation_restart

    echo ""
    echo "================================================================"
    echo "============================ DRIVER ============================"
    echo "================================================================"
    echo ""

    cp input_priorinf_mean_d01.nc template_priorinf_mean_d01.nc
    cp input_priorinf_sd_d01.nc template_priorinf_sd_d01.nc

    cd ${back}
fi

echo "setting MOM6 timestep to ${MOM6_TIMESTEP} seconds for each ensemble member..."

for i in $(seq ${ENS_SIZE}); do
    sed -i "34 s/DT = .*/DT = ${MOM6_TIMESTEP}/" ${MOM6_BATS_DIR}/ensemble/member_$(printf "%04d" ${i})/MOM_input
done

echo "determining the initial model time..."

timestr=$(ncdump ${MOM6_BATS_DIR}/ensemble/member_0001/RESTART/MOM.res.nc | grep "Time = [0123456789]* ;")
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

echo "beginning the assimilation loop..."

exit

while [ $currentday_dart -lt $LASTDAY_DART ]
do
    echo "archiving the state of member 1..."
    cp ${MOM6_BATS_DIR}/ensemble/member_0001/RESTART/MOM.res.nc ${MOM6_BATS_DIR}/output/member_0001_archive/${currentday_dart}.res.nc

    echo "searching for an obs-sequence file for day ${currentday_mom6} (MOM6 calendar)..."
    echo "                                           ${currentday_dart} (DART calendar)..."

    if [ -f ${OBSSEQ_DIR}/BATS_${currentday_dart}.out ]
    then
        echo "found file, assimilating with DART..."

        outputdir=${MOM6_BATS_DIR}/output/${currentday_dart}
        mkdir ${outputdir}

        sed -i "56 s%obs_sequence_in_name.*%obs_sequence_in_name ='\\${OBSSEQ_DIR}/BATS_${currentday_dart}.out',%" ${MOM6_BATS_DIR}/DART/input.nml
        sed -i "57 s%obs_sequence_out_name.*%obs_sequence_out_name ='\\${outputdir}/obs_seq.final',%" ${MOM6_BATS_DIR}/DART/input.nml

        back=$(pwd)
        cd ${MOM6_BATS_DIR}/DART

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

        ncks -A -v h template_priorinf_mean_d01.nc output_priorinf_mean_d01.nc
        ncks -A -v h template_priorinf_sd_d01.nc output_priorinf_sd_d01.nc

        cd ${back}

        mv ${MOM6_BATS_DIR}/DART/dart_log.out ${outputdir}
        mv ${MOM6_BATS_DIR}/DART/output_mean.nc ${outputdir}
        mv ${MOM6_BATS_DIR}/DART/output_sd.nc ${outputdir}
        mv ${MOM6_BATS_DIR}/DART/preassim* ${outputdir}
        mv ${MOM6_BATS_DIR}/DART/analysis* ${outputdir}
        mv ${MOM6_BATS_DIR}/DART/input_priorinf* ${outputdir}
        mv ${MOM6_BATS_DIR}/DART/output_priorinf* ${outputdir}
        
        cp ${outputdir}/output_priorinf_mean_d01.nc ${MOM6_BATS_DIR}/DART/input_priorinf_mean_d01.nc
        cp ${outputdir}/output_priorinf_sd_d01.nc ${MOM6_BATS_DIR}/DART/input_priorinf_sd_d01.nc

        cp ${outputdir}/output_priorinf_mean_d02.nc ${MOM6_BATS_DIR}/DART/input_priorinf_mean_d02.nc
        cp ${outputdir}/output_priorinf_sd_d02.nc ${MOM6_BATS_DIR}/DART/input_priorinf_sd_d02.nc
    else
        echo "no file found."
    fi

    let tomorrow_mom6=${currentday_mom6}+1
    let tomorrow_dart=${currentday_dart}+1

    echo "advancing the ensemble to day ${tomorrow_mom6} (MOM6 calendar)..."
    echo "                              ${tomorrow_dart} (DART calendar)..."
    echo ""

    for i in $(seq ${ENS_SIZE}); do
        sed -i "371 s/DAYMAX = .*/DAYMAX = ${tomorrow_mom6}/" ${MOM6_BATS_DIR}/ensemble/member_$(printf "%04d" ${i})/MOM_input
    done

    init_seconds=${SECONDS}

    for i in $(seq ${ENS_SIZE}); do
        echo "advancing ensemble member ${i}..."
        cd ${MOM6_BATS_DIR}/ensemble/member_$(printf "%04d" ${i})
        rm -f logfile.txt
        ${MOM6_BIN} >> logfile.txt &
    done

    wait

    echo ""
    echo "finished advancing the ensemble."
    
    current_seconds=${SECONDS}
    let diff=${current_seconds}-${init_seconds}

    echo "integration wall-time: ${diff} seconds."

    currentday_mom6=${tomorrow_mom6}
    currentday_dart=${tomorrow_dart}
done

echo "assimilation loop complete."
echo "exiting..."
echo ""
