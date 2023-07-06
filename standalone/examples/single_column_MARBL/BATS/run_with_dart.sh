#!/bin/bash

# ======================= SCRIPT PARAMETERS =======================

# MOM6 binary, keep this path absolute
MOM6_BIN=~/work/cesm/cesm2_3_alpha12b+mom6_marbl/components/mom/standalone/build/intel/MOM6/MOM6

# important filesystem paths, keep these absolute
MOM6_BATS_DIR=$(pwd)                                               # working directory for MOM6
DART_MODEL_DIR=~/work/DART/models/MARBL_MOM6_1D                    # location of DART model information
OBSSEQ_DIR=~/work/BATS_obsseq                                      # location of obs-sequence files

# DA config options
ENS_SIZE=5

# other
MOM6_TO_DART=139157             # offset between MOM6 and DART calendars
MOM6_TIMESTEP=100.0             # timestep to use when advancing ensemble members

# ======================= MAIN PROGRAM =======================

echo ""
echo "================================================================"
echo "============================ SCRIPT ============================"
echo "================================================================"
echo ""

echo "old ensemble data and analysis obs-sequence files will be deleted."
read -p "continue? [y/n] " userchoice

if [ "${userchoice}" != "y" ] && [ "${userchoice}" != "Y" ]
then
    echo ""
    echo "exiting..."
    echo ""
    exit
fi

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
    sed -i "s/DT = .*/DT = ${MOM6_TIMESTEP}/" ${ensemble_subdir}/MOM_input
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

echo "determining the day of the last available observation..."

last_obsseq_file=$(ls ${OBSSEQ_DIR}/out | tail -n 1)
lastday_dart=${last_obsseq_file:5:6}
let lastday_mom6=${lastday_dart}-${MOM6_TO_DART}

echo "determined the day of the last available observation to be ${lastday_mom6} (MOM6 calendar),"
echo "                                                           ${lastday_dart} (DART calendar)."

read -p "simulate until day of last observation? [y/n] " userchoice

if [ "${userchoice}" != "y" ] && [ "${userchoice}" != "Y" ]
then
    read -p "enter last day of simulation (DART calendar): " lastday_dart
    let lastday_mom6=${lastday_dart}-${MOM6_TO_DART}
fi

echo "will simulate until day ${lastday_dart} (DART calendar),"
echo "                        ${lastday_mom6} (MOM6 calendar)."

echo "setting perturb_from_single_instance = .true. ..."
sed -i "s/perturb_from_single_instance = .*/perturb_from_single_instance = .true./" ${DART_MODEL_DIR}/work/input.nml

echo "beginning the assimilation loop..."
first_assimilation_complete=false

while [ $currentday_dart -lt $lastday_dart ]
do
    echo "searching for an obs-sequence file for day ${currentday_mom6} (MOM6 calendar)..."
    echo "                                           ${currentday_dart} (DART calendar)..."

    if [ -f "${OBSSEQ_DIR}/out/BATS_${currentday_dart}.out" ]
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

        ./filter | tee ${back}/program_output.txt
        
        echo ""
        echo "================================================================"
        echo "============================ SCRIPT ============================"
        echo "================================================================"
        echo ""

        cd ${back}

        grep -q "ERROR" program_output.txt
        status=${?}
        rm program_output.txt

        if [ ${status} -eq 0 ]
        then
            echo "error detected from DART."
            echo "exiting..."
            echo ""
            exit
        fi

        if ! ${first_assimilation_complete} 
        then
            first_assimilation_complete=true

            echo "first assimilation complete."
            echo "setting perturb_from_single_instance = .false. ..."
            sed -i "s/perturb_from_single_instance = .*/perturb_from_single_instance = .false./" ${DART_MODEL_DIR}/work/input.nml
        else
            echo "assimilation complete."
        fi
    else
        echo "no file found."
    fi

    let tomorrow_mom6=${currentday_mom6}+1
    let tomorrow_dart=${currentday_dart}+1

    if ! ${first_assimilation_complete}
    then
        echo "advancing the model to day ${tomorrow_mom6} (MOM6 calendar)..."
        echo "                           ${tomorrow_dart} (DART calendar)..."

        sed -i "s/DAYMAX = [0123456789]*/DAYMAX = ${tomorrow_mom6}/" ${MOM6_BATS_DIR}/ensemble/member_0001/MOM_input
        back=$(pwd)
        cd ${MOM6_BATS_DIR}/ensemble/member_0001

        echo ""
        echo "================================================================"
        echo "========================= MOM6 + MARBL ========================="
        echo "================================================================"
        echo ""

        ${MOM6_BIN} | tee ${back}/program_output.txt

        echo ""
        echo "================================================================"
        echo "============================ SCRIPT ============================"
        echo "================================================================"
        echo ""

        cd ${back}

        grep -q "FATAL" program_output.txt
        status=${?}
        rm program_output.txt

        if [ ${status} -eq 0 ]
        then
            echo "fatal error detected from MOM6 + MARBL."
            echo "exiting..."
            echo ""
            exit
        fi

        echo "finished advancing model."
    else
        echo "advancing the ensemble to day ${tomorrow_mom6} (MOM6 calendar)..."
        echo "                              ${tomorrow_dart} (DART calendar)..."
        
        for i in $(seq ${ENS_SIZE}); do
            member_subdir=${MOM6_BATS_DIR}/ensemble/member_$(printf "%04d" ${i})
            
            sed -i "s/DAYMAX = .*/DAYMAX = ${tomorrow_mom6}/" ${member_subdir}/MOM_input
            
            echo "advancing ensemble member ${i}..."
            back=$(pwd)
            cd ${member_subdir}

            echo ""
            echo "================================================================"
            echo "========================= MOM6 + MARBL ========================="
            echo "================================================================"
            echo ""
            
            ${MOM6_BIN} | tee ${back}/program_output.txt

            echo ""
            echo "================================================================"
            echo "============================ SCRIPT ============================"
            echo "================================================================"
            echo ""

            cd ${back}

            grep -q "FATAL" program_output.txt
            status=${?}
            rm program_output.txt

            if [ ${status} -eq 0 ]
            then
                echo "fatal error detected from MOM6 + MARBL."
                echo "exiting..."
                echo ""
                exit
            fi

            echo "finished advancing emsemble member ${i}."
        done

        echo "finished advancing the ensemble."
    fi

    currentday_mom6=${tomorrow_mom6}
    currentday_dart=${tomorrow_dart}
done

echo "assimilation loop complete."
echo "exiting..."
echo ""
