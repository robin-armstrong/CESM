import sys
import numpy as np
import netCDF4 as nc

################### SCRIPT PARAMETERS ###################

# names of the variables which will be recorded in the climatology (as they appear in prog_file)
variable_keys = ['PO4', 'NO3', 'SiO3', 'Fe', 'O2', 'DIC', 'ALK', 'DOC', 'DON', 'DOP', 'microzooC', 'mesozooC']

################### MAIN PROGRAM ########################

ens_dir    = sys.argv[1]
ens_size   = int(sys.argv[2])
layer_file = sys.argv[3]
clim_dir   = sys.argv[4]

# depths (in meters) at which average climatological values will be recorded
clim_depths = np.array(open(layer_file, "r").read().split(','))
clim_layers = len(clim_depths)

# creating the climatology records
for month in range(12):
    avg_clim = nc.Dataset(clim_dir+"/avg_clim_"+("%02d" % (month + 1))+".nc", "w")
    avg_clim.createDimension("Month")
    avg_clim.createDimension("Layer")

    month_var           = avg_clim.createVariable("Month", "int", ("Month",))
    month_var.long_name = "Month within the climatological year."
    samples             = avg_clim.createVariable("samples", "int", ("Month",))
    samples.long_name   = "Number of samples used to create this climatology."
    depth_var           = avg_clim.createVariable("Layer", "double", ("Layer",))
    depth_var.long_name = "Depth of a layer (at its center) within the ocean column."
    depth_var.units     = "meters"

    avg_clim["Month"][0]             = month + 1
    avg_clim["Layer"][0:clim_layers] = clim_depths
    avg_clim["samples"][0]           = 0

    for var in variable_keys:
        marbl_val          = avg_clim.createVariable("clim_"+var, "double", ("Layer",))
        marbl_val.longname = "Depth profile of climatological means for "+var+" (ensemble average)."

        marbl_spread          = avg_clim.createVariable("ens_stddev_"+var, "double", ("Layer",))
        marbl_spread.longname = "Depth profile of ensemble standard deviations for "+var+" climatological means."

        avg_clim["clim_"+var][0:clim_layers] = np.zeros(clim_layers)
        avg_clim["ens_stddev_"+var][0:clim_layers] = np.zeros(clim_layers)
    
    # averaging over the ensemble
    for ens_index in range(ens_size):
        ens_data = nc.Dataset(ens_dir+"/member_"+("%04d" % (ens_index + 1))+"/climatology/clim_"+("%02d" % (month + 1))+".nc", "r")

        for var in variable_keys:
            avg_clim["clim_"+var][:] += ens_data["clim_"+var][:]/ens_size

            # For now, recording the average squared value in the "standard deviation" field.
            # This is converted to a true standard deviation at the end of the script.
            avg_clim["ens_stddev_"+var][:] += np.array(ens_data["clim_"+var][:])**2/ens_size
        
        ens_data.close()
    
    for var in variable_keys:
        ens_variance               = np.array(avg_clim["ens_stddev_"+var][:]) - np.array(avg_clim["clim_"+var][:])**2
        avg_clim["ens_stddev_"+var][:] = np.sqrt(np.maximum(ens_variance, 0.))
    
    avg_clim.close()
