#!/bin/bash

# =====================================================================================
# ======================= SCRIPT PARAMETERS ===========================================
# =====================================================================================

# important paths, keep these absolute
MOM6_BIN=/glade/work/rarmstrong/cesm/cesm2_3_alpha12b+mom6_marbl/components/mom/standalone/build/intel-casper/MOM6/MOM6
CONDA_ACTIVATE=/glade/u/home/rarmstrong/work/miniconda3/bin/activate
MOM6_BATS_DIR=/glade/work/rarmstrong/cesm/cesm2_3_alpha12b+mom6_marbl/components/mom/standalone/examples/single_column_MARBL/BATS_param_estimation
OBSSEQ_DIR=/glade/u/home/rarmstrong/work/DART/observations/obs_converters/BATS_clim

# data assimilation parameters
ENS_SIZE=3   # number of ensemble members
EQ_YEARS=1   # number of years that MARBL will be integrated to reach quasi-equilibrium
NUM_CYCLES=1 # number of data assimilation cycles

# other
PROG_FILE=prog_z.nc                             # the name (without path) of a MOM6 diagnostic file which records time-series for all MARBL variables with daily resolution
LAYER_FILE=python_scripts/driver/marbl_zl.txt   # comma-separated list of pseudo-depths in prog_z.nc
MOM_TIMESTEP=14400                              # MOM timestep
SEED=1                                          # random seed for generating initial parameter perturbations

# =====================================================================================
# ======================= MAIN PROGRAM ================================================
# =====================================================================================

process_id=${1}
module load nco
source ${CONDA_ACTIVATE} marbl-dart

let eq_days=${EQ_YEARS}*365

if [ ${process_id} -eq 1 ]; then
    echo ""
    echo "================================================================"
    echo "============================ DRIVER ============================"
    echo "================================================================"
    echo ""

    echo "deleting old ensemble..."
    rm -rf ${MOM6_BATS_DIR}/ensemble/*

    echo "deleting old output files..."
    rm -rf ${MOM6_BATS_DIR}/output/*

    echo "preparing temp directory..."
    export TMPDIR=/glade/scratch/${USER}/marbl_mom6_dart_temp
    mkdir -p ${TMPDIR}

    echo "setting ensemble size in DART namelist..."

    sed -i "s/num_output_state_members.*/num_output_state_members = ${ENS_SIZE}/" ${MOM6_BATS_DIR}/DART/input.nml
    sed -i "s/num_output_obs_members.*/num_output_obs_members = ${ENS_SIZE}/" ${MOM6_BATS_DIR}/DART/input.nml
    sed -i "s/ens_size.*/ens_size = ${ENS_SIZE}/" ${MOM6_BATS_DIR}/DART/input.nml

    echo "beginning the assimilation loop..."
fi

cycle_number=1

# data assimilation loop
while [ ${cycle_number} -le ${NUM_CYCLES} ]; do
    if [ ${process_id} -eq 1 ]; then
        if [ ${cycle_number} -lt ${NUM_CYCLES} ]; then
            echo ""
            echo "~~~~~~~~~~~~~~~"
            echo "CYCLE ${cycle_number}"
            echo "~~~~~~~~~~~~~~~"
        else
                echo ""
            echo "~~~~~~~~~~~~~~~"
            echo "CYCLE ${cycle_number} (final)"
            echo "~~~~~~~~~~~~~~~"
        fi

        for i in $(seq ${ENS_SIZE}); do
            echo ""
            echo "resetting data for ensemble member ${i}..."

            memberdir=${MOM6_BATS_DIR}/ensemble/member_$(printf "%04d" ${i})
            rm -rf ${memberdir}
            mkdir ${memberdir}
            cp -Lr ${MOM6_BATS_DIR}/baseline_state/* ${memberdir}
            mkdir ${memberdir}/climatology

            echo "setting member 1 integration length to ${eq_days} days..."
            sed -i "s/DAYMAX = .*/DAYMAX = ${eq_days}/" ${memberdir}/MOM_input

            echo "setting member 1 MOM time-step to ${MOM_TIMESTEP} seconds..."
            sed -i "s/DT = .*/DT = ${MOM_TIMESTEP}/" ${memberdir}/MOM_input
        done

        echo ""

        if [ ${cycle_number} -eq 1 ]; then
            echo "initiating record of ensemble parameter statistics..."

            mkdir -p ${MOM6_BATS_DIR}/output/parameter_record
            python3 ${MOM6_BATS_DIR}/python_scripts/driver/record_params.py "init" ${MOM6_BATS_DIR}/ensemble ${ENS_SIZE} ${MOM6_BATS_DIR}/output/parameter_record/param_record.nc 2>&1
        fi

        echo "perturbing the ensemble parameters..."

        let randomseed=${SEED}+${cycle_number}
        python3 ${MOM6_BATS_DIR}/python_scripts/driver/perturb_params.py ${MOM6_BATS_DIR}/baseline_state ${MOM6_BATS_DIR}/ensemble ${ENS_SIZE} ${MOM6_BATS_DIR}/python_scripts/driver/marbl_zl.txt ${randomseed} 2>&1

        echo "integrating the ensemble..."
        echo ""

        init_seconds=${SECONDS}

        # writing files which signal the other processes to begin running MOM6
        for i in $(seq ${ENS_SIZE}); do
            touch ${MOM6_BATS_DIR}/.begin_mom6_$(printf "%04d" ${i})
        done
    fi

    # waiting for permission from process no. 1 to begin the next integration
    while true; do
        if [ -f "${MOM6_BATS_DIR}/.begin_mom6_$(printf "%04d" ${process_id})" ]; then
            rm ${MOM6_BATS_DIR}/.begin_mom6_$(printf "%04d" ${process_id})
            break
        else
            sleep 1
        fi
    done

    memberdir=${MOM6_BATS_DIR}/ensemble/member_$(printf "%04d" ${process_id})
    logfile=${memberdir}/member_$(printf "%04d" ${process_id})_logfile.txt

    if [ ${cycle_number} -eq 1 ]; then
        rm -f ${logfile}

        echo "================================================================" >> ${logfile}
        echo "============================ DRIVER ============================" >> ${logfile}
        echo "================================================================" >> ${logfile}
        echo ""                                                                 >> ${logfile}
    fi

    echo "ASSIMILATION CYCLE ${cycle_number}:"                                       >> ${logfile}
    echo ""                                                                          >> ${logfile}
    echo "initiating ${EQ_YEARS}-year MARBL integration for member ${process_id}..." >> ${logfile}
    
    back=$(pwd -P)

    echo ""                                                                 >> ${logfile}
    echo "================================================================" >> ${logfile}
    echo "========================== MARBL / MOM6 ========================" >> ${logfile}
    echo "================================================================" >> ${logfile}
    echo ""                                                                 >> ${logfile}

    cd ${memberdir}
    ${MOM6_BIN} >> ${logfile} 2>&1
    cd ${back}

    echo ""                                                                 >> ${logfile}
    echo "================================================================" >> ${logfile}
    echo "============================ DRIVER ============================" >> ${logfile}
    echo "================================================================" >> ${logfile}
    echo ""                                                                 >> ${logfile}

    echo "finished MARBL integration."                              >> ${logfile}
    echo "generating climatology files for member ${process_id}..." >> ${logfile}
    
    rm -f ${memberdir}/climatology/clim_*
    python3 ${MOM6_BATS_DIR}/python_scripts/driver/create_climatology.py ${EQ_YEARS} ${memberdir}/${PROG_FILE} ${memberdir}/climatology ${LAYER_FILE} >> ${logfile} 2>&1

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

        echo "archiving MOM integration logfiles..."

        mkdir -p ${MOM6_BATS_DIR}/output/cycle_$(printf "%03d" ${cycle_number})/integration_logfiles
        
        for i in $(seq ${ENS_SIZE}); do
            logfile=member_$(printf "%04d" ${i})_logfile.txt
            mv ${MOM6_BATS_DIR}/ensemble/member_$(printf "%04d" ${i})/${logfile} ${MOM6_BATS_DIR}/output/cycle_$(printf "%03d" ${cycle_number})/integration_logfiles/${logfile}
        done

        echo "recording the ensemble average climatologies..."

        mkdir ${MOM6_BATS_DIR}/output/cycle_$(printf "%03d" ${cycle_number})/average_climatologies
        python3 ${MOM6_BATS_DIR}/python_scripts/driver/average_climatologies.py ${MOM6_BATS_DIR}/ensemble ${ENS_SIZE} ${LAYER_FILE} ${MOM6_BATS_DIR}/output/cycle_$(printf "%03d" ${cycle_number})/average_climatologies 2>&1

        if [ ${cycle_number} -lt ${NUM_CYCLES} ]; then
            echo "beginning data assimilation."
            echo ""

            for month in $(seq 12); do
                if [ -f "${OBSSEQ_DIR}/obs_seq_files/BATS_clim_$(printf "%02d" ${month}).out" ]; then
                    echo "assimilating file with DART: ${OBSSEQ_DIR}/obs_seq_files/BATS_clim_$(printf "%02d" ${month}).out"

                    state_list=${MOM6_BATS_DIR}/DART/ensemble_states.txt
                    param_list=${MOM6_BATS_DIR}/DART/ensemble_params.txt

                    rm -f ${state_list}
                    rm -f ${param_list}

                    for ens_index in $(seq ${ENS_SIZE}); do
                        echo "${MOM6_BATS_DIR}/ensemble/member_$(printf "%04d" ${ens_index})/climatology/clim_$(printf "%02d" ${month}).nc" >> ${state_list}
                        echo "${MOM6_BATS_DIR}/ensemble/member_$(printf "%04d" ${ens_index})/climatology/params_$(printf "%02d" ${month}).nc" >> ${param_list}
                    done

                    out_dir=${MOM6_BATS_DIR}/output/cycle_$(printf "%03d" ${cycle_number})/month_$(printf "%02d" ${month})
                    mkdir ${out_dir}

                    sed -i "s%obs_sequence_in_name.*%obs_sequence_in_name ='${OBSSEQ_DIR}/obs_seq_files/BATS_clim_$(printf "%02d" ${month}).out',%" ${MOM6_BATS_DIR}/DART/input.nml
                    sed -i "s%obs_sequence_out_name.*%obs_sequence_out_name ='${out_dir}/obs_seq.final',%" ${MOM6_BATS_DIR}/DART/input.nml

                    back=$(pwd -P)
                    cd ${MOM6_BATS_DIR}/DART

                    ./filter >> /dev/null

                    mv preassim_mean_* ${out_dir}
                    mv preassim_sd_* ${out_dir}
                    mv analysis_mean_* ${out_dir}
                    mv analysis_sd_* ${out_dir}
                    mv output_mean_* ${out_dir}
                    mv output_sd_* ${out_dir}
                    mv dart_log.out ${out_dir}

                    for file in $(ls -I fill_inflation_restart -I filter -I model_mod_check -I obs_diag -I input.nml -I .gitignore); do
                        rm ${file}
                    done

                    cd ${back}
                else
                    echo "ERROR: failed to locate obs-seq file ${OBSSEQ_DIR}/obs_seq_files/BATS_clim_$(printf "%02d" ${month}).out."
                fi
            done
        fi

        echo "recording the current parameter statistics..."
        python3 ${MOM6_BATS_DIR}/python_scripts/driver/record_params.py "record" ${MOM6_BATS_DIR}/ensemble ${ENS_SIZE} ${MOM6_BATS_DIR}/output/parameter_record/param_record.nc 2>&1

        if [ ${cycle_number} -lt ${NUM_CYCLES} ]; then
            echo "calculating restart parameters for next cycle..."

            let randomseed=${SEED}+${cycle_number}
            python3 ${MOM6_BATS_DIR}/python_scripts/driver/resample_params.py ${MOM6_BATS_DIR}/ensemble ${ENS_SIZE} ${randomseed} 2>&1
        else
            echo "creating diagnostic plot..."
            ### FILL THIS PART IN
        fi
    fi

    let cycle_number=${cycle_number}+1
done
