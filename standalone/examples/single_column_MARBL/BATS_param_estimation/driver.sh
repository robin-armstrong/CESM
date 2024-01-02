#!/bin/bash

# ======================= SCRIPT PARAMETERS =======================

# if 'true', then the script will erase old DART outputs and start clean
START_CLEAN=true

# important paths, keep these absolute
MOM6_BIN=/glade/work/rarmstrong/cesm/cesm2_3_alpha12b+mom6_marbl/components/mom/standalone/build/intel-casper/MOM6/MOM6
CONDA_ACTIVATE=/glade/u/home/rarmstrong/work/miniconda3/bin/activate
MOM6_BATS_DIR=/glade/work/rarmstrong/cesm/cesm2_3_alpha12b+mom6_marbl/components/mom/standalone/examples/single_column_MARBL/BATS_param_estimation
OBSSEQ_DIR=/glade/u/home/rarmstrong/work/DART/observations/obs_converters/BATS/obs_seq_files

# data assimilation parameters
ENS_SIZE=2
EQ_YEARS=1          # number of years that MARBL will be integrated to reach quasi-equilibrium
NUM_CYCLES=1        # number of data assimilation cycles

# other
PROG_FILE=prog.nc       # the name of a MOM6 diagnostic file which records time-series for all MARBL variables with daily resolution
MOM6_TO_DART=139157     # offset between MOM6 and DART calendars
SEED=1                  # random seed for generating initial parameter perturbations

# ======================= MAIN PROGRAM =======================

process_id=${1}
module load nco
source ${CONDA_ACTIVATE} marbl-dart

let eq_days=${EQ_YEARS}*365

if [ ${process_id} -eq 1 ] && ${START_CLEAN}; then
    echo "deleting old ensemble..."

    rm -rf ${MOM6_BATS_DIR}/ensemble/*

    for i in $(seq ${ENS_SIZE}); do
        echo ""
        echo "initializing data for ensemble member ${i}..."

        memberdir=${MOM6_BATS_DIR}/ensemble/member_$(printf "%04d" ${i})
        mkdir ${memberdir}
        cp -Lr ${MOM6_BATS_DIR}/baseline_state/* ${memberdir}
        mkdir ${memberdir}/climatology

        echo "perturbing parameters for ensemble member ${i}..."

        cp ${memberdir}/INPUT/marbl_in ${memberdir}/INPUT/marbl_in_temp
        rm ${memberdir}/INPUT/marbl_in
        let randomseed=${SEED}+${process_id}
        python3 ${MOM6_BATS_DIR}/perturb_params.py ${memberdir}/INPUT/marbl_in_temp ${randomseed} ${memberdir}/INPUT/marbl_in
        rm ${memberdir}/INPUT/marbl_in_temp

        echo "creating parameter netCDF file for member ${i}..."
        python3 ${MOM6_BATS_DIR}/marbl_to_dart.py ${memberdir}/INPUT/marbl_in ${FIRSTDAY_MOM6} ${memberdir}/INPUT/marbl_params.nc
    done

    echo "preparing temp directory..."
    export TMPDIR=/glade/scratch/${USER}/marbl_mom6_dart_temp
    mkdir -p ${TMPDIR}

    echo "setting integration length to ${eq_days} days..."

    for i in $(seq ${ENS_SIZE}); do
        sed -i "380 s/DAYMAX = .*/DAYMAX = ${eq_days}/" ${MOM6_BATS_DIR}/ensemble/member_$(printf "%04d" ${i})/MOM_input
    done

    echo "beginning the assimilation loop..."
fi

completed_cycles=0

# data assimilation loop
while [ ${completed_cycles} -lt ${NUM_CYCLES} ]; do
    if [ ${process_id} -eq 1 ]; then
        echo "integrating the ensemble..."
        echo ""

        init_seconds=${SECONDS}

        # writing files which signal the other processes to begin running MOM6
        for i in $(seq ${ENS_SIZE}); do
            touch ${MOM6_BATS_DIR}/.begin_mom6_$(printf "%04d" ${i})
        done
    fi

    # waiting for permission from process no. 1 to run MOM6
    while true; do
        if [ -f "${MOM6_BATS_DIR}/.begin_mom6_$(printf "%04d" ${process_id})" ]; then
            rm ${MOM6_BATS_DIR}/.begin_mom6_$(printf "%04d" ${process_id})
            break
        else
            sleep 1
        fi
    done

    memberdir=${MOM6_BATS_DIR}/ensemble/member_$(printf "%04d" ${process_id})
    back=$(pwd -P)

    cd ${memberdir}
    ${MOM6_BIN}

    cd ${back}
    rm ${memberdir}/climatology/*
    python3 ${MOM6_BATS_DIR}/create_climatology.py ${EQ_YEARS} ${memberdir}/${PROG_FILE} ${memberdir}/climatology

    touch ${MOM6_BATS_DIR}/.mom6_complete_$(printf "%04d" ${process_id})
    
    # process no. 1 prepares for the next assimilation cycle
    if [ ${process_id} -eq 1 ]; then
        # waiting for all the MOM6 instances to finish before proceeding
        while true; do
            foundall=true

            for i in $(seq ${ENS_SIZE}); do
                if ! [ -f "${MOM6_BATS_DIR}/.mom6_complete_$(printf "%04d" ${i})" ]; then
                    foundall=false
                fi
            done

            if ${foundall}; then
                break
            else
                sleep 1
            fi
        done

        rm ${MOM6_BATS_DIR}/.mom6_complete*

        echo ""
        echo "finished advancing the ensemble."

        current_seconds=${SECONDS}
        let diff=${current_seconds}-${init_seconds}

        echo "integration wall-time: ${diff} seconds."
    fi

    # DATA ASSIMILATION HAPPENS HERE

    let completed_cycles=${completed_cycles}+1
done
