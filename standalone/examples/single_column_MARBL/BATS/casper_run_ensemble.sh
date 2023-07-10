#PBS -N marblmom6_1d_integration
#PBS -A p93300012
#PBS -l walltime=00:02:00
#PBS -q casper
#PBS -j oe
#PBS -k oe
#PBS -m n
#PBS -l select=1:ncpus=30:mpiprocs=30

./marblmom6_1d_integration
