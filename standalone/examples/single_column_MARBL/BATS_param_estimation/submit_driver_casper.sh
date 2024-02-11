#!/bin/bash

#PBS -N marbldart_paramdemo
#PBS -A p93300012
#PBS -J 1-3
#PBS -l select=1:ncpus=4:mpiprocs=1
#PBS -l walltime=12:00:00
#PBS -q casper
#PBS -m abe

if [ ${PBS_ARRAY_INDEX} -eq 1 ]; then
    rm -f driver_logfile.txt
    ./driver.sh ${PBS_ARRAY_INDEX} >> driver_logfile.txt
else
    ./driver.sh ${PBS_ARRAY_INDEX}
fi
