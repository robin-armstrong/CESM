import os
import sys
import numpy as np
import netCDF4 as nc

################### SCRIPT PARAMETERS ###################

paramlist = ["autotroph_settings(1)%kDOP",
             "autotroph_settings(1)%kNH4"]

################### MAIN PROGRAM ########################

clim_dir   = sys.argv[1]
layer_file = sys.argv[2]

numlayers = len(open(layer_file, "r").read().split(','))

analysis_params = nc.Dataset(clim_dir+"/analysis_params.nc", "w")

# setting up the analysis parameter NetCDF file

layer = analysis_params.createDimension("Layer", size = numlayers)

for i in range(len(paramlist)):
    analysis_params.createVariable(paramlist[i], 'f8', ("Layer",))
    analysis_params[paramlist[i]][:] = np.zeros(numlayers)

for month in range(12):
    latent_params = nc.Dataset(clim_dir+"/params_"+("%02d" % (month + 1))+".nc")

    for i in range(len(paramlist)):
        analysis_params[paramlist[i]][:] += latent_params[paramlist[i]][:]/12
    
    latent_params.close()

analysis_params.close()
