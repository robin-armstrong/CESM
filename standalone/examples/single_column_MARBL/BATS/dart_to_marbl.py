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
