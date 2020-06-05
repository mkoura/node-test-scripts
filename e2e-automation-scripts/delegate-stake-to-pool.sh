#!/bin/bash

# Current working dir: cardano-node
CWD="${PWD}"

./e2e-automation-scripts/create-payment-and-stake-addresses-with-registartion.sh

if [ $? != 0 ]; then
    echo "ERROR: Creation & registartion of stake address failed"
    exit 1
fi

# source common lib

# Delegate stake to existing stake pools

. "${CWD}/e2e-automation-scripts/common.sh"

echo -e "\nINFO: Delegating stake to existing stake pools ..."

# Generate the certificate

echo -e "\nINFO: Generating delegation certificate ${keys_dir}/${user}-deleg.cert ..."


# Create directory for payment, stake key pair and addresses

keys_dir=${root_addresses_dir}/${counter_value}
user="user${counter_value}"
pool_1_cold_vkey=${pool_1_dir}/operator.vkey


cardano-cli shelley stake-address delegation-certificate \
    --staking-verification-key-file "${keys_dir}/${user}-stake.vkey" \
    --cold-verification-key-file "${pool_1_cold_vkey}" \
    --out-file "${keys_dir}/${user}-deleg.cert"


delegation_cert="${keys_dir}/${user}-deleg.cert"

# Build TX

echo -e "\nINFO: Building raw TX in order to register certificate for stake delegation  address ..."


# Determine TTL

current_tip=$(get_current_tip)
ttl=$(calculate_ttl)

echo -e "\nCurrent tip: ${current_tip}"
echo "Setting TTL to: ${ttl}"

# Calculate fee

echo -e "\nCalculating TX fee ..."

# Get current protocol params and write it to file

$(get_protocol_params)

echo -e "\nCalculating TX fee for registration of delegation certificate ..."

stake_signing_key=${keys_dir}/${user}-stake.skey

fee=$(cardano-cli shelley transaction calculate-min-fee \
    --tx-in-count 1 \
    --tx-out-count 1 \
    --ttl "${ttl}" \
    --testnet-magic "${testnet_magic}" \
    --signing-key-file "${signing_key}" \
    --signing-key-file "${stake_signing_key}" \
    --certificate "${delegation_cert}" \
    --protocol-params-file "${protocol_params_file}" \
    | awk '{ print $2}')

if [ $? != 0 ]; then
    echo "ERROR: Error during fee calculation"
    exit 1
fi

echo "Delegaion certificate registration fee: ${fee}"

# Build TX

echo -e "\nBuilding raw TX ..."

tx=$(get_tx_info_for_address ${from_address})
input=$(get_input_for_tx ${tx})
balance=$(get_balance_for_tx ${tx})
change=$(( balance - fee ))

echo -e "\nTX Info:"
echo "TX Input: ${input}"
echo "TX Input Balance: ${balance}"
echo "Change: ${change}"
echo -e "\nINFO: Sending ${fee} lovelaces to register delegation certificate"


# Build

echo -e "\nBuilding raw TX ..."

cardano-cli shelley transaction build-raw \
    --ttl "${ttl}" \
    --fee "${fee}" \
    --tx-in "${input}" \
    --tx-out "${from_address}+${change}" \
    --certificate-file "${delegation_cert}" \
    --out-file "${keys_dir}/${user}-tx-deleg-cert.raw"

if [ $?	== 1 ]; then
    echo -e "\nERROR: Error when building raw transaction"
    exit 1
fi


# Sign TX

echo -e "\nSigning TX ..."

cardano-cli shelley transaction sign \
    --tx-body-file "${keys_dir}/${user}-tx-deleg-cert.raw" \
    --signing-key-file "${signing_key}" \
    --signing-key-file "${stake_signing_key}" \
    --testnet-magic "${testnet_magic}" \
    --out-file "${keys_dir}/${user}-tx-deleg-cert.signed"

if [ $?	== 1 ]; then
    echo -e "\nERROR: Error when signing transaction"
    exit 1
fi

# Submit TX

echo -e "\nSubmitting TX ..."

cardano-cli shelley transaction submit \
    --tx-file "${keys_dir}/${user}-tx-deleg-cert.signed" \
    --testnet-magic "${testnet_magic}"

if [ $?	== 1 ]; then
    echo -e "\nERROR: Error when submitting transaction"
    exit 1
fi


















