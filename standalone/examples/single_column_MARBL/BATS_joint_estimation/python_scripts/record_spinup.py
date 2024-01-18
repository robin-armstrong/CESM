import sys
import netCDF4 as nc

bgc_var = sys.argv[1]
year    = round(float(sys.argv[2]))
sample  = round(float(sys.argv[3]))
state   = nc.Dataset(sys.argv[4], "r")
record  = nc.Dataset(sys.argv[5], "a")

bgcvalue  = state[bgc_var][0, 0, 0, 0]

if((year == 1) and (sample == 1)):
    time = record.createDimension("Time")
    bgcrecord = record.createVariable(bgc_var+"_average", "double", ("Time",))
    bgcrecord.long_name = "Average value of "+bgc_var+" in a given year of the spin-up"

if(sample == 1):
    record[bgc_var+"_average"][year - 1] = bgcvalue
else:
    record[bgc_var+"_average"][year - 1] = (bgcvalue + (sample - 1)*record[bgc_var+"_average"][year - 1])/sample
    