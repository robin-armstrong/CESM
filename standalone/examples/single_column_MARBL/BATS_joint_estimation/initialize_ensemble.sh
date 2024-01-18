#!/bin/bash

# ======================= SCRIPT PARAMETERS =======================

# Important paths, keep these absolute.
MOM6_BIN=~/work/cesm/cesm2_3_alpha12b+mom6_marbl/components/mom/standalone/build/intel-casper/MOM6/MOM6
MOM6_BATS_DIR=$(pwd -P)
CONDA_ACTIVATE=/glade/u/home/rarmstrong/work/miniconda3/bin/activate

# Ensemble size.
ENS_SIZE=80

# Day when the assimilation loop will start (MOM6 calendar).
FIRSTDAY_MOM6=8455

# Minimum length, in years, of the spin-up for each ensemble member.
MIN_SPINUP_LENGTH=10

# Member i undergoes a spinup of length (i + $MIN_SPINUP_LENGTH) % $SPINUP_LENGTH_MODULUS.
# Varying spinup times are used to promote higher spread in the initial ensemble.
SPINUP_LENGTH_MODULUS=80

# Length, in days, of yearly time interval where state samples are taken.
# Yearly averages of these samples are recorded to serve as a diagnostic for
# whether or not the spin-up reached steady state.
SAMPLES_PER_YEAR=20

# BGC variable that the yearly averages are computed for.
BGC_VAR=O2

# Random number seed for creating the parameter perturbations. This number is combined
# with ensemble member indices to create a unique random seed for each member.
SEED=1

# ======================= MAIN PROGRAM =======================

member_index=${1}
source ${CONDA_ACTIVATE} marbl-dart

echo ""
echo "================================================================"
echo "===================== INITIALIZATION DRIVER ===================="
echo "================================================================"
echo ""

let spinup_length=${MIN_SPINUP_LENGTH}+${member_index}
let offset=${SPINUP_LENGTH_MODULUS}*$((${member_index}/${SPINUP_LENGTH_MODULUS}))
let spinup_length=${spinup_length}-${offset}

let n=365*$((${FIRSTDAY_MOM6}/365))
let first_sample_day=${FIRSTDAY_MOM6}-${n}

echo "removing old data for member ${member_index}..."

memberdir=${MOM6_BATS_DIR}/ensemble/member_$(printf "%04d" ${member_index})
rm -rf ${memberdir}

echo "creating directory for member ${member_index}..."

mkdir ${memberdir}
cp -Lr ${MOM6_BATS_DIR}/ensemble/baseline/* ${memberdir}

echo "perturbing the BGC parameters for member ${member_index}..."

cp ${memberdir}/marbl_in ${memberdir}/marbl_in_temp
rm ${memberdir}/marbl_in
let randomseed=${SEED}+${member_index}
python3 ${MOM6_BATS_DIR}/python_scripts/perturb_params.py ${memberdir}/marbl_in_temp ${randomseed} ${memberdir}/marbl_in 2>&1
rm ${memberdir}/marbl_in_temp

echo "creating parameter netCDF file for member ${member_index}..."
python3 ${MOM6_BATS_DIR}/python_scripts/marbl_to_dart.py ${memberdir}/marbl_in ${FIRSTDAY_MOM6} ${memberdir}/marbl_params.nc 2>&1

echo "beginning ${spinup_length}-year spinup for member ${member_index}..."
echo "advancing member ${member_index} to day ${first_sample_day}..."

sed -i "380 s/DAYMAX = .*/DAYMAX = ${first_sample_day}/" ${memberdir}/MOM_input
back=$(pwd -P)
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

while [ ${spinup_time} -lt ${spinup_length} ]
do
    let spinup_time=${spinup_time}+1
    echo "taking samples over the next ${SAMPLES_PER_YEAR} days..."

    currentday=${first_sample_day}

    for sample_num in $(seq ${SAMPLES_PER_YEAR})
    do
        echo "taking sample on day ${currentday}..."
        python3 ${MOM6_BATS_DIR}/python_scripts/record_spinup.py ${BGC_VAR} ${spinup_time} ${sample_num} ${memberdir}/RESTART/MOM.res.nc ${memberdir}/spinup_record.nc 2>&1

        let currentday=${currentday}+1
        echo "advancing member ${member_index} to day ${currentday}..."

        sed -i "380 s/DAYMAX = .*/DAYMAX = ${currentday}/" ${memberdir}/MOM_input
        back=$(pwd -P)
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

    sed -i "380 s/DAYMAX = .*/DAYMAX = ${currentday}/" ${memberdir}/MOM_input
    back=$(pwd -P)
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

res_txt=${memberdir}/RESTART/MOM.res.txt
ncdump ${memberdir}/RESTART/MOM.res.nc >> ${res_txt}
rm ${memberdir}/RESTART/MOM.res.nc
sed -ri "s/Time = [0123456789]+ ;/Time = ${FIRSTDAY_MOM6} ;/" ${res_txt}
ncgen ${res_txt} -o ${memberdir}/RESTART/MOM.res.nc
rm ${res_txt}

echo "removing ocean_solo.res..."
rm ${memberdir}/RESTART/ocean_solo.res

echo "turning off checksum verification for member ${member_index} restart file..."

echo "" >> ${memberdir}/MOM_input
echo "RESTART_CHECKSUMS_REQUIRED = False" >> ${memberdir}/MOM_input

echo "finished initializing member ${member_index}."
touch ${MOM6_BATS_DIR}/.init_complete_$(printf "%04d" ${member_index})

# process no. 1 creates ensemble lists once all the other processes have finished
if [ ${member_index} -eq 1 ]; then
    # waiting for all other processes to finish before proceeding
    while true; do
        foundall=true

        for i in $(seq ${ENS_SIZE}); do
            if ! [ -f "${MOM6_BATS_DIR}/.init_complete_$(printf "%04d" ${i})" ]; then
                foundall=false
            fi
        done

        if ${foundall}; then
            break
        else
            sleep 1
        fi
    done

    rm ${MOM6_BATS_DIR}/.init_complete*

    echo "deleting old ensemble member lists..."

    rm -f ${MOM6_BATS_DIR}/DART/ensemble_states.txt
    rm -f ${MOM6_BATS_DIR}/DART/ensemble_states.txt

    echo "creating new ensemble member lists..."

    for i in $(seq ${ENS_SIZE}); do
        echo "${MOM6_BATS_DIR}/ensemble/member_$(printf "%04d" ${i})/RESTART/MOM.res.nc" >> ${MOM6_BATS_DIR}/DART/ensemble_states.txt
        echo "${MOM6_BATS_DIR}/ensemble/member_$(printf "%04d" ${i})/marbl_params.nc" >> ${MOM6_BATS_DIR}/DART/ensemble_params.txt
    done

    echo "finished creating ensemble member lists."
fi

echo "exiting..."
echo ""
