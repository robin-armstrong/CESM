import sys
import re
import numpy as np
import netCDF4 as nc

################### SCRIPT PARAMETERS ###################

paramlist = ["autotroph_settings(1)%kDOP",
             "autotroph_settings(1)%kNH4"]

################### MAIN PROGRAM ########################

mode     = sys.argv[1]
ens_path = sys.argv[2]
ens_size = round(float(sys.argv[3]))
filename = sys.argv[4]

record   = nc.Dataset(filename, "a")

if(mode == "init"):
    record.createDimension("AssimilationCycle")
    record.createDimension("EnsembleMemberIndex")

    for param in paramlist:
        param_value            = record.createVariable(param, "double", ("AssimilationCycle", "EnsembleMemberIndex",))
        param_mean             = record.createVariable("average_"+param, "double", ("AssimilationCycle",))
        param_mean.long_name   = "Ensemble mean for parameter "+param
        param_stddev           = record.createVariable("stddev_"+param, "double", ("AssimilationCycle",))
        param_stddev.long_name = "Ensemble standard deviation for parameter "+param

elif(mode == "record"):
    cycle_index = record["average_"+paramlist[0]].shape[0]

    for param in paramlist:
        mean        = 0.
        sq_mean     = 0.

        pname_regex = re.compile(r'^[^\s]+')
        pval_regex  = re.compile(r'[^\s]+$')

        for member_id in range(1, ens_size + 1):
            pfile    = ens_path+"/member_"+("{:04d}".format(member_id))+"/INPUT/marbl_in"
            marbl_in = open(pfile, "r")

            for line in marbl_in.readlines():
                pname_array = re.findall(pname_regex, line)
                
                if(len(pname_array) == 0):  # handles empty lines
                    continue
                
                pname = pname_array[0]

                if(pname != param):
                    continue
                
                pval_array = re.findall(pval_regex, line)
                pval       = float(pval_array[0])

                record[param][cycle_index, member_id - 1] = pval

                mean      += pval
                sq_mean   += pval**2
        
        mean    /= ens_size
        sq_mean /= ens_size
        
        record["average_"+param][cycle_index] = mean
        record["stddev_"+param][cycle_index]  = np.sqrt(sq_mean - mean**2)
else:
    print("Unrecognized mode option.")

record.close()
