import os
import sys
import numpy as np
import netCDF4 as nc

################### SCRIPT PARAMETERS ###################

paramlist = ["autotroph_settings(1)%kDOP",
             "autotroph_settings(1)%kNH4"]

################### MAIN PROGRAM ########################

clim_dir  = sys.argv[1]
numlayers = round(float(sys.argv[2]))

forecast_params = nc.Dataset(clim_dir+"/forecast_params.nc", "r")
analysis_params = nc.Dataset(clim_dir+"/analysis_params.nc", "w")

# setting up the analysis parameter NetCDF file

layer = analysis_params.createDimension("Layer", size = numlayers)

for i in range(len(paramlist)):
    analysis_params.createVariable(paramlist[i], 'f8', ("Layer",))
    analysis_params[paramlist[i]][:] = forecast_params[paramlist[i]][:]

for day in range(365):
    latent_params = nc.Dataset(clim_dir+"/params_"+("%03d" % day)+".nc")

    for i in range(len(paramlist)):
        analysis_params[paramlist[i]][:] += latent_params[paramlist[i]][:] - forecast_params[paramlist[i]][:]
    
    analysis_params[paramlist[i]][:] = np.maximum(analysis_params[paramlist[i]][:], 0.)

    latent_params.close()

forecast_params.close()
analysis_params.close()
