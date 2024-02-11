import sys
import re
import os
import numpy as np
import netCDF4 as nc

################### SCRIPT PARAMETERS ###################

paramlist = ["autotroph_settings(1)%kDOP"]

# The "mode" parameter has three options, which control how the parameters
# are recombined:
#     1. "resample," in which the new parameter for each member is
#        a random sample from the 12 latent parameters corresponding
#        to that member.
#     2. "year_avg," in which the new parameter for each member is
#        the average of its 12 latent parameters.
#     3. "ens_avg," in which all (12 * ens_size) parameters are averaged
#        and then perturbed with noise to produce a new parameter cycle.

mode = "ens_avg"

perturb_size = 3.0      # standard deviation of parameter perturbations
                        # in log-space, for when mode == "ens_avg."

def getvalue(param_array):
    return np.mean(param_array)

################### MAIN PROGRAM ########################

ens_path = sys.argv[1]
ens_size = int(sys.argv[2])
rng_seed = int(sys.argv[3])

num_params = len(paramlist)

rng = np.random.default_rng(seed = rng_seed)

marbl_tmp = ens_size*[None]
marbl_out = ens_size*[None]
dart_in   = np.zeros((ens_size, 12, num_params))

output_params = np.zeros((ens_size, num_params))

# setting up input and output parameter text files, recording the parameters given by DART
for ens_index in range(ens_size):
    member_input = ens_path+"/member_"+("%04d" % (ens_index + 1))+"/INPUT"
    os.system("mv "+member_input+"/marbl_in "+member_input+"/marbl_in_tmp")
    
    marbl_tmp[ens_index] = open(member_input+"/marbl_in_tmp", "r")
    marbl_out[ens_index] = open(member_input+"/marbl_in", "w")

    for month_index in range(12):
        ncfile = nc.Dataset(ens_path+"/member_"+("%04d" % (ens_index + 1))+"/climatology/params_"+("%02d" % (month_index + 1))+".nc", "r")
        
        for param_index in range(num_params):
            pname = paramlist[param_index]
            dart_in[ens_index, month_index] = getvalue(ncfile[pname][:])
        
        ncfile.close()

# setting output parameter values
if(mode == "resample"):
    for ens_index in range(ens_size):
        for param_index in range(num_params):
            month_index = int(np.floor(12*rng.random()))
            output_params[ens_index, param_index] = dart_in[ens_index, month_index, param_index]

elif(mode == "year_avg"):
    for ens_index in range(ens_size):
        for param_index in range(num_params):
            output_params[ens_index, param_index] = np.mean(dart_in[ens_index, :, param_index])

elif(mode == "ens_avg"):
    for param_index in range(num_params):
        param_avg = np.mean(dart_in[:, :, param_index])

        for ens_index in range(ens_size):
            # generating a sample from the standard normal distribution
            # using the Box-Mueller transform. There's probably an easier
            # way to do this in Numpy but I'm too lazy to look it up...
            
            u = rng.random()
            t = rng.random()
            x = np.sqrt(-2*np.log(u))*np.cos(2*t*np.pi)

            # log-normal perturbation of the average parameter value
            output_params[ens_index, param_index] = param_avg*np.exp(perturb_size*x)
else:
    raise ValueError("unknown parameter recombination mode, '"+mode+"'")

# writing the parameters into MARBL-readable text files

pname_regex = re.compile(r'^[^\s]+') # regex to extract parameter names

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
                in_paramlist  = True
                marbl_out[ens_index].write(pname+" = "+str(output_params[ens_index, param_index])+"\n")
        
        if(not in_paramlist):
            marbl_out[ens_index].write(line)

for ens_index in range(ens_size):
    marbl_out[ens_index].close()
    marbl_tmp[ens_index].close()

    os.system("rm "+ens_path+"/member_"+("%04d" % (ens_index + 1))+"/INPUT/marbl_in_tmp")
