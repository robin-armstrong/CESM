echo "deleting old output files..."

rm test_output/*

echo "configuring the DART namelist file..."

sed -i "s%template_file = .*%template_file = 'testing/test_ensemble/input/member_0001/MOM.res.nc',%" ../input.nml
sed -i "s%input_state_files = .*%input_state_files = '',%" ../input.nml
sed -i "s%input_state_file_list = .*%input_state_file_list = 'testing/test_ensemble/input/ensemble_members_in.txt',%" ../input.nml
sed -i "s%output_state_files = .*%output_state_files = '',%" ../input.nml
sed -i "s%output_state_file_list = .*%output_state_file_list = 'testing/test_ensemble/output/ensemble_members_out.txt',%" ../input.nml
sed -i "s/ens_size = .*/ens_size = 30,/" ../input.nml
sed -i "s/num_output_state_members = .*/num_output_state_members = 30,/" ../input.nml
sed -i "s/num_output_obs_members = .*/num_output_obs_members = 30,/" ../input.nml
sed -i "s/num_output_obs_members = .*/num_output_obs_members = 30,/" ../input.nml
sed -i "s/perturb_from_single_instance = .*/perturb_from_single_instance = .false.,/" ../input.nml
sed -i "s%obs_sequence_in_name.*%obs_sequence_in_name = 'testing/test_obs/obs_seq.out',%" ../input.nml
sed -i "s%obs_sequence_out_name.*%obs_sequence_out_name = 'testing/test_output/obs_seq.final',%" ../input.nml
sed -i "s/write_all_stages_at_end = .*/write_all_stages_at_end = .true.,/" ../input.nml

echo "running DART..."
back=$(pwd)
cd ..

echo ""
echo "================================================================"
echo "============================= DART ============================="
echo "================================================================"
echo ""

./filter

mv analysis* testing/test_output
mv preassim* testing/test_output
mv dart_log.out testing/test_output
mv output*.nc testing/test_output

cd ${back}
