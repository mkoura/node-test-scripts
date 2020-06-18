#!/bin/bash

# Scenario:
# 1. create a payment key pair + address
# 2. test1: try to build, sign and send an unbalanced transaction (change = -1, 1 input, 1 output)
# 3. test2: try to build, sign and send an unbalanced transaction (change = 1, 1 input, 1 output)
# 4. test3: try to build, sign and send an unbalanced transaction (change = 1, 1 input, 2 outputs)


CWD=$PWD

# source common lib

. $CWD/e2e-automation-scripts/common.sh

# Lets create counter file that will keep the number of how many times this script was ran
# ran == how many addresses were created. It  will be used to create separate directories for each
# new key pair / addresses

# Create init variables, directory, payment keys and address for the new address (addr1)
check_address_counter_file

keys_dirpath1=$addresses_root_dirpath/$address_counter_value
addr1=user$address_counter_value
payment_verification_keypath1=$keys_dirpath1/${addr1}.vkey
payment_signing_keypath1=$keys_dirpath1/${addr1}.skey
payment_address_path1=$keys_dirpath1/${addr1}.addr

raw_tx_filepath=$addresses_root_dirpath/tx-body.raw
signed_tx_filepath=$addresses_root_dirpath/tx-body.signed

info_msg "Creating directory: $keys_dirpath1 for payment key pair and address files ..."
mkdir -p $keys_dirpath1

info_msg "Creating payment address keys for $addr1 (addr1) ..."

cardano-cli shelley address key-gen \
    --verification-key-file $payment_verification_keypath1 \
    --signing-key-file $payment_signing_keypath1

if [ $?	!= 0 ]; then
    echo "ERROR: Error during payment keypair creation for $addr1"
    exit 1
fi

info_msg "Building payment address for $addr1 ..."

cardano-cli shelley address build \
    --payment-verification-key-file $payment_verification_keypath1 \
    --testnet-magic $testnet_magic \
    --out-file $payment_address_path1

if [ $? != 0 ]; then
    error_msg "Error during payment address creation for $addr1"
    exit 1
fi

# Determine TTL
current_tip=$(get_current_tip)

if [ $? != 0 ]; then
    error_msg "Error when getting current tip"
    exit 1
fi

ttl=$(calculate_ttl)

info_msg "Current tip: $current_tip"
info_msg "Setting TTL to: $ttl"

# Get current protocol params and write it to file
$(get_protocol_params)

if [ $?	!= 0 ]; then
    error_msg "Error when obtaining protocol parameters"
    exit 1
fi

# Calculate fee
info_msg "Calculating TX fee ..."

fee=$(cardano-cli shelley transaction calculate-min-fee \
    --tx-in-count 1 \
    --tx-out-count 1 \
    --ttl $ttl \
    --testnet-magic $testnet_magic \
    --signing-key-file $user1_payment_signing_keypath \
    --protocol-params-file $protocol_params_filepath \
    | awk '{ print $2}')

if [ $? != 0 ]; then
    echo "ERROR: Error during fee calculation"
    exit 1
fi

echo "========================= Test 1: negative change ======================="

# Build TX
info_msg "Building raw TX ..."	

src_address=$user1_payment_address
dst_address=$(cat $payment_address_path1)

# Get UTXOs from source address (to be used into the actual transaction)
src_utxos=$(get_utxos_for_address $src_address)
highest_amount_utxo=0
utxo_no=0
counter=0

# Create an array with all the utxos from the source address
readarray -t utxo_array <<<"$src_utxos"	

# Get the value and array_index of the UTXO with the highest amount of LOVELACE
for utxo_string in "${utxo_array[@]}"; do
	utxo_amount=$(echo $utxo_string | cut -d' ' -f3)
	if (( utxo_amount >= highest_amount_utxo )); then
		highest_amount_utxo=$utxo_amount
		utxo_no=$counter
	fi
	counter=$(( counter + 1 ))
done

highest_amount_utxo=${utxo_array[$utxo_no]}
highest_utxo_amount_balance=$(get_balance_for_tx $highest_amount_utxo)
src_addr_balance=$(get_address_balance $src_address)
dst_addr_balance=$(get_address_balance $dst_address)
input_utxo=$(get_input_for_tx $highest_amount_utxo)
	
amount_transferred=$(( highest_utxo_amount_balance - fee + 1 ))
change=$(( highest_utxo_amount_balance - fee - amount_transferred ))

info_msg "src_addr_balance (before): $src_addr_balance"
info_msg "highest_utxo_amount_balance (before): $highest_utxo_amount_balance"
info_msg "dst_addr_balance (before): $dst_addr_balance"
info_msg "input_utxo: $input_utxo"
info_msg "fee: $fee"
info_msg "amount_transferred: $amount_transferred"
info_msg "change: $change"

cardano-cli shelley transaction build-raw \
	--ttl $ttl \
	--fee $fee \
	--tx-in $input_utxo \
	--tx-out "${dst_address}+${amount_transferred}" \
	--out-file $raw_tx_filepath

# ISSUE with incorrect return code = 1 for success
if [ $?	== 1 ]; then
	error_msg "Error when building raw transaction"
	exit 1
fi

# Sign TX
info_msg "Signing TX ..."

cardano-cli shelley transaction sign \
	--signing-key-file $user1_payment_signing_keypath \
	--testnet-magic $testnet_magic \
	--tx-body-file $raw_tx_filepath \
	--out-file $signed_tx_filepath

# ISSUE with incorrect return code = 1 for success
if [ $?	== 1 ]; then
	error_msg "Error when signing transaction"
	exit 1
fi
	
# Submit TX
info_msg "Submitting TX ..."

cardano-cli shelley transaction submit \
	--tx-file "${signed_tx_filepath}" \
	--testnet-magic "${testnet_magic}"

# ISSUE with incorrect return code = 0 for success
if [ $?	== 0 ]; then
	error_msg "Transaction not balanced; Expected error when submitting transaction"
	exit 1
else
	success_msg "Not balanced transaction could not be submitted"
fi
	
echo "========================= Test 2: positive change ======================="

# Build TX
info_msg "Building raw TX ..."	
	
amount_transferred=$(( highest_utxo_amount_balance - fee - 1 ))
change=$(( highest_utxo_amount_balance - fee - amount_transferred ))

info_msg "src_addr_balance (before): $src_addr_balance"
info_msg "highest_utxo_amount_balance (before): $highest_utxo_amount_balance"
info_msg "dst_addr_balance (before): $dst_addr_balance"
info_msg "input_utxo: $input_utxo"
info_msg "fee: $fee"
info_msg "amount_transferred: $amount_transferred"
info_msg "change: $change"

cardano-cli shelley transaction build-raw \
	--ttl $ttl \
	--fee $fee \
	--tx-in $input_utxo \
	--tx-out "${dst_address}+${amount_transferred}" \
	--out-file $raw_tx_filepath

# ISSUE with incorrect return code = 1 for success
if [ $?	== 1 ]; then
	error_msg "Error when building raw transaction"
	exit 1
fi

# Sign TX
info_msg "Signing TX ..."

cardano-cli shelley transaction sign \
	--signing-key-file $user1_payment_signing_keypath \
	--testnet-magic $testnet_magic \
	--tx-body-file $raw_tx_filepath \
	--out-file $signed_tx_filepath

# ISSUE with incorrect return code = 1 for success
if [ $?	== 1 ]; then
	error_msg "Error when signing transaction"
	exit 1
fi
	
# Submit TX
info_msg "Submitting TX ..."

cardano-cli shelley transaction submit \
	--tx-file "${signed_tx_filepath}" \
	--testnet-magic "${testnet_magic}"

# ISSUE with incorrect return code = 0 for success
if [ $?	== 0 ]; then
	error_msg "Transaction not balanced; Expected error when submitting transaction"
	exit 1
else
	success_msg "Not balanced transaction could not be submitted"
fi

echo "========================= Test 3: positive change AND --tx-out-count=2 ======================="

# Calculate fee
info_msg "Calculating TX fee ..."

fee=$(cardano-cli shelley transaction calculate-min-fee \
    --tx-in-count 1 \
    --tx-out-count 2 \
    --ttl $ttl \
    --testnet-magic $testnet_magic \
    --signing-key-file $user1_payment_signing_keypath \
    --protocol-params-file $protocol_params_filepath \
    | awk '{ print $2}')

if [ $? != 0 ]; then
    echo "ERROR: Error during fee calculation"
    exit 1
fi

# Build TX
info_msg "Building raw TX ..."	
	
amount_transferred=$(( highest_utxo_amount_balance - fee - 1 ))
change=$(( highest_utxo_amount_balance - fee - amount_transferred + 2 ))

info_msg "src_addr_balance (before): $src_addr_balance"
info_msg "highest_utxo_amount_balance (before): $highest_utxo_amount_balance"
info_msg "dst_addr_balance (before): $dst_addr_balance"
info_msg "input_utxo: $input_utxo"
info_msg "fee: $fee"
info_msg "amount_transferred: $amount_transferred"
info_msg "change: $change"

cardano-cli shelley transaction build-raw \
	--ttl $ttl \
	--fee $fee \
	--tx-in $input_utxo \
	--tx-out "${dst_address}+${amount_transferred}" \
	--tx-out "${src_address}+${change}" \
	--out-file $raw_tx_filepath

# ISSUE with incorrect return code = 1 for success
if [ $?	== 1 ]; then
	error_msg "Error when building raw transaction"
	exit 1
fi

# Sign TX
info_msg "Signing TX ..."

cardano-cli shelley transaction sign \
	--signing-key-file $user1_payment_signing_keypath \
	--testnet-magic $testnet_magic \
	--tx-body-file $raw_tx_filepath \
	--out-file $signed_tx_filepath

# ISSUE with incorrect return code = 1 for success
if [ $?	== 1 ]; then
	error_msg "Error when signing transaction"
	exit 1
fi
	
# Submit TX
info_msg "Submitting TX ..."

cardano-cli shelley transaction submit \
	--tx-file "${signed_tx_filepath}" \
	--testnet-magic "${testnet_magic}"

# ISSUE with incorrect return code = 0 for success
if [ $?	== 0 ]; then
	error_msg "Transaction not balanced; Expected error when submitting transaction"
	exit 1
else
	success_msg "Not balanced transaction could not be submitted"
fi