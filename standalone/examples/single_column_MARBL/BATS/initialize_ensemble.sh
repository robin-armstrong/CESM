#!/bin/bash

# ======================= SCRIPT PARAMETERS =======================

# important paths, keep these absolute
MOM6_BIN=~/work/cesm/cesm2_3_alpha12b+mom6_marbl/components/mom/standalone/build/intel-cheyenne/MOM6/MOM6
MOM6_BATS_DIR=$(pwd)

# ensemble size
ENS_SIZE=80

SAMPLES_PER_YEAR=5      # the number of ensemble members that will be sampled from each year
DAYS_BETWEEN_SAMPLES=10 # the days between sampling ensemble members in a given year

# the day when the assimilation loop will start (MOM6 calendar)
FIRSTDAY_MOM6=8455

# ======================= MAIN PROGRAM =======================

echo ""
echo "================================================================"
echo "===================== INITIALIZATION DRIVER ===================="
echo "================================================================"
echo ""

let n=365*$((${FIRSTDAY_MOM6}/365))
let first_sample_day=${FIRSTDAY_MOM6}-$n

echo "deleting old ensemble members..."

rm -rf ${MOM6_BATS_DIR}/ensemble/member*

echo "deleting old ensemble member list..."

rm ${MOM6_BATS_DIR}/DART/ensemble_members.txt

echo "configuring baseline MARBL + MOM6 namelist to read from BATS..."

sed -i "3 s/input_filename = .*/input_filename = 'n',/" ${MOM6_BATS_DIR}/ensemble/baseline/input.nml
sed -i "4 s%restart_input_dir = .*%restart_input_dir = 'INPUT/',%" ${MOM6_BATS_DIR}/ensemble/baseline/input.nml

num_members_created=0
first_integration_complete=false

while [ ${num_members_created} -lt ${ENS_SIZE} ]
do
    echo "advancing the model to day ${first_sample_day}..."

    sed -i "371 s/DAYMAX = .*/DAYMAX = ${first_sample_day}/" ${MOM6_BATS_DIR}/ensemble/baseline/MOM_input
    back=$(pwd)
    cd ${MOM6_BATS_DIR}/ensemble/baseline

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
    echo "finished advancing the model."

    if ! ${first_integration_complete} 
    then
        first_integration_complete=true

        echo "configuring baseline MARBL + MOM6 namelist to read from restart file..."

        sed -i "3 s/input_filename = .*/input_filename = 'r',/" ${MOM6_BATS_DIR}/ensemble/baseline/input.nml
        sed -i "4 s%restart_input_dir = .*%restart_input_dir = 'RESTART/',%" ${MOM6_BATS_DIR}/ensemble/baseline/input.nml
    fi

    echo "sampling ${SAMPLES_PER_YEAR} ensemble members over the next ${SAMPLES_PER_YEAR} days..."

    currentday=${first_sample_day}

    for i in $(seq ${SAMPLES_PER_YEAR})
    do
        let num_members_created=${num_members_created}+1
        echo "sampling member ${num_members_created} from day ${currentday}..."

        memberdir=${MOM6_BATS_DIR}/ensemble/member_$(printf "%04d" ${num_members_created})
        mkdir ${memberdir}
        cp -Lr ${MOM6_BATS_DIR}/ensemble/baseline/* ${memberdir}
        rm ${memberdir}/RESTART/ocean_solo.res

        echo "correcting the timestamp for member ${num_members_created}..."

        ncdump ${memberdir}/RESTART/MOM.res.nc >> MOM.res.txt        
        rm ${memberdir}/RESTART/MOM.res.nc        
        sed -ri "s/Time = [0123456789]+ ;/Time = ${FIRSTDAY_MOM6} ;/" MOM.res.txt
        ncgen MOM.res.txt -o ${memberdir}/RESTART/MOM.res.nc
        rm MOM.res.txt

        echo "adding member ${num_members_created} to the ensemble list..."
        echo "${memberdir}/RESTART/MOM.res.nc" >> ${MOM6_BATS_DIR}/DART/ensemble_members.txt
        
        let currentday=${currentday}+${DAYS_BETWEEN_SAMPLES}
        sed -i "371 s/DAYMAX = .*/DAYMAX = ${currentday}/" ${MOM6_BATS_DIR}/ensemble/baseline/MOM_input

        echo "advancing the model to day ${currentday}..."

        back=$(pwd)
        cd ${MOM6_BATS_DIR}/ensemble/baseline

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
        echo "finished advancing the model."
    done

    let first_sample_day=${first_sample_day}+365
done

echo "finished initializing the ensemble."
echo "exiting..."
echo ""
