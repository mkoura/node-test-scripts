#!/bin/bash

root=e2e-tests-directory
output_log_filename=output.log
output_log_filepath=$root/$output_log_filename

tests_results_filename=tests-results.txt
tests_results_filepath=$root/$tests_results_filename

tests_dir_path=python_scripts/e2e_scenarios

echo "======================== test-runner.sh ========================" 2>&1 | tee -a $output_log_filepath

# List of test scripts to run:


tests=$(ls -1 $tests_dir_path | grep test.py)

for test in $tests; do
    ./$tests_dir_path/$test 2>&1 | tee -a $output_log_filepath
    echo "$test:${PIPESTATUS[0]}" >> $tests_results_filepath
done

#tmux kill-server
