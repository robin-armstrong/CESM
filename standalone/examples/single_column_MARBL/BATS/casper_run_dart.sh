#PBS -N marblmom6_dart_assimilation
#PBS -A p93300012
#PBS -l walltime=00:02:00
#PBS -q casper
#PBS -j oe
#PBS -k oe
#PBS -m n
#PBS -l select=1:ncpus=1:mpiprocs=1

./marblmom6_dart_assimilation
