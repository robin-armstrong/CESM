import sys
import numpy as np
import netCDF4 as nc

################### SCRIPT PARAMETERS ###################

# names of the variables which will be recorded in the climatology (as they appear in prog_file)
variable_keys = ['PO4', 'NO3', 'SiO3', 'Fe', 'O2', 'DIC', 'ALK', 'DOC', 'DON', 'DOP', 'microzooC', 'mesozooC']

################### MAIN PROGRAM ########################

int_years   = round(float(sys.argv[1])) # number years that MARBL has been integrated through before running this script
prog_file   = sys.argv[2]               # MOM6 diagnostic file which records time-series for all MARBL variables with daily resolution
clim_dir    = sys.argv[3]               # directory to write daily climatologies into
min_depth   = float(sys.argv[4])        
max_depth   = float(sys.argv[5])
clim_layers = round(float(sys.argv[6]))

# depths (in meters) at which climatological averages will be recorded
clim_depths = np.exp(np.linspace(np.log(min_depth), np.log(max_depth), clim_layers))

prog        = nc.Dataset(prog_file, "r")
prog_layers = len(prog["zl"])

clim = 365*[None]      # array of netCDF files containing daily climatologies, populated below

# initializing the climatology records
for day in range(365):
    clim[day] = nc.Dataset(clim_dir+"/clim_"+("%03d" % day)+".nc", "a")
    clim[day].createDimension("Time")
    clim[day].createDimension("Layer")

    day_var             = clim[day].createVariable("Time", "int", ("Time",))
    day_var.long_name   = "Day within the climatological year."
    samples             = clim[day].createVariable("samples", "int", ("Time",))
    samples.long_name   = "Number of samples used to create this climatology."
    depth_var           = clim[day].createVariable("Layer", "double", ("Layer",))
    depth_var.long_name = "Depth of a layer (at its center) within the ocean column."
    depth_var.units     = "meters"

    clim[day]["Time"][0]              = day
    clim[day]["Layer"][0:clim_layers] = clim_depths
    clim[day]["samples"][0]           = 0

    for var in variable_keys:
        marbl_var          = clim[day].createVariable("clim_"+var, "double", ("Layer",))
        marbl_var.longname = "Climatological depth profile for "+var+"."

        clim[day]["clim_"+var][0:clim_layers] = np.zeros(clim_layers)

# averaging over the MARBL integration to obtain the climatology

for day_raw in range(int_years*365):
    day = day_raw % 365

    marbl_depths    = np.zeros(prog_layers)
    marbl_depths[0] = .5*prog["h"][day_raw, 0,  0, 0]
    
    for layer in range(0, prog_layers - 1):
        marbl_depths[layer + 1] = marbl_depths[layer] + .5*(prog["h"][day_raw, layer,  0, 0] + prog["h"][day_raw, layer + 1,  0, 0])

    N_prev = float(clim[day]["samples"][0])

    for var in variable_keys:
        prog_vals = prog[var][day_raw, :, 0, 0]
        interp    = np.interp(clim_depths, marbl_depths, prog_vals)
        clim_prev = np.array(clim[day]["clim_"+var][:])

        clim[day]["clim_"+var][:] = (N_prev*clim_prev + interp)/(N_prev + 1)
    
    clim[day]["samples"][0] = N_prev + 1
    
for day in range(365):
    clim[day].close()
