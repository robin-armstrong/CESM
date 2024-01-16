import sys
import os
import re
import numpy as np
import netCDF4 as nc

################### SCRIPT PARAMETERS ###################

paramlist = ["autotroph_settings(1)%kDOP",
             "autotroph_settings(1)%kNH4"]
             
################### MAIN PROGRAM ########################

marbl_in  = open(sys.argv[1], "r")
out_dir   = sys.argv[2]
numlayers = round(float(sys.argv[3]))

# This script will produce 365 separate parameter netCDF files, one for each day of the
# climatological year. This will simplify the data assimilation process, and eventually,
# the parameter innovations for each day will be combined into a single set of analysis
# parameters. The script begins by populating the netCDF file for day 0, and then copies
# and modifies it appropriately for the remaining days of the year.

dart_out    = 365*[None]
dart_out[0] = nc.Dataset(out_dir+"/params_000.nc", "w")

# setting up the NetCDF file
layer      = dart_out[0].createDimension("Layer", size = numlayers)
timedim    = dart_out[0].createDimension("Time", size = 1)
timevar    = dart_out[0].createVariable("Time", 'i8', ("Time",))
timevar[0] = 0

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
for day in range(1, 365):
    os.system("cp "+out_dir+"/params_000.nc "+out_dir+"/params_"+("%03d" % day)+".nc")
    
    dart_out[day]            = nc.Dataset(out_dir+"/params_"+("%03d" % day)+".nc", "a")
    dart_out[day]["Time"][0] = day
    dart_out[day].close()
