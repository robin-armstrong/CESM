import sys
import re
import numpy as np

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

################### MAIN PROGRAM ########################

marbl_in  = open(sys.argv[1], "r")
rng_seed  = sys.argv[2]
marbl_out = open(sys.argv[3], "w")

np.random.randn(rng_seed)

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
            pval *= np.exp(.01*pval*np.random.randn())
            marbl_out.write(pname + " = " + str(pval) + "\n")
    
    if(not in_paramlist):
        marbl_out.write(line)

marbl_in.close()
marbl_out.close()
