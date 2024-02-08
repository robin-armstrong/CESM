import sys
import numpy as np
import netCDF4 as nc

################### SCRIPT PARAMETERS ###################

# names of the variables which will be recorded in the climatology (as they appear in prog_file)
variable_keys = ['PO4', 'NO3', 'SiO3', 'Fe', 'O2', 'DIC', 'ALK', 'DOC', 'DON', 'DOP', 'microzooC', 'mesozooC']

################### MAIN PROGRAM ########################

int_years  = round(float(sys.argv[1])) # number years that MARBL has been integrated through before running this script
prog_file  = sys.argv[2]               # MOM6 diagnostic file which records time-series for all MARBL variables with daily resolution
clim_dir   = sys.argv[3]               # directory to write daily climatologies into
layer_file = sys.argv[4]

# depths (in meters) at which climatological averages will be recorded
clim_depths = np.array(open(layer_file, "r").read().split(','))
clim_layers = len(clim_depths)

prog = nc.Dataset(prog_file, "r")
clim = 12*[None]    # array of netCDF files containing monthly climatologies, populated below

# initializing the climatology records
for month in range(12):
    clim[month] = nc.Dataset(clim_dir+"/clim_"+("%02d" % (month + 1))+".nc", "a")
    clim[month].createDimension("Month")
    clim[month].createDimension("Layer")

    month_var           = clim[month].createVariable("Month", "int", ("Month",))
    month_var.long_name = "Month within the climatological year."
    samples             = clim[month].createVariable("samples", "int", ("Month",))
    samples.long_name   = "Number of samples used to create this climatology."
    depth_var           = clim[month].createVariable("Layer", "double", ("Layer",))
    depth_var.long_name = "Depth of a layer (at its center) within the ocean column."
    depth_var.units     = "meters"

    clim[month]["Month"][0]             = month + 1
    clim[month]["Layer"][0:clim_layers] = clim_depths
    clim[month]["samples"][0]           = 0

    for var in variable_keys:
        marbl_var          = clim[month].createVariable("clim_"+var, "double", ("Layer",))
        marbl_var.longname = "Climatological depth profile for "+var+"."

        clim[month]["clim_"+var][0:clim_layers] = np.zeros(clim_layers)

# averaging over the MARBL integration to obtain the climatology

for day in range(int_years*365):
    month  = int(np.floor(12*day/365)) % 12
    N_prev = float(clim[month]["samples"][0])

    for var in variable_keys:
        prog_vals = np.array(prog[var][day, :, 0, 0])
        clim_prev = np.array(clim[month]["clim_"+var][:])

        clim[month]["clim_"+var][:] = (N_prev*clim_prev + prog_vals)/(N_prev + 1)
    
    clim[month]["samples"][0] = N_prev + 1
    
for month in range(12):
    clim[month].close()
