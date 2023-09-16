import sys
import re
import numpy as np
import netCDF4 as nc

################### SCRIPT PARAMETERS ###################

paramlist = ["caco3_bury_thres_depth", "f_graze_CaCO3_remin", "parm_Lig_degrade_rate0"]
numlayers = 65

def getvalue(param_array):
    return param_array[0]

################### MAIN PROGRAM ########################

dart_in        = sys.argv[1]    # path to the parameter list NetCDF file
marbl_out      = sys.argv[2]    # path for the text file to be outputted
marbl_template = sys.argv[3]    # template for the parameter text file

paramfile    = open(marbl_out, "w")
templatefile = open(marbl_template, "r")
ncfile       = nc.Dataset(dart_in, "r")

# regular expressions to extract parameter name from text
pname_regex = re.compile(r'^[^\s]+')

# populating the parameter list
for line in templatefile.readlines():
    pname_array = re.findall(pname_regex, line)

    if(len(pname_array) == 0):  # handles empty lines
        paramfile.write("\n")
        continue
    
    pname      = pname_array[0]
    writeparam = False
    
    for i in range(len(paramlist)):
        if(pname == paramlist[i]):
            writeparam = True
            paramfile.write(pname + " = " + str(getvalue(ncfile[pname][:])) + "\n")
    
    if(not writeparam):
        paramfile.write(line)

paramfile.close()
templatefile.close()
ncfile.close()
