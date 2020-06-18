#!/bin/bash

echo "======================== test-runner.sh ========================" 2>&1 | tee -a output.log

# List of test scripts to run:

./e2e-automation-scripts/transaction-with-no-existing-input-address.sh 2>&1 | tee -a output.log
echo "transaction-with-no-existing-input-address.sh:${PIPESTATUS[0]}" >> tests-results.txt

./e2e-automation-scripts/transaction-with-no-existing-output-address.sh 2>&1 | tee -a output.log
echo "transaction-with-no-existing-output-address.sh:${PIPESTATUS[0]}" >> tests-results.txt

./e2e-automation-scripts/create-payment-and-stake-addresses-with-registartion.sh 2>&1 | tee -a output.log
echo "create-payment-and-stake-addresses-with-registartion.sh:${PIPESTATUS[0]}" >> tests-results.txt

./e2e-automation-scripts/delegate-stake-to-pool.sh 2>&1 | tee -a output.log
echo "delegate-stake-to-pool.sh:${PIPESTATUS[0]}" >> tests-results.txt

tmux kill-server
