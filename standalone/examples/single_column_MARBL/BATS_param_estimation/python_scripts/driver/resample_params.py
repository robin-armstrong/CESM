import sys
import re
import os
import numpy as np
import netCDF4 as nc

################### SCRIPT PARAMETERS ###################

paramlist = ["autotroph_settings(1)%kDOP"]

def getvalue(param_array):
    return np.mean(param_array)

################### MAIN PROGRAM ########################

ens_path = sys.argv[1]
ens_size = int(sys.argv[2])
rng_seed = int(sys.argv[3])

rng = np.random.default_rng(seed = rng_seed)

marbl_tmp = ens_size*[None]
marbl_out = ens_size*[None]
dart_in   = [12*[None] for ens_index in range(ens_size)]

for ens_index in range(ens_size):
    member_input = ens_path+"/member_"+("%04d" % (ens_index + 1))+"/INPUT"
    os.system("mv "+member_input+"/marbl_in "+member_input+"/marbl_in_tmp")
    
    marbl_tmp[ens_index] = open(member_input+"/marbl_in_tmp", "r")
    marbl_out[ens_index] = open(member_input+"/marbl_in", "w")

    for month_index in range(12):
        dart_in[ens_index][month_index] = nc.Dataset(ens_path+"/member_"+("%04d" % (ens_index + 1))+"/climatology/params_"+("%02d" % (month_index + 1))+".nc", "r")

# regular expressions to extract parameter name from text
pname_regex = re.compile(r'^[^\s]+')

# populating the parameter lists

for ens_index in range(ens_size):
    for line in marbl_tmp[ens_index].readlines():
        pname_array = re.findall(pname_regex, line)

        if(len(pname_array) == 0):  # handles empty lines
            marbl_out[ens_index].write("\n")
            continue
        
        pname        = pname_array[0]
        in_paramlist = False
        
        for param_index in range(len(paramlist)):
            if(pname == paramlist[param_index]):
                in_paramlist = True
                
                month_index = int(np.floor(12*rng.random()))
                pval        = getvalue(dart_in[ens_index][month_index][pname][:])
                
                marbl_out[ens_index].write(pname+" = "+str(pval)+"\n")
        
        if(not in_paramlist):
            marbl_out[ens_index].write(line)

for ens_index in range(ens_size):
    marbl_out[ens_index].close()
    marbl_tmp[ens_index].close()

    os.system("rm "+ens_path+"/member_"+("%04d" % (ens_index + 1))+"/INPUT/marbl_in_tmp")

    for month_index in range(12):
        dart_in[ens_index][month_index].close()
