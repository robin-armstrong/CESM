#!/bin/bash

# ======================= SCRIPT PARAMETERS =======================

# MOM6 binary, keep this path absolute
MOM6_BIN=~/work/cesm/cesm2_3_alpha12b+mom6_marbl/components/mom/standalone/build/intel-cheyenne/MOM6/MOM6

# important filesystem paths, keep these absolute
MOM6_BATS_DIR=$(pwd)                        # working directory for MOM6
OBSSEQ_DIR=~/work/BATS_obsseq               # location of obs-sequence files

# ensemble size
ENS_SIZE=80

# other
LASTDAY_DART=147800     # last day of simulation (DART calendar)
MOM6_TO_DART=139157     # offset between MOM6 and DART calendars
MOM6_LARGESTEP=3600.0   # larger timestep (seconds) to use when advancing ensemble members
MOM6_SMALLSTEP=200.0    # smaller timestep (seconds) to use when advancing ensemble members

# ======================= MAIN PROGRAM =======================

init_seconds=${SECONDS}

echo ""
echo "================================================================"
echo "============================ DRIVER ============================"
echo "================================================================"
echo ""

echo "deleting old ensemble data files..."

rm -rf ${MOM6_BATS_DIR}/ensemble/member_*

echo "deleting old DART output files..."

rm -rf ${MOM6_BATS_DIR}/output/*

echo "resetting the restart file list..."

touch ${MOM6_BATS_DIR}/DART/ensemble_members.txt
truncate -s 0 ${MOM6_BATS_DIR}/DART/ensemble_members.txt

for i in $(seq ${ENS_SIZE}); do
    ensemble_subdir=${MOM6_BATS_DIR}/ensemble/member_$(printf "%04d" ${i})
    mkdir ${ensemble_subdir}
    echo "${ensemble_subdir}/RESTART/MOM.res.nc" >> ${MOM6_BATS_DIR}/DART/ensemble_members.txt
done

echo "configuring the DART namelist file..."

sed -i "s%template_file = .*%template_file = '${MOM6_BATS_DIR}/ensemble/member_0001/RESTART/MOM.res.nc',%" ${MOM6_BATS_DIR}/DART/input.nml
sed -i "s%input_state_files = .*%input_state_files = '',%" ${MOM6_BATS_DIR}/DART/input.nml
sed -i "s%input_state_file_list = .*%input_state_file_list = '${MOM6_BATS_DIR}/DART/ensemble_members.txt',%" ${MOM6_BATS_DIR}/DART/input.nml
sed -i "s%output_state_files = .*%output_state_files = '',%" ${MOM6_BATS_DIR}/DART/input.nml
sed -i "s%output_state_file_list = .*%output_state_file_list = '${MOM6_BATS_DIR}/DART/ensemble_members.txt',%" ${MOM6_BATS_DIR}/DART/input.nml
sed -i "s/ens_size = .*/ens_size = ${ENS_SIZE},/" ${MOM6_BATS_DIR}/DART/input.nml
sed -i "s/num_output_state_members = .*/num_output_state_members = ${ENS_SIZE},/" ${MOM6_BATS_DIR}/DART/input.nml
sed -i "s/num_output_obs_members = .*/num_output_obs_members = ${ENS_SIZE},/" ${MOM6_BATS_DIR}/DART/input.nml
sed -i "s/num_output_obs_members = .*/num_output_obs_members = ${ENS_SIZE},/" ${MOM6_BATS_DIR}/DART/input.nml

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
    cp ${baseline_subdir}/ocean_geometry.nc ${ensemble_subdir}/ocean_geometry.nc

    sed -i "s/input_filename = .*/input_filename = 'r',/" ${ensemble_subdir}/input.nml
    sed -i "s%restart_input_dir = .*%restart_input_dir = 'RESTART/',%" ${ensemble_subdir}/input.nml
done

echo "setting MOM6 timestep to ${MOM6_LARGESTEP} seconds for each ensemble member..."

for i in $(seq ${ENS_SIZE}); do
    sed -i "s/DT = .*/DT = ${MOM6_LARGESTEP}/" ${MOM6_BATS_DIR}/ensemble/member_$(printf "%04d" ${i})/MOM_input
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
sed -i "s/perturb_from_single_instance = .*/perturb_from_single_instance = .true.,/" ${MOM6_BATS_DIR}/DART/input.nml

echo "beginning the assimilation loop..."

first_assimilation_complete=false

while [ $currentday_dart -lt $LASTDAY_DART ]
do
    echo "searching for an obs-sequence file for day ${currentday_mom6} (MOM6 calendar)..."
    echo "                                           ${currentday_dart} (DART calendar)..."

    if [ -f ${OBSSEQ_DIR}/BATS_${currentday_dart}.out ]
    then
        echo "found file, assimilating with DART..."

        outputdir=${MOM6_BATS_DIR}/output/${currentday_dart}
        mkdir ${outputdir}

        sed -i "s%obs_sequence_in_name.*%obs_sequence_in_name ='\\${OBSSEQ_DIR}/BATS_${currentday_dart}.out',%" ${MOM6_BATS_DIR}/DART/input.nml
        sed -i "s%obs_sequence_out_name.*%obs_sequence_out_name ='\\${outputdir}/obs_seq.final',%" ${MOM6_BATS_DIR}/DART/input.nml

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

        mv ${MOM6_BATS_DIR}/DART/dart_log.out ${outputdir}
        mv ${MOM6_BATS_DIR}/DART/output_mean.nc ${outputdir}
        mv ${MOM6_BATS_DIR}/DART/output_sd.nc ${outputdir}
        mv ${MOM6_BATS_DIR}/DART/preassim* ${outputdir}
        mv ${MOM6_BATS_DIR}/DART/analysis* ${outputdir}

        if ! ${first_assimilation_complete} 
        then
            first_assimilation_complete=true
            echo "setting MOM6 timestep to ${MOM6_SMALLSTEP} seconds for each ensemble member..."

            for i in $(seq ${ENS_SIZE}); do
                sed -i "s/DT = .*/DT = ${MOM6_SMALLSTEP}/" ${MOM6_BATS_DIR}/ensemble/member_$(printf "%04d" ${i})/MOM_input
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
    
    current_seconds=${SECONDS}
    let diff=${current_seconds}-${init_seconds}

    echo ""
    echo "time since start: ${diff} seconds."
    echo ""

    currentday_mom6=${tomorrow_mom6}
    currentday_dart=${tomorrow_dart}
done

echo "assimilation loop complete."
echo "exiting..."
echo ""
