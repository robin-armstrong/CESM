#!/bin/bash

#PBS -N marbldart_joint_init
#PBS -A p93300012
#PBS -J 1-80
#PBS -l select=1:ncpus=4:mpiprocs=1
#PBS -l walltime=12:00:00
#PBS -q casper
#PBS -m abe

rm -f initializer_logfile_$(printf "%04d" ${PBS_ARRAY_INDEX}).txt
./initialize_ensemble.sh ${PBS_ARRAY_INDEX} >> initializer_logfile_$(printf "%04d" ${PBS_ARRAY_INDEX}).txt
