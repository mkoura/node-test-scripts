#!/bin/bash

# Current working dir: cardano-node
CWD="${PWD}"

# source common lib
. "${CWD}/e2e-automation-scripts/common.sh"

#signing_key=${root_addresses_dir}/user1.skey
#from_address=$(cat ${root_addresses_dir}/user1.addr)
amount=1

# Lets create counter file that will keep the number of how many times this script was ran
# ran == how many addresses were created. It  will be used to create separate directories for each
# new key pair / addresses

check_counter_file

# Create directory for payment, stake key pair and addresses

keys_dir=${root_addresses_dir}/${counter_value}
user="user${counter_value}"

echo -e "\nINFO: Creating directory: ${keys_dir} for payment key pair and address files ..."
mkdir -p "${keys_dir}"

# Create payment address keys

echo "INFO: Creating payment address keys for ${user} ..."

cardano-cli shelley address key-gen \
    --verification-key-file "${keys_dir}/${user}.vkey" \
    --signing-key-file "${keys_dir}/${user}.skey"

if [ $?	!= 0 ]; then
    echo "ERROR: Error during payment keypair creation"
    exit 1
fi


# Create stake address keys

echo "INFO: Creating stake address keys for ${user} ..."

cardano-cli shelley stake-address key-gen \
    --verification-key-file "${keys_dir}/${user}-stake.vkey" \
    --signing-key-file "${keys_dir}/${user}-stake.skey"

if [ $? != 0 ]; then
    echo "ERROR: Error during stake keypair creation"
    exit 1
fi

# Set stake signing key

stake_signing_key="${keys_dir}/${user}-stake.skey"

# Build payment address

echo "INFO: Building payment address for ${user} ..."

cardano-cli shelley address build \
    --payment-verification-key-file "${keys_dir}/${user}.vkey" \
    --stake-verification-key-file "${keys_dir}/${user}-stake.vkey" \
    --testnet-magic "${testnet_magic}" \
    --out-file "${keys_dir}/${user}.addr"

if [ $? != 0 ]; then
    echo "ERROR: Error during payment address creation"
    exit 1
fi

# Set to address

to_address=$(cat "${keys_dir}/${user}.addr")

# Build stake address

echo "INFO: Building stake address for ${user} ..."

cardano-cli shelley stake-address build \
    --stake-verification-key-file "${keys_dir}/${user}-stake.vkey" \
    --testnet-magic "${testnet_magic}" \
    --out-file "${keys_dir}/${user}-stake.addr"

if [ $? != 0 ]; then
    echo "ERROR: Error during stake address creation"
    exit 1
fi

# Create stake addresses registration cert

echo "INFO: Creating registartion cert for ${user}-stake.addr ..."

cardano-cli shelley stake-address registration-certificate \
    --stake-verification-key-file "${keys_dir}/${user}-stake.vkey" \
    --out-file "${keys_dir}/${user}-stake.reg.cert"

if [ $? != 0 ]; then
    echo "ERROR: Error during creation of registartion certificate"
    exit 1
fi

# Build TX

echo -e "\nINFO: Building raw TX in order to register certificate for stake address ..."


# Determine TTL

current_tip=$(get_current_tip)
ttl=$(calculate_ttl)

echo -e "\nCurrent tip: ${current_tip}"
echo "Setting TTL to: ${ttl}"

# Calculate fee

echo -e "\nCalculating TX fee ..."

# Get current protocol params and write it to file

$(get_protocol_params)

fee=$(cardano-cli shelley transaction calculate-min-fee \
    --tx-in-count 1 \
    --tx-out-count 2 \
    --ttl "${ttl}" \
    --testnet-magic "${testnet_magic}" \
    --signing-key-file "${signing_key}" \
    --signing-key-file "${stake_signing_key}" \
    --certificate-file "${keys_dir}/${user}-stake.reg.cert" \
    --protocol-params-file "${protocol_params_file}" \
    | awk '{ print $2}')

if [ $? != 0 ]; then
    echo "ERROR: Error during fee calculation"
    exit 1
fi

echo "Fee: ${fee}"

# In order to register stake key on the chain we also need to pay a deposit which is specified in genesis
# parameters

echo -e "\nObtaining key deposit ..."

key_deposit="$(grep keyDep "${protocol_params_file}" | grep -o '[0-9]\+')"

echo "Key deposit: ${key_deposit}"

# Build TX

tx=$(get_tx_info_for_address ${from_address})
input=$(get_input_for_tx ${tx})
balance=$(get_balance_for_tx ${tx})
change=$(( balance - fee - amount - key_deposit))

echo -e "\nTX Info:"
echo "TX Input: ${input}"
echo "TX Input Balance: ${balance}"
echo "Output address: ${to_address}"
echo "Amount trasfered ${amount}"
echo "Change: ${change}"

echo -e "\nINFO: Sending $((amount/1000000)) ADA from ${from_address} to ${to_address}"
echo "INFO: Registering stake address ${keys_dir}/${user}-stake.addr"

echo -e "\nBuilding raw TX ..."

cardano-cli shelley transaction build-raw \
    --ttl "${ttl}" \
    --fee "${fee}" \
    --tx-in "${input}" \
    --tx-out "${to_address}+${amount}" \
    --tx-out "${from_address}+${change}" \
    --certificate-file "${keys_dir}/${user}-stake.reg.cert" \
    --out-file "${keys_dir}/${user}-tx-body.raw"

if [ $?	== 1 ]; then
    echo -e "\nERROR: Error when building raw transaction"
    exit 1
fi

# Sign TX

echo -e "\nSigning TX ..."

cardano-cli shelley transaction sign \
    --signing-key-file "${signing_key}" \
    --signing-key-file "${stake_signing_key}" \
    --testnet-magic "${testnet_magic}" \
    --tx-body-file "${keys_dir}/${user}-tx-body.raw" \
    --out-file "${keys_dir}/${user}-tx-body.signed"

if [ $?	== 1 ]; then
    echo -e "\nERROR: Error when signing transaction"
    exit 1
fi

# Submit TX

echo -e "\nSubmitting TX ..."

cardano-cli shelley transaction submit \
    --tx-file "${keys_dir}/${user}-tx-body.signed" \
    --testnet-magic "${testnet_magic}"

if [ $?	== 1 ]; then
    echo -e "\nERROR: Error when submitting transaction"
    exit 1
fi

# Wait for some time

echo -e "\nINFO: Waiting for the tx to be included into a block ..."

wait_for_new_tip

echo -e "\nINFO: Showing balance for destination address after submitting TX ..."

destination_addr_details="$(get_tx_info_for_address "${to_address}")"

if [[ -z "${destination_addr_details}" || "${destination_addr_details}" == *"----"* ]]; then
    echo -e "\nERROR: destination address ${to_address} does not exist / empty.
    Exiting ..."
    exit 1
else
    funds=$(get_balance_for_tx ${destination_addr_details})
    echo "${destination_addr_details}"
    if (( funds != amount )); then
        echo "ERROR: Incorrect amount of funds on address. Is: ${funds}. Should be: ${amount}"
	exit 1
    fi
    exit 0
fi
