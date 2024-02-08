import numpy as np
import netCDF4 as nc
import matplotlib.pyplot as plt

#################################################################
####################### SCRIPT PARAMETERS #######################
#################################################################

# names of the observation variables as they appear in the BATS
# data file, and in MARBL restart files.
varnames_bats = ["O2", "CO2", "Alk", "NO31", "PO41", "Si1"]
varnames_marbl = ["O2", "DIC", "ALK", "NO3", "PO4", "SiO3"]

#################################################################
####################### MAIN PROGRAM ############################
#################################################################

num_cycles     = int(sys.argv[1])
ens_size       = int(sys.argv[2])
ens_dir        = sys.argv[3]
bats_clim_path = sys.argv[4]

# BATS empirical climatology
bats_clim = nc.Dataset(bats_clim_path, "r")

numvars    = len(varnames_bats)
num_layers = len(bats_clim["depth"])

for cycle_index in range(num_cycles):
    # array of MARBL-produced climatology files, populated below
    marbl_clim = ens_size*[None]

    for ens_index in range(ens_size):
        marbl_clim[ens_index] = 12*[None]

        for month_index in range(12):
            marbl_clim[ens_index][month_index] = nc.Dataset(ens_dir+"/member_"+("%04d" % (ens_index + 1))+"/climatology/clim_"+("%02d" % (month_index + 1))+".nc", "r")
    
    for month_index in range(12):
        