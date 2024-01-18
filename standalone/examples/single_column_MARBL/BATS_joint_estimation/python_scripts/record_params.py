import sys
import re
import numpy as np
import netCDF4 as nc

################### SCRIPT PARAMETERS ###################

paramlist = ["autotroph_settings(1)%kDOP"]
ens_path  = "/glade/work/rarmstrong/cesm/cesm2_3_alpha12b+mom6_marbl/components/mom/standalone/examples/single_column_MARBL/BATS/ensemble"

################### MAIN PROGRAM ########################

mode     = sys.argv[1]
ens_size = round(float(sys.argv[2]))
filename = sys.argv[3]
day      = sys.argv[4]

record   = nc.Dataset(filename, "a")

if(mode == "init"):
    time              = record.createDimension("Time")
    day_var           = record.createVariable("day", "int", ("Time",))
    day_var.long_name = "Simulation time, in the DART calendar"

    for param in paramlist:
        param_mean             = record.createVariable("average_"+param, "double", ("Time",))
        param_mean.long_name   = "Ensemble mean for parameter "+param
        param_stddev           = record.createVariable("stddev_"+param, "double", ("Time",))
        param_stddev.long_name = "Ensemble standard deviation for parameter "+param

elif(mode == "record"):
    index = record["day"].shape[0]
    record["day"][index] = day

    for param in paramlist:
        mean    = 0.
        sq_mean = 0.

        pname_regex = re.compile(r'^[^\s]+')
        pval_regex  = re.compile(r'[^\s]+$')

        for member_id in range(1, ens_size + 1):
            pfile    = ens_path+"/member_"+("{:04d}".format(member_id))+"/marbl_in"
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
                mean      += pval
                sq_mean   += pval**2
        
        mean    /= ens_size
        sq_mean /= ens_size
        
        record["average_"+param][index] = mean
        record["stddev_"+param][index]     = np.sqrt(sq_mean - mean**2)
else:
    print("Unrecognized mode option.")

record.close()
