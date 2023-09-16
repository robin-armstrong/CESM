import sys
import re
import numpy as np
import netCDF4 as nc

################### SCRIPT PARAMETERS ###################

paramlist = ["caco3_bury_thres_depth", "f_graze_CaCO3_remin", "parm_Lig_degrade_rate0"]
numlayers = 65

################### MAIN PROGRAM ########################

marbl_in = sys.argv[1]      # path to the parameter list text file
out_file = sys.argv[2]      # path for the netCDF file being created
timeval  = sys.argv[3]      # simulation time which the parameters correspond to

# setting up the NetCDF file
ncfile     = nc.Dataset(out_file, "w")
layer      = ncfile.createDimension("Layer", size = numlayers)
timedim    = ncfile.createDimension("Time", size = 1)
timevar    = ncfile.createVariable("Time", 'i8', ("Time",))
timevar[0] = timeval

ncparams   = [None]*len(paramlist)

for i in range(len(paramlist)):
    ncparams[i] = ncfile.createVariable(paramlist[i], 'f8', ("Layer",))

# opening the text file with parameter values
paramfile = open(marbl_in, "r")

# regular expressions to extract parameter name and value from text
pname_regex = re.compile(r'^[^\s]+')
pval_regex  = re.compile(r'[^\s]+$')

# populating the NetCDF file
for line in paramfile.readlines():
    pname_array = re.findall(pname_regex, line)

    if(len(pname_array) == 0):  # skips empty lines
        continue
    
    pname = pname_array[0]
    
    for i in range(len(paramlist)):
        if(pname == paramlist[i]):
            pval_array = re.findall(pval_regex, line)
            pval       = float(pval_array[0])
            
            ncparams[i][:] = pval*np.ones(numlayers)
