import sys
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

month_names = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]

#################################################################
####################### MAIN PROGRAM ############################
#################################################################

num_cycles     = int(sys.argv[1])   # number of iterations that MARBL-DART ran for
marbl_out_dir  = sys.argv[2]        # directory containing MARBL-DART output
bats_clim_path = sys.argv[3]        # path of the BATS empirical climatology file
diag_out_dir   = sys.argv[4]        # directory where the diagnostic plot will be saved

num_vars = len(varnames_bats)

# BATS empirical climatology
bats_clim   = nc.Dataset(bats_clim_path, "r")
bats_depths = np.array(bats_clim["Depth"])
bats_layers = len(bats_depths)

# array to store the data that will be plotted
avg_mismatch = np.zeros((num_vars, 12, bats_layers, num_cycles))

# measuring model-data mismatch across all iterations
for cycle in range(num_cycles):
    for month in range(12):
        # an average climatology from MARBL-DART
        marbl_clim   = nc.Dataset(marbl_out_dir+"/cycle_"+("%03d" % (cycle + 1))+"/average_climatologies/avg_clim_"+("%02d" % (month + 1))+".nc", "r")
        marbl_depths = np.array(marbl_clim["Layer"])
        marbl_layers = len(marbl_depths)

        for var_index in range(num_vars):
            bats_z      = 0     # index of the layer where average mismatch is being calculated (BATS grid)
            num_samples = 0     # number of MARBL grid points that have contributed to the current average

            for marbl_z in range(marbl_layers):
                if((bats_z < bats_layers - 1) and (marbl_depths[marbl_z] >= bats_depths[bats_z + 1])):
                    bats_z      += 1
                    num_samples  = 0
                
                marbl_val = marbl_clim["clim_"+varnames_marbl[var_index]][marbl_z]
                bats_val  = bats_clim[varnames_bats[var_index]+"_value"][month, bats_z]
                bats_err  = bats_clim[varnames_bats[var_index]+"_error_sd"][month, bats_z]
                
                old_avg = avg_mismatch[var_index, month, bats_z, cycle]
                new_avg = (num_samples*old_avg + (marbl_val - bats_val)/(bats_err*bats_val))/(num_samples + 1)

                avg_mismatch[var_index, month, bats_z, cycle] = new_avg
                
                num_samples += 1

plt.ioff()

for var_index in range(num_vars):
    fig = plt.figure(figsize = (14, 18))
    
    for month in range(12):
        tile = fig.add_subplot(4, 3, month + 1)
        tile.set_title(varnames_bats[var_index]+" Mismatch ("+month_names[month]+")")
        tile.imshow(avg_mismatch[var_index, month, :, :], aspect = num_cycles/bats_layers, cmap = "seismic", vmin = -0.2, vmax = 0.2)

    plt.savefig(diag_out_dir+"/"+varnames_bats[var_index]+"_err.pdf")
    plt.close(fig)
