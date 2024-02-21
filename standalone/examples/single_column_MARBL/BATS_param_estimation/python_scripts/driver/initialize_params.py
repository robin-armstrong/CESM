import sys
import os
import re
import numpy as np
import netCDF4 as nc

################### SCRIPT PARAMETERS ###################

paramlist = ["autotroph_settings(2)%alphaPI_per_day"]

perturb_percentage = 0.3    # standard deviation of the Gaussian random variable
                            # which is used to create a multiplicative log-normal
                            # perturbation of the parameter values.

################### MAIN PROGRAM ########################

base_dir     = sys.argv[1]            # base parameter file that perturbations are applied to
ens_dir      = sys.argv[2]            # top level directory for ensemble members
ens_size     = int(sys.argv[3])
layer_file   = sys.argv[4]            # contains layer pseudo-depths for MARBL
rng_seed     = int(sys.argv[5])       # source of randomness for parameter perturbations

os.system("cp "+base_dir+"/INPUT/marbl_in "+ens_dir+"/marbl_in_tmp")
marbl_template = open(ens_dir+"/marbl_in_tmp", "r")

rng = np.random.default_rng(seed = rng_seed)

numlayers = len(open(layer_file, "r").read().split(','))

marbl_out = ens_size*[None]     # these are populated in the loop below
dart_out  = ens_size*[None]
ncparams  = ens_size*[None]

# initializing parameter files that are readable by MARBL and DART

for ens_index in range(ens_size):
    marbl_paramfile = ens_dir+"/member_"+("%04d" % (ens_index + 1))+"/INPUT/marbl_in"
    os.system("rm -f "+marbl_paramfile)
    marbl_out[ens_index] = open(marbl_paramfile, "w")

    dart_dir = ens_dir+"/member_"+("%04d" % (ens_index + 1))+"/climatology"
    os.system("rm -f "+dart_dir+"/params_*")

    dart_out[ens_index] = 12*[None]
    ncparams[ens_index] = 12*[None]

    # each ensemble member gets 12 (initially) identical copies of the parameter list
    for month in range(12):
        dart_out[ens_index][month] = nc.Dataset(dart_dir+"/params_"+("%02d" % (month + 1))+".nc", "w")

        layer      = dart_out[ens_index][month].createDimension("Layer", size = numlayers)
        timedim    = dart_out[ens_index][month].createDimension("Month", size = 1)
        timevar    = dart_out[ens_index][month].createVariable("Month", 'i8', ("Month",))
        timevar[0] = 1

        ncparams[ens_index][month] = len(paramlist)*[None]

        for param_index in range(len(paramlist)):
            ncparams[ens_index][month][param_index] = dart_out[ens_index][month].createVariable(paramlist[param_index], 'f8', ("Layer",))

# regular expressions to extract parameter name and value from text
pname_regex = re.compile(r'^[^\s]+')
pval_regex  = re.compile(r'[^\s]+$')

for line in marbl_template.readlines():
    pname_array = re.findall(pname_regex, line)

    if(len(pname_array) == 0):  # handles empty lines
        for ens_index in range(ens_size):
            marbl_out[ens_index].write("\n")
        
        continue
    
    pname        = pname_array[0]
    in_paramlist = False
    
    for param_index in range(len(paramlist)):
        if(pname == paramlist[param_index]):
            in_paramlist = True
            pval_array   = re.findall(pval_regex, line)
            pval         = float(pval_array[0])
            
            # Writing the parameter into MARBL and DART parameter files,
            # with perturbations if this is the first assimilation cycle.
            
            for ens_index in range(ens_size):
                # generating a sample from the standard normal distribution
                t1 = rng.random()
                t2 = rng.random()
                x  = np.sqrt(-2*np.log(t1))*np.cos(2*np.pi*t2)

                # applying a log-normal multiplicative perturbation
                pval *= np.exp(perturb_percentage*x)

                marbl_out[ens_index].write(pname + " = " + str(pval) + "\n")

                for month in range(12):
                    ncparams[ens_index][month][param_index][:] = pval*np.ones(numlayers)
    
    if(not in_paramlist):
        for ens_index in range(ens_size):
            marbl_out[ens_index].write(line)

marbl_template.close()
os.system("rm "+ens_dir+"/marbl_in_tmp")

for ens_index in range(ens_size):
    marbl_out[ens_index].close()
    
    for month in range(12):
        dart_out[ens_index][month].close()
