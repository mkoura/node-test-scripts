#!/bin/bash

# Current working dir: cardano-node
CWD="${PWD}"

./e2e-automation-scripts/create-payment-and-stake-addresses-with-registartion.sh

if [ $? != 0 ]; then
    echo "ERROR: Creation & registartion of stake address failed"
    exit 1
fi

# source common lib
. "${CWD}/e2e-automation-scripts/common.sh"

# Lets create counter file that will keep the number of how many times this script was ran
# ran == how many addresses were created. It  will be used to create separate directories for each
# new key pair / addresses

check_pool_counter_file

# Create directory for pool and relay

pool_dir=${CWD}/example/node-pool${pool_counter_value}
relay_dir=${CWD}/example/node-relay${pool_counter_value}

echo -e "\nINFO: Creating directories ${pool_dir} and ${relay_dir} for pool and relay ..."

mkdir -p ${pool_dir}
mkdir -p ${relay_dir}


# Generate  offline "cold" key pair

echo -e "\nINFO: Creating cold-keys inside ${pool_dir} ..."

cardano-cli shelley node key-gen \
    --verification-key-file "${pool_dir}/cold.vkey" \
    --signing-key-file "${pool_dir}/cold.skey" \
    --operational-certificate-issue-counter "${pool_dir}/cold.counter"

if [ $?	!= 0 ]; then
    echo "ERROR: Error during cold keys creation"
    exit 1
fi


# Generate hot KES keypair

echo -e "\nINFO: Generating hot KES keypair ..."

cardano-cli shelley node key-gen-KES \
    --verification-key-file "${pool_dir}/kes.vkey" \
    --signing-key-file "${pool_dir}/kes.skey"

if [ $?	!= 0 ]; then
    echo "ERROR: Error during hot KES keypair creation"
    exit 1
fi

# Get start of KES validity period

kes_period=$(calculate_kes_period)
#echo "get_current_tip: $(get_current_tip)"
#echo "get_slots_per_kes_period: $(get_slots_per_kes_period)"
#echo "KES period tip/kes period: ${kes_period}"

# Create operational certificate for your pool

echo -e "\nINFO: Creating operational certificate for new pool ..."

cardano-cli shelley node issue-op-cert \
    --kes-verification-key-file "${pool_dir}/kes.vkey" \
    --cold-signing-key-file "${pool_dir}/cold.skey" \
    --operational-certificate-issue-counter-file "${pool_dir}/cold.counter" \
    --kes-period "${kes_period}" \
    --out-file "${pool_dir}/opcert"

if [ $?	!= 0 ]; then
    echo "ERROR: Error during operational certificate creation"
    exit 1
fi

# Generate a VRF key pair for your new stake pool - they will be used for leader lottery selection

echo -e "\nINFO: Generating a VRF key pair for new stake pool ..."

cardano-cli shelley node key-gen-VRF \
    --verification-key-file "${pool_dir}/vrf.vkey" \
    --signing-key-file "${pool_dir}/vrf.skey"

if [ $?	!= 0 ]; then
    echo "ERROR: Error during VRF key pair creation"
    exit 1
fi

# Create topology files for pool and relay

ff_relay_hostname=127.0.0.1 #relays-new.ff.dev.cardano.org
ff_relay_port=3001

local_relay_hostname=127.0.0.1
local_relay_port=4240

local_block_producer_hostname=127.0.0.1
local_block_producer_port=4242

echo -e "\nINFO: Creating topology files for pool and relay ..."

echo "{
   \"Producers\": [
     {
       \"addr\": \"${local_block_producer_hostname}\",
       \"port\": ${local_block_producer_port},
       \"valency\": 1
     }
   ]
}" > ${pool_dir}/topology.json



 echo "{
   \"Producers\": [
     {
       \"addr\": \"${local_relay_hostname}\",
       \"port\": ${local_relay_port},
       \"valency\": 1
     },
     {
       \"addr\": \"${ff_relay_hostname}\",
       \"port\": ${ff_relay_port},
       \"valency\": 1
     }
   ]
}" > ${relay_dir}/topology.json



# Generate registration cert

echo -e "\nINFO: Generating pool certificate ..."

# Pool params
pool_pledge=7000000
pool_cost=77000000
pool_margin=0.07

# Get current protocol params and write it to file

$(get_protocol_params)

stake_keys_and_address_location="${root_addresses_dir}/${counter_value}"
user="user${counter_value}"
stake_vkey_location="${stake_keys_and_address_location}/${user}-stake.vkey"
stake_skey_location="${stake_keys_and_address_location}/${user}-stake.skey"

cardano-cli shelley stake-pool registration-certificate \
    --cold-verification-key-file "${pool_dir}/cold.vkey" \
    --vrf-verification-key-file "${pool_dir}/vrf.vkey" \
    --pool-pledge "${pool_pledge}" \
    --pool-cost "${pool_cost}" \
    --pool-margin "${pool_margin}" \
    --pool-reward-account-verification-key-file "${stake_vkey_location}" \
    --pool-owner-stake-verification-key-file "${stake_vkey_location}" \
    --testnet-magic ${testnet_magic} \
    --out-file "${pool_dir}/pool.cert"

if [ $?	!= 0 ]; then
    echo "ERROR: Error during pool registration certificate creation"
    exit 1
fi


# Pledge some stake to your stake pool

echo -e "\nINFO: Generating delegation certificate - delegating to own pool ..."

cardano-cli shelley stake-address delegation-certificate \
    --stake-verification-key-file "${stake_vkey_location}" \
    --cold-verification-key-file "${pool_dir}/cold.vkey" \
    --out-file "${pool_dir}/own-deleg.cert"


if [ $?	!= 0 ]; then
    echo "ERROR: Error during delegation certificate creation"
    exit 1
fi


# Register the pool online

echo -e "\nINFO: Registering pool ..."

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
    --tx-out-count 1 \
    --ttl "${ttl}" \
    --testnet-magic "${testnet_magic}" \
    --signing-key-file "${signing_key}" \
    --signing-key-file "${pool_dir}/cold.skey" \
    --signing-key-file "${stake_skey_location}" \
    --certificate "${pool_dir}/pool.cert" \
    --certificate "${pool_dir}/own-deleg.cert" \
    --protocol-params-file "${protocol_params_file}" \
    | awk '{ print $2}')

if [ $? != 0 ]; then
    echo "ERROR: Error during fee calculation"
    exit 1
fi

echo -e "\nINFO: Pool registration certificate fee: ${fee}"


# Pool deposit

echo -e "\nINFO: Obtaining pool deposit ..."

pool_deposit=$(get_pool_deposit)

echo -e "Pool deposit: ${pool_deposit}"

# By default use address 1 as source address

tx=$(get_tx_info_for_address ${from_address})
input=$(get_input_for_tx ${tx})
balance=$(get_balance_for_tx ${tx})
change=$(( balance - pool_deposit - fee ))


echo -e "\nTX Info:"
echo "Input: ${input}"
echo "Balance: ${balance}"
echo "Change: ${change}"
echo -e "\nINFO: Sending $(( $pool_deposit + $fee )) lovelaces to register pool"

# Build raw TX

echo -e "\nBuilding raw TX ..."

cardano-cli shelley transaction build-raw \
    --tx-in "${input}" \
    --tx-out "${from_address}+${change}" \
    --ttl "${ttl}" \
    --fee "${fee}" \
    --tx-body-file "${pool_dir}/pool-registration-tx.raw" \
    --certificate "${pool_dir}/pool.cert" \
    --certificate "${pool_dir}/own-deleg.cert"

if [ $?	== 1 ]; then
    echo -e "\nERROR: Error when building raw transaction"
    exit 1
fi

# Sign TX

echo -e "\nSigning TX ..."

cardano-cli shelley transaction sign \
    --tx-body-file "${pool_dir}/pool-registration-tx.raw" \
    --signing-key-file "${signing_key}" \
    --signing-key-file "${pool_dir}/cold.skey" \
    --signing-key-file "${stake_skey_location}" \
    --testnet-magic "${testnet_magic}" \
    --tx-file "${pool_dir}/pool-registration-tx.signed"

if [ $?	== 1 ]; then
    echo -e "\nERROR: Error when signing transaction"
    exit 1
fi

# Submit TX

echo -e "\nSubmitting TX ..."

cardano-cli shelley transaction submit \
    --tx-file "${pool_dir}/pool-registration-tx.signed" \
    --testnet-magic "${testnet_magic}"

if [ $?	== 1 ]; then
    echo -e "\nERROR: Error when submitting transaction"
    exit 1
fi

###################################################################

echo -e "\nINFO: Starting pool and relay nodes in tmux session ..."

tmux has-session -t dev

if [ $? != 0 ]; then
    tmux new-session -s dev -n "Cardano Pool & Relay Nodes" -d
    tmux split-window -h -t dev:0
    tmux send-keys -t dev:0.0 "cardano-node run --config example/configuration.yaml --topology ${pool_dir}/topology.json --database-path ${pool_dir}/db --socket-path ${pool_dir}/db/node.socket --shelley-kes-key ${pool_dir}/kes.skey --shelley-vrf-key ${pool_dir}/vrf.skey --shelley-operational-certificate ${pool_dir}/opcert --port ${local_relay_port}" C-m
    tmux send-keys -t dev:0.1 "cardano-node run --config example/configuration.yaml --topology ${relay_dir}/topology.json --database-path ${relay_dir}/db --socket-path ${relay_dir}/db/node.socket --port ${local_block_producer_port}" C-m
    tmux select-window -t dev:0
fi
tmux attach -t dev
