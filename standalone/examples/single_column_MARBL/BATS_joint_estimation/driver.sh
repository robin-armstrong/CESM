#!/bin/bash

# ======================= SCRIPT PARAMETERS =======================

# if 'true', then the script will erase old DART outputs and start clean
START_CLEAN=true

# important paths, keep these absolute
MOM6_BIN=/glade/work/rarmstrong/cesm/cesm2_3_alpha12b+mom6_marbl/components/mom/standalone/build/intel-casper/MOM6/MOM6
CONDA_ACTIVATE=/glade/u/home/rarmstrong/work/miniconda3/bin/activate
MOM6_BATS_DIR=/glade/work/rarmstrong/cesm/cesm2_3_alpha12b+mom6_marbl/components/mom/standalone/examples/single_column_MARBL/BATS_joint_estimation
OBSSEQ_DIR=/glade/u/home/rarmstrong/work/DART/observations/obs_converters/BATS/obs_seq_files
ENS_BACKUP_DIR=/glade/u/home/rarmstrong/marbldart_ensemble_backup

# ensemble size
ENS_SIZE=80

# other
LASTDAY_DART=149473     # last day of simulation (DART calendar)
MOM6_TO_DART=139157     # offset between MOM6 and DART calendars
MOM6_TIMESTEP=3600.0    # timestep (seconds) to use when advancing ensemble members

# ======================= MAIN PROGRAM =======================

process_id=${1}
module load nco
source ${CONDA_ACTIVATE} marbl-dart

if [ ${process_id} -eq 1 ]; then
    echo ""
    echo "================================================================"
    echo "============================ DRIVER ============================"
    echo "================================================================"
    echo ""

    echo "determining the initial model time..."
fi

timestr=$(ncdump ${MOM6_BATS_DIR}/ensemble/member_0001/RESTART/MOM.res.nc | grep "Time = [0123456789]* ;")
timestr_length=${#timestr}
let timestr_lastindex=${timestr_length}-2
let timestamp_length=${timestr_lastindex}-8
currentday_mom6=${timestr:8:${timestamp_length}}
let currentday_dart=${currentday_mom6}+${MOM6_TO_DART}

if [ ${process_id} -eq 1 ]; then
    echo "determined the initial model time to be ${currentday_mom6} (MOM6 calendar),"
    echo "                                        ${currentday_dart} (DART calendar)."
fi

# process no. 1 performs file organization tasks
if [ ${process_id} -eq 1 ]; then
    if ${START_CLEAN}; then
        echo "deleting old DART output files..."

        rm -rf ${MOM6_BATS_DIR}/output/*
        mkdir ${MOM6_BATS_DIR}/output/member_0001_archive
        mkdir ${MOM6_BATS_DIR}/output/parameter_record
        rm -f ${MOM6_BATS_DIR}/DART/template_priorinf*
        rm -f ${MOM6_BATS_DIR}/DART/input_priorinf*
        rm -f ${MOM6_BATS_DIR}/DART/output_priorinf*

        echo "initiating record of ensemble parameter statistics..."

        python3 ${MOM6_BATS_DIR}/python_scripts/record_params.py "init" ${ENS_SIZE} ${MOM6_BATS_DIR}/output/parameter_record/param_record.nc 0

        echo "configuring the DART namelist file..."

        sed -i "32 s%input_state_files = .*%input_state_files = '',%" ${MOM6_BATS_DIR}/DART/input.nml
        sed -i "33 s%input_state_file_list = .*%input_state_file_list = '${MOM6_BATS_DIR}/DART/ensemble_states.txt', '${MOM6_BATS_DIR}/DART/ensemble_params.txt',%" ${MOM6_BATS_DIR}/DART/input.nml
        sed -i "38 s%output_state_files = .*%output_state_files = '',%" ${MOM6_BATS_DIR}/DART/input.nml
        sed -i "39 s%output_state_file_list = .*%output_state_file_list = '${MOM6_BATS_DIR}/DART/ensemble_states.txt', '${MOM6_BATS_DIR}/DART/ensemble_params.txt',%" ${MOM6_BATS_DIR}/DART/input.nml
        sed -i "42 s/num_output_state_members = .*/num_output_state_members = ${ENS_SIZE},/" ${MOM6_BATS_DIR}/DART/input.nml
        sed -i "47 s/ens_size = .*/ens_size = ${ENS_SIZE},/" ${MOM6_BATS_DIR}/DART/input.nml
        sed -i "49 s/perturb_from_single_instance = .*/perturb_from_single_instance = .false.,/" ${MOM6_BATS_DIR}/DART/input.nml
        sed -i "58 s/num_output_obs_members = .*/num_output_obs_members = ${ENS_SIZE},/" ${MOM6_BATS_DIR}/DART/input.nml
        sed -i "141 s%template_file = .*%template_file = '${MOM6_BATS_DIR}/ensemble/member_0001/RESTART/MOM.res.nc', '${MOM6_BATS_DIR}/ensemble/member_0001/marbl_params.nc',%" ${MOM6_BATS_DIR}/DART/input.nml

        echo "generating inflation restart files..."

        back=$(pwd -P -P)
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

    echo "preparing temp directory..."
    export TMPDIR=/glade/scratch/${USER}/marbl_mom6_dart_temp
    mkdir -p ${TMPDIR}

    echo "beginning the assimilation loop..."
fi

while true
do
    # process no. 1 performs data assimilation and file organization
    if [ ${process_id} -eq 1 ]; then
        echo "archiving the state of member 1..."
        cp ${MOM6_BATS_DIR}/ensemble/member_0001/RESTART/MOM.res.nc ${MOM6_BATS_DIR}/output/member_0001_archive/${currentday_dart}.state.nc
        cp ${MOM6_BATS_DIR}/ensemble/member_0001/marbl_params.nc ${MOM6_BATS_DIR}/output/member_0001_archive/${currentday_dart}.params.nc

        echo "searching for an obs-sequence file for day ${currentday_mom6} (MOM6 calendar)..."
        echo "                                           ${currentday_dart} (DART calendar)..."

        if [ -f "${OBSSEQ_DIR}/BATS_${currentday_dart}.out" ]
        then
            echo "found file, assimilating with DART..."

            outputdir=${MOM6_BATS_DIR}/output/${currentday_dart}
            mkdir ${outputdir}

            sed -i "56 s%obs_sequence_in_name.*%obs_sequence_in_name ='\\${OBSSEQ_DIR}/BATS_${currentday_dart}.out',%" ${MOM6_BATS_DIR}/DART/input.nml
            sed -i "57 s%obs_sequence_out_name.*%obs_sequence_out_name ='\\${outputdir}/obs_seq.final',%" ${MOM6_BATS_DIR}/DART/input.nml

            back=$(pwd -P)
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

            echo "adding vertical layers to output inflation files..."
            ncks -A -v h template_priorinf_mean_d01.nc output_priorinf_mean_d01.nc
            ncks -A -v h template_priorinf_sd_d01.nc output_priorinf_sd_d01.nc

            cd ${back}

            echo "archiving the assimilation output..."
            mv ${MOM6_BATS_DIR}/DART/dart_log.out ${outputdir}
            mv ${MOM6_BATS_DIR}/DART/output_mean* ${outputdir}
            mv ${MOM6_BATS_DIR}/DART/output_sd* ${outputdir}
            mv ${MOM6_BATS_DIR}/DART/preassim* ${outputdir}
            mv ${MOM6_BATS_DIR}/DART/analysis* ${outputdir}
            mv ${MOM6_BATS_DIR}/DART/input_priorinf* ${outputdir}
            mv ${MOM6_BATS_DIR}/DART/output_priorinf* ${outputdir}

            echo "recording the current parameter statistics..."

            python3 ${MOM6_BATS_DIR}/python_scripts/record_params.py "record" ${ENS_SIZE} ${MOM6_BATS_DIR}/output/parameter_record/param_record.nc ${currentday_dart}
            
            echo "preparing inflation files for the next assimilation cycle..."
            cp ${outputdir}/output_priorinf_mean_d01.nc ${MOM6_BATS_DIR}/DART/input_priorinf_mean_d01.nc
            cp ${outputdir}/output_priorinf_sd_d01.nc ${MOM6_BATS_DIR}/DART/input_priorinf_sd_d01.nc

            cp ${outputdir}/output_priorinf_mean_d02.nc ${MOM6_BATS_DIR}/DART/input_priorinf_mean_d02.nc
            cp ${outputdir}/output_priorinf_sd_d02.nc ${MOM6_BATS_DIR}/DART/input_priorinf_sd_d02.nc

            echo "signaling ensemble members to refresh MARBL parameters before running MOM6..."

            for i in $(seq ${ENS_SIZE}); do
                touch ${MOM6_BATS_DIR}/.refresh_params_$(printf "%04d" ${i})
            done
        else
            echo "no file found."
        fi

        let tomorrow_mom6=${currentday_mom6}+1
        let tomorrow_dart=${currentday_dart}+1

        echo "advancing the ensemble to day ${tomorrow_mom6} (MOM6 calendar)..."
        echo "                              ${tomorrow_dart} (DART calendar)..."
        echo ""

        for i in $(seq ${ENS_SIZE}); do
            sed -i "380 s/DAYMAX = .*/DAYMAX = ${tomorrow_mom6}/" ${MOM6_BATS_DIR}/ensemble/member_$(printf "%04d" ${i})/MOM_input
        done

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
        fi

        # checking for an "exit" signal from process no. 1
        if [ -f "${MOM6_BATS_DIR}/.stop_cycle_$(printf "%04d" ${process_id})" ]; then
            rm ${MOM6_BATS_DIR}/.stop_cycle_$(printf "%04d" ${process_id})
            exit
        fi
    done

    # if necessary, refreshing MARBL parameters before running MOM6
    if [ -f "${MOM6_BATS_DIR}/.refresh_params_$(printf "%04d" ${process_id})" ]; then
        rm ${MOM6_BATS_DIR}/.refresh_params_$(printf "%04d" ${process_id})
        
        # moving the old parameter file to a temp file that will soon be deleted
        memberdir=${MOM6_BATS_DIR}/ensemble/member_$(printf "%04d" ${process_id})
        cp ${memberdir}/marbl_in ${memberdir}/marbl_in_temp
        rm ${memberdir}/marbl_in

        # generating the new parameter file from DART output
        python3 ${MOM6_BATS_DIR}/python_scripts/dart_to_marbl.py ${memberdir}/marbl_params.nc ${memberdir}/marbl_in_temp ${memberdir}/marbl_in
        rm ${memberdir}/marbl_in_temp
        rm ${memberdir}/marbl_params.nc

        # regenerating the DART parameter file so that it has a correct timestamp,
        # this also has the effect of equalizing parameter values across different layers
        # in the resulting NetCDF file. The shared parameter value is calculated by the
        # 'getvalue()' function in dart_to_marbl.py.
        python3 ${MOM6_BATS_DIR}/python_scripts/marbl_to_dart.py ${memberdir}/marbl_in ${currentday_mom6} ${memberdir}/marbl_params.nc
    fi

    back=$(pwd -P)
    cd ${MOM6_BATS_DIR}/ensemble/member_$(printf "%04d" ${process_id})
    mom6_log=mom6_logfile_${process_id}.txt
    rm -f ${mom6_log}
    ${MOM6_BIN} >> ${mom6_log}
    cd ${back}
    touch ${MOM6_BATS_DIR}/.mom6_complete_$(printf "%04d" ${process_id})

    let currentday_mom6=${currentday_mom6}+1
    let currentday_dart=${currentday_dart}+1

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

        if [ ${currentday_dart} -eq ${LASTDAY_DART} ]; then
            echo "assimilation loop complete."
            echo "sending exit signal to ensemble members..."

            for i in $(seq ${ENS_SIZE}); do
                touch ${MOM6_BATS_DIR}/.stop_cycle_$(printf "%04d" ${i})
            done

            rm ${MOM6_BATS_DIR}/.stop_cycle_0001

            echo "exiting..."
            echo ""

            exit
        fi
    fi
done
