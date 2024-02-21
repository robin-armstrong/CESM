import sys
import re
import numpy as np
import netCDF4 as nc

################### SCRIPT PARAMETERS ###################

paramlist = ["autotroph_settings(2)%alphaPI_per_day"]

numlayers = 65

def getvalue(param_array):
    return np.mean(param_array[0])

################### MAIN PROGRAM ########################

dart_in   = nc.Dataset(sys.argv[1], "r")
marbl_in  = open(sys.argv[2], "r")
marbl_out = open(sys.argv[3], "w")

# regular expressions to extract parameter name from text
pname_regex = re.compile(r'^[^\s]+')

# populating the parameter list
for line in marbl_in.readlines():
    pname_array = re.findall(pname_regex, line)

    if(len(pname_array) == 0):  # handles empty lines
        marbl_out.write("\n")
        continue
    
    pname        = pname_array[0]
    in_paramlist = False
    
    for i in range(len(paramlist)):
        if(pname == paramlist[i]):
            in_paramlist = True
            marbl_out.write(pname + " = " + str(getvalue(dart_in[pname][:])) + "\n")
    
    if(not in_paramlist):
        marbl_out.write(line)

marbl_out.close()
marbl_in.close()
dart_in.close()
