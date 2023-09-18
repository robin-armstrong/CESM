import sys
import re
import numpy as np
import netCDF4 as nc

################### SCRIPT PARAMETERS ###################

paramlist = ["autotroph_settings(1)%kCO2",
             "autotroph_settings(1)%kDOP",
             "autotroph_settings(1)%kFe",
             "autotroph_settings(1)%kNH4",
             "autotroph_settings(1)%kNO3",
             "autotroph_settings(1)%kPO4",
             "autotroph_settings(1)%kSiO3",
             "autotroph_settings(2)%kCO2",
             "autotroph_settings(2)%kDOP",
             "autotroph_settings(2)%kFe",
             "autotroph_settings(2)%kNH4",
             "autotroph_settings(2)%kNO3",
             "autotroph_settings(2)%kPO4",
             "autotroph_settings(2)%kSiO3",
             "autotroph_settings(3)%kCO2",
             "autotroph_settings(3)%kDOP",
             "autotroph_settings(3)%kFe",
             "autotroph_settings(3)%kNH4",
             "autotroph_settings(3)%kNO3",
             "autotroph_settings(3)%kPO4",
             "autotroph_settings(3)%kSiO3",
             "autotroph_settings(4)%kCO2",
             "autotroph_settings(4)%kDOP",
             "autotroph_settings(4)%kFe",
             "autotroph_settings(4)%kNH4",
             "autotroph_settings(4)%kNO3",
             "autotroph_settings(4)%kPO4",
             "autotroph_settings(4)%kSiO3"]
             
numlayers = 65

################### MAIN PROGRAM ########################

marbl_in  = open(sys.argv[1], "r")
timestamp = sys.argv[2]
dart_out  = nc.Dataset(sys.argv[3], "w")

# setting up the NetCDF file
layer      = dart_out.createDimension("Layer", size = numlayers)
timedim    = dart_out.createDimension("Time", size = 1)
timevar    = dart_out.createVariable("Time", 'i8', ("Time",))
timevar[0] = timestamp

ncparams   = [None]*len(paramlist)

for i in range(len(paramlist)):
    ncparams[i] = dart_out.createVariable(paramlist[i], 'f8', ("Layer",))

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
dart_out.close()
