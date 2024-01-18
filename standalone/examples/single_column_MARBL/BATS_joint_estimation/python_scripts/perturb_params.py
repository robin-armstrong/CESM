import sys
import re
import numpy as np

################### SCRIPT PARAMETERS ###################

paramlist = ["autotroph_settings(1)%kDOP"]

perturb_percentage = 0.3    # standard deviation of the Gaussian random variable
                            # which is used to create a multiplicative log-normal
                            # perturbation of the parameter values.

################### MAIN PROGRAM ########################

marbl_in  = open(sys.argv[1], "r")
rng_seed  = sys.argv[2]
marbl_out = open(sys.argv[3], "w")

np.random.randn(int(rng_seed))

# regular expressions to extract parameter name and value from text
pname_regex = re.compile(r'^[^\s]+')
pval_regex  = re.compile(r'[^\s]+$')

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
            pval_array   = re.findall(pval_regex, line)
            pval         = float(pval_array[0])

            # applying a log-normal multiplicative perturbation
            pval *= np.exp(perturb_percentage*np.random.randn())
            marbl_out.write(pname + " = " + str(pval) + "\n")
    
    if(not in_paramlist):
        marbl_out.write(line)

marbl_in.close()
marbl_out.close()
