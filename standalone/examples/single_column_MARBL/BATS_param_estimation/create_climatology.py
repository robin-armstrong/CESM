import sys
import os
import numpy as np
import netCDF4 as nc

################### SCRIPT PARAMETERS ###################

# names of the variables which will be recorded in the climatology (as they appear in prog_file)
variable_keys = ['PO4', 'NO3', 'SiO3', 'Fe', 'O2', 'DIC', 'ALK', 'DOC', 'DON', 'DOP', 'microzooC', 'mesozooC']

# depths (in meters) at which climatological averages will be recorded
clim_depths = np.exp(np.linspace(np.log(1), np.log(4500), 20))

################### MAIN PROGRAM ########################

int_years = round(float(sys.argv[1]))     # number years that MARBL has been integrated through before running this script
prog_file = sys.argv[2]                   # MOM6 diagnostic file which records time-series for all MARBL variables with daily resolution
clim_dir  = sys.argv[3]                   # directory to write daily climatologies into

prog        = nc.Dataset(prog_file, "r")
prog_layers = len(prog["zl"])
clim_layers = len(clim_depths)

clim = 365*[None]      # array of netCDF files containing daily climatologies, populated below

for day in range(365):
    clim[day] = nc.Dataset(clim_dir+"/clim_"+("%03d" % (day + 1))+".nc", "a")

# initializing the climatology records, if necessary
for day in range(365):
    clim[day].createDimension("Time")
    clim[day].createDimension("Depth")

    day_var             = clim[day].createVariable("day", "int", ("Time",))
    day_var.long_name   = "Day within the climatological year."
    depth_var           = clim[day].createVariable("depth", "double", ("Depth",))
    depth_var.long_name = "Depth within the ocean column."

    clim[day]["day"][0] = day + 1
    clim[day]["depth"][0:clim_layers] = clim_depths

    for var in variable_keys:
        marbl_var          = clim[day].createVariable("clim_"+var, "double", ("Depth",))
        marbl_var.longname = "Climatological depth profile for "+var+"."
        samples            = clim[day].createVariable("samples_"+var, "int", ("Depth",))

        clim[day]["clim_"+var][0:clim_layers] = np.zeros(clim_layers)
        clim[day]["samples_"+var][0:clim_layers] = np.zeros(clim_layers, dtype = "int")
    
    clim[day].note = "For variables of the form 'samples_XXX', a value of '0' indicates that no samples were available for the given layer, in which case the climatological value shown for this layer is a linear interpolation from the nearest layers that have samples."

# averaging over the MARBL integration to obtain the climatology
for raw_day in range(int_years*365):
    day = raw_day % 365

    marbl_depths    = np.zeros(prog_layers)
    marbl_depths[0] = .5*prog["h"][day, 0,  0, 0]
    
    for z in range(0, prog_layers - 1):
        marbl_depths[z + 1] = marbl_depths[z] + .5*(prog["h"][day, z,  0, 0] + prog["h"][day, z + 1,  0, 0])

    for var in variable_keys:
        for layer in range(prog_layers):
            # value to be added into the climatological average
            prog_val = prog[var][day, layer, 0, 0]
            
            # finding the climatology grid point whose depth is closest to prog_depth
            clim_layer = np.argmin(np.abs(clim_depths - marbl_depths[layer]*np.ones(clim_layers)))

            # adding the new value into the climatology
            N_prev    = clim[day]["samples_"+var][clim_layer]
            clim_prev = clim[day]["clim_"+var][clim_layer]

            clim[day]["clim_"+var][clim_layer]     = (N_prev*clim_prev + prog_val)/(N_prev + 1)
            clim[day]["samples_"+var][clim_layer] += 1
        
        # using linear interpolation to fill depth bins that have no samples

        sampled_layers   = (np.array(clim[day]["samples_"+var]) > 0)
        unsampled_layers = (np.array(clim[day]["samples_"+var]) == 0)

        clim[day]["clim_"+var][unsampled_layers] = np.interp(clim_depths[unsampled_layers], clim_depths[sampled_layers], clim[day]["clim_"+var][sampled_layers])
    
    clim[day].close()
