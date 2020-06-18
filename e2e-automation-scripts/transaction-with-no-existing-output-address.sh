#!/bin/bash

# Current working dir: cardano-node

CWD=$PWD

# Source common lib

. $CWD/e2e-automation-scripts/common.sh


check_address_counter_file

# Init variables

keys_dirpath=$addresses_root_dirpath/$address_counter_value
user=user$address_counter_value
fee=1000000 # Skip fee calculation and pick up fee = 1 ADA
amount_transferred=10000000 # 10 ADA

tx=$(get_tx_info_for_address $from_address)
input=$(get_input_for_tx $tx)
balance=$(get_balance_for_tx $tx)
change=$(( balance - fee - amount_transferred ))
to_address=$(get_random_payment_address)
raw_tx_filepath=$keys_dirpath/${user}-tx-body.raw
signed_tx_filepath=$keys_dirpath/${user}-tx-body.signed

info_msg "Creating directory: $keys_dirpath for tx files ..."
mkdir -p $keys_dirpath

# Determine TTL

current_tip=$(get_current_tip)

if [ $? != 0 ]; then
    error_msg "Error when getting current tip"
    exit 1
fi

ttl=$(calculate_ttl)

info_msg "Current tip: $current_tip"
info_msg "Setting TTL to: $ttl"

# Build TX

info_msg "TX Info:"
info_msg "TX Input: $input"
info_msg "TX Input Balance: $balance"
info_msg "Fake output address: $to_address"
info_msg "Amount trasfered $amount_transferred"
info_msg "Change: $change"
info_msg "Sending $(( amount_transferred / 1000000 )) ADA from $from_address to non existing address: $to_address"

info_msg "Building raw TX ..."

cardano-cli shelley transaction build-raw \
    --ttl $ttl \
    --fee $fee \
    --tx-in "$input" \
    --tx-out "${to_address}+${amount_transferred}" \
    --tx-out "${from_address}+${change}" \
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

tx_submit_output=$(cardano-cli shelley transaction submit \
    --tx-file $signed_tx_filepath \
    --testnet-magic $testnet_magic)

# ISSUE with incorrect return code = 1 for success
if [ $?	== 1 ]; then
    error_msg "Error when submitting transaction"
    exit 1
fi

wait_for_new_tip

assert_address_balance $to_address $amount_transferred
