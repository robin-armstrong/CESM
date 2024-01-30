import sys
import os
import re
import numpy as np
import netCDF4 as nc

################### SCRIPT PARAMETERS ###################

paramlist = ["autotroph_settings(1)%kDOP",
             "autotroph_settings(1)%kNH4"]
             
################### MAIN PROGRAM ########################

marbl_in   = open(sys.argv[1], "r")
out_dir    = sys.argv[2]
layer_file = sys.argv[3]

numlayers = len(open(layer_file, "r").read().split(','))

# This script will produce 365 separate parameter netCDF files, one for each month of the
# climatological year. This will simplify the data assimilation process, and eventually,
# the parameter innovations for each day will be combined into a single set of analysis
# parameters. The script begins by populating the netCDF file for month 1, and then copies
# and modifies it appropriately for the remaining months of the year.

dart_out    = 12*[None]
dart_out[0] = nc.Dataset(out_dir+"/params_01.nc", "w")

# setting up the NetCDF file
layer      = dart_out[0].createDimension("Layer", size = numlayers)
timedim    = dart_out[0].createDimension("Month", size = 1)
timevar    = dart_out[0].createVariable("Month", 'i8', ("Month",))
timevar[0] = 1

ncparams   = [None]*len(paramlist)

for i in range(len(paramlist)):
    ncparams[i] = dart_out[0].createVariable(paramlist[i], 'f8', ("Layer",))

# regular expressions to extract parameter name and value from text
pname_regex = re.compile(r'^[^\s]+')
pval_regex  = re.compile(r'[^\s]+$')

# populating the NetCDF file
for line in marbl_in.readlines():
    pname_array = re.findall(pname_regex, line)

    if(len(pname_array) == 0):  # skips empty lines
        continue
    
    pname = pname_array[0]
    
    for i in range(len(paramlist)):
        if(pname == paramlist[i]):
            pval_array = re.findall(pval_regex, line)
            pval       = float(pval_array[0])
            
            ncparams[i][:] = pval*np.ones(numlayers)

marbl_in.close()
dart_out[0].close()

# creating the remaining parameter files
for month in range(1, 12):
    os.system("cp "+out_dir+"/params_01.nc "+out_dir+"/params_"+("%02d" % (month + 1))+".nc")
    
    dart_out[month]            = nc.Dataset(out_dir+"/params_"+("%02d" % (month + 1))+".nc", "a")
    dart_out[month]["Month"][0] = month + 1
    dart_out[month].close()
