#!/bin/bash

# ======================= SCRIPT PARAMETERS =======================

START_CLEAN=true
FIRST_MEMBER_INDEX=1

# Important paths, keep these absolute.
MOM6_BIN=~/work/cesm/cesm2_3_alpha12b+mom6_marbl/components/mom/standalone/build/intel-cheyenne/MOM6/MOM6
MOM6_BATS_DIR=$(pwd)
CONDA_ACTIVATE=/glade/u/home/rarmstrong/work/miniconda3/bin/activate

# Ensemble size.
ENS_SIZE=3

# Day when the assimilation loop will start (MOM6 calendar).
FIRSTDAY_MOM6=8455

# Length, in years, of the spin-up for each ensemble member.
SPINUP_LENGTH=50

# Length, in days, of yearly time interval where state samples are taken.
# Yearly averages of these samples are recorded to serve as a diagnostic for
# whether or not the spin-up reached steady state.
SAMPLES_PER_YEAR=20

# BGC variable that the yearly averages are computed for.
BGC_VAR=O2

# Random number seed for creating the parameter perturbations.
SEED=1

# ======================= MAIN PROGRAM =======================

echo ""
echo "================================================================"
echo "===================== INITIALIZATION DRIVER ===================="
echo "================================================================"
echo ""

source ${CONDA_ACTIVATE} marbl-dart

let n=365*$((${FIRSTDAY_MOM6}/365))
let first_sample_day=${FIRSTDAY_MOM6}-${n}

if ${START_CLEAN}; then
    echo "deleting old ensemble members..."

    rm -rf ${MOM6_BATS_DIR}/ensemble/member*

    echo "deleting old ensemble member lists..."

    rm -f ${MOM6_BATS_DIR}/DART/ensemble_states.txt
    rm -f ${MOM6_BATS_DIR}/DART/ensemble_params.txt
fi

let member_index=${FIRST_MEMBER_INDEX}-1

while [ ${member_index} -lt ${ENS_SIZE} ]
do
    let member_index=${member_index}+1

    echo "creating directory for member ${member_index}..."
    
    memberdir=${MOM6_BATS_DIR}/ensemble/member_$(printf "%04d" ${member_index})
    rm -rf ${memberdir}
    sed -i "\:${memberdir}/RESTART/MOM.res.nc:d" ${MOM6_BATS_DIR}/DART/ensemble_states.txt
    sed -i "\:${memberdir}/INPUT/marbl_params.nc:d" ${MOM6_BATS_DIR}/DART/ensemble_params.txt

    mkdir ${memberdir}
    cp -Lr ${MOM6_BATS_DIR}/ensemble/baseline/* ${memberdir}

    echo "perturbing the BGC parameters for member ${member_index}..."

    cp ${memberdir}/INPUT/marbl_in ${memberdir}/INPUT/marbl_in_temp
    rm ${memberdir}/INPUT/marbl_in
    let randomseed=${SEED}+${member_index}
    python3 ${MOM6_BATS_DIR}/perturb_params.py ${memberdir}/INPUT/marbl_in_temp ${randomseed} ${memberdir}/INPUT/marbl_in
    rm ${memberdir}/INPUT/marbl_in_temp

    echo "creating parameter netCDF file for member ${member_index}..."
    python3 ${MOM6_BATS_DIR}/marbl_to_dart.py ${memberdir}/INPUT/marbl_in ${FIRSTDAY_MOM6} ${memberdir}/INPUT/marbl_params.nc

    echo "adding member ${member_index} to the ensemble list..."

    echo "${memberdir}/RESTART/MOM.res.nc" >> ${MOM6_BATS_DIR}/DART/ensemble_states.txt
    echo ${memberdir}/INPUT/marbl_params.nc >> ${MOM6_BATS_DIR}/DART/ensemble_params.txt

    echo "advancing ensemble member ${member_index} to day ${first_sample_day}..."

    sed -i "371 s/DAYMAX = .*/DAYMAX = ${first_sample_day}/" ${memberdir}/MOM_input
    back=$(pwd)
    cd ${memberdir}

    echo ""
    echo "================================================================"
    echo "========================= MARBL + MOM6 ========================="
    echo "================================================================"
    echo ""

    ${MOM6_BIN}

    echo ""
    echo "================================================================"
    echo "===================== INITIALIZATION DRIVER ===================="
    echo "================================================================"
    echo ""

    cd ${back}

    echo "finished advancing member ${member_index}."
    echo "configuring member ${member_index} namelist to read from restart file..."

    sed -i "3 s/input_filename = .*/input_filename = 'r',/" ${memberdir}/input.nml
    sed -i "4 s%restart_input_dir = .*%restart_input_dir = 'RESTART/',%" ${memberdir}/input.nml

    spinup_time=0
    currentday=${first_sample_day}

    while [ ${spinup_time} -lt ${SPINUP_LENGTH} ]
    do
        let spinup_time=${spinup_time=0}+1
        echo "taking samples over the next ${SAMPLES_PER_YEAR} days..."

        currentday=${first_sample_day}

        for sample_num in $(seq ${SAMPLES_PER_YEAR})
        do
            echo "taking sample on day ${currentday}..."
            python3 ${MOM6_BATS_DIR}/record_spinup.py ${BGC_VAR} ${spinup_time} ${sample_num} ${memberdir}/RESTART/MOM.res.nc ${memberdir}/spinup_record.nc

            let currentday=${currentday}+1
            echo "advancing member ${member_index} to day ${currentday}..."

            sed -i "371 s/DAYMAX = .*/DAYMAX = ${currentday}/" ${memberdir}/MOM_input
            back=$(pwd)
            cd ${memberdir}

            echo ""
            echo "================================================================"
            echo "========================= MARBL + MOM6 ========================="
            echo "================================================================"
            echo ""

            ${MOM6_BIN}

            echo ""
            echo "================================================================"
            echo "===================== INITIALIZATION DRIVER ===================="
            echo "================================================================"
            echo ""

            cd ${back}

            echo "finished advancing member ${member_index}."
        done

        let first_sample_day=${first_sample_day}+365
        let currentday=${first_sample_day}

        echo "advancing member ${member_index} to day ${currentday}..."

        sed -i "371 s/DAYMAX = .*/DAYMAX = ${currentday}/" ${memberdir}/MOM_input
        back=$(pwd)
        cd ${memberdir}

        echo ""
        echo "================================================================"
        echo "========================= MARBL + MOM6 ========================="
        echo "================================================================"
        echo ""

        ${MOM6_BIN}

        echo ""
        echo "================================================================"
        echo "===================== INITIALIZATION DRIVER ===================="
        echo "================================================================"
        echo ""

        cd ${back}

        echo "finished advancing member ${member_index}."
    done

    echo "correcting the timestamp for member ${member_index}..."

    ncdump ${memberdir}/RESTART/MOM.res.nc >> MOM.res.txt        
    rm ${memberdir}/RESTART/MOM.res.nc        
    sed -ri "s/Time = [0123456789]+ ;/Time = ${FIRSTDAY_MOM6} ;/" MOM.res.txt
    ncgen MOM.res.txt -o ${memberdir}/RESTART/MOM.res.nc
    rm MOM.res.txt
done

echo "finished initializing the ensemble."
echo "exiting..."
echo ""
