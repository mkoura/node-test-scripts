#!/bin/bash

function usage()
{
cat << HEREDOC

    Usage: $progname [--help]

    optional arguments:
      -h, --help           show this help message and exit


Script for exercise 5 from Cardano Tutorials:
https://github.com/input-output-hk/cardano-tutorials/blob/master/pioneers-testnet/pioneers-exercise-5.md

Requirements:
0) Running relay node, socket file relay/db/node.socket must exist
1) GHC, cabal and all lib needed to start node. (Check tutorials docs)
2) Required ports to be opened

The purpose of this script is to register your stake pool.

WARNING: This script creates lock file after first run - so you will not accidentally remove/overwrite your pool cert file when running this script again. If you want to rerun script - remove lock file. Backup your files if needed.

HEREDOC
}

function requiremnts()
{

cat << HERE_DOC
Looks like relay node is not running.
This script requires relay node from exercise 1 to be running.

It is located in: cardano-node/relay/
Socket file: cardano-node/relay/db/node.socket

You can start node by running "run-node.sh" script from cardano-node/exercise2 directory
OR by manually running from cardano-node directory in a separate terminal:

cardano-node run --topology relay/ff-topology.json --database-path relay/db --socket-path relay/db/node.socket --port 3002 --config relay/ff-config.json

HERE_DOC
exit 1
}

# Current working dir for exercise 5

CWD="${PWD}"
cd ..


# Initialize variables

progname=$(basename $0)
socket_file="${PWD}/relay/db/node.socket"
files_created_by_script_dirname=keys_and_certs
source_address_and_keys_location="${PWD}/exercise1/keys_and_addresses"
from=$(cat "${source_address_and_keys_location}/payment1.addr")
stake_keys_and_address_location="${PWD}/exercise2/keys_and_addresses/0"
pool_keys_and_key_files="${PWD}/pool/keys_and_certs"
testnet_magic=42
lock_file=lock

# Pool params
pool_pledge=7000000
pool_cost=77000000
pool_margin=0.07


OPTS=$(getopt -o "h" --long "help" -n "$progname" -- "$@")
if [ $? != 0 ] ; then
    echo "ERROR: Error in command line arguments." >&2 ; usage; exit 1 ;
fi

eval set -- "$OPTS"

while true; do
    case "$1" in
        -h | --help ) usage; exit; ;;
        -- ) shift; break ;;
        * ) break ;;
    esac
done


# Check whether node is running

is_node_running="$(ps -aux |grep "[c]ardano-node run" | wc -l)"

if [[ "${is_node_running}" < 1 || ! -S "${socket_file}" ]]; then
    requiremnts
fi

# Set CARDANO_NODE_SOCKET_PATH for cardano-cli tool

export CARDANO_NODE_SOCKET_PATH="relay/db/node.socket"


# Check for lock file

if [ -f "${CWD}/${lock_file}" ]; then
    echo "INFO: Lock file exist meaning that you already ran this script and created 'hot' and 'cold' KES, VRF key pairs.
          If you want to re-run this script backup all your cold keys, addresses etc. files in a separate directory and remove
          lockfile.
          WARNING: Rerunning this script after lockfile removal will overwrite existing 'cold', 'hot', KES, VRF keys and remove pool
          and relay directories with all its state"
    exit 0;
fi


# Create directory for certs and other key files inside exercise 5 dir

current_files_dir=${CWD}/${files_created_by_script_dirname}
echo -e "\nINFO: Creating directory: ${current_files_dir} for certs, address and other files ..."
mkdir -p "${current_files_dir}"


# Get current protocol params

protocol_params_file="${CWD}/protocol.json"

echo -e "\nINFO: Getting current protocol params: ${protocol_params_file} ..."

cardano-cli shelley query protocol-parameters \
    --testnet-magic "${testnet_magic}" \
    --out-file "${protocol_params_file}"


# Generate registration cert

echo -e "\nINFO: Generating pool certificate ..."

cardano-cli shelley stake-pool registration-certificate \
    --stake-pool-verification-key-file ~/cold-keys/cold.vkey \
    --vrf-verification-key-file "${pool_keys_and_key_files}/vrf.vkey" \
    --pool-pledge "${pool_pledge}" \
    --pool-cost "${pool_cost}" \
    --pool-margin "${pool_margin}" \
    --reward-account-verification-key-file "${stake_keys_and_address_location}/stake2.vkey" \
    --pool-owner-staking-verification-key "${stake_keys_and_address_location}/stake2.vkey" \
    --out-file "${pool_keys_and_key_files}/pool.cert"


# Pledge some stake to your stake pool

echo -e "\nINFO: Generating delegation certificate - delegating to own pool ..."

cardano-cli shelley stake-address delegation-certificate \
    --staking-verification-key-file "${stake_keys_and_address_location}/stake2.vkey" \
    --stake-pool-verification-key-file ~/cold-keys/cold.vkey \
    --out-file "${pool_keys_and_key_files}/own-deleg.cert"


# Register the pool online

echo -e "\nINFO: Registering pool ..."

# First determine TTL

current_tip="$(cardano-cli shelley query tip --testnet-magic "${testnet_magic}" | awk -F= '{print $2}' | grep -o '[0-9]\+')"
ttl="$(($current_tip+100000))"

echo -e "\nCurrent tip: ${current_tip}"
echo "Setting TTL to: ${ttl}"


fee=$(cardano-cli shelley transaction calculate-min-fee \
    --tx-in-count 1 \
    --tx-out-count 1 \
    --ttl "${ttl}" \
    --testnet-magic "${testnet_magic}" \
    --signing-key-file "${source_address_and_keys_location}/payment1.skey" \
    --signing-key-file ~/cold-keys/cold.skey \
    --signing-key-file "${stake_keys_and_address_location}/stake2.skey" \
    --certificate "${pool_keys_and_key_files}/pool.cert" \
    --certificate "${pool_keys_and_key_files}/own-deleg.cert" \
    --protocol-params-file "${protocol_params_file}" \
    | awk '{ print $2}')

echo -e "\nINFO: Pool registration certificate fee: ${fee}"


# Pool deposit

echo -e "\nINFO: Calculating pool deposit ..."

pool_deposit="$(cat "${protocol_params_file}" | jq '.poolDeposit')"

echo -e "Pool deposit: ${pool_deposit}"


#---
# By default use address 1 from exercise 1 as a source address

tx=$(cardano-cli shelley query utxo --testnet-magic "${testnet_magic}" --address "${from}" | grep "^[^- ]" | sort -k 2n | tail -1)

echo -e "\nTX: $tx "
utxo=$( echo "$tx" | awk '{ print $1 }')
id=$( echo "$tx" | awk '{ print $2 }')
balance=$( echo "$tx" | awk '{ print $3 }')
input="${utxo}#${id}"

change=$(( ${balance} - ${pool_deposit} - ${fee}))

echo -e "\nTX Info:"
echo "Input: ${input}"
echo "Balance: ${balance}"
echo "Change: ${change}"
echo -e "\nINFO: Sending $(( $pool_deposit + $fee )) lovelaces to register pool"

# Transaction creation

# Build TX

cardano-cli shelley transaction build-raw \
    --tx-in "${input}" \
    --tx-out "${from}+${change}" \
    --ttl "${ttl}" \
    --fee "${fee}" \
    --tx-body-file "${CWD}/pool-registration-tx.raw" \
    --certificate "${pool_keys_and_key_files}/pool.cert" \
    --certificate "${pool_keys_and_key_files}/own-deleg.cert"

# Sign

cardano-cli shelley transaction sign \
    --tx-body-file "${CWD}/pool-registration-tx.raw" \
    --signing-key-file "${source_address_and_keys_location}/payment1.skey" \
    --signing-key-file ~/cold-keys/cold.skey \
    --signing-key-file "${stake_keys_and_address_location}/stake2.skey" \
    --testnet-magic "${testnet_magic}" \
    --tx-file "${CWD}/pool-registration-tx.signed"


# Submit

cardano-cli shelley transaction submit \
    --tx-file "${CWD}/pool-registration-tx.signed" \
    --testnet-magic "${testnet_magic}"

# Issue with cli return status

if [ $?	== 0 ]; then
    echo -e "\nERROR: Error when submitting transaction"
    exit 1
fi

# Create lock file

echo -e "\nINFO: Creating lock file - so you will not accidentally remove/overwrite your keys and cert files when running this script again ..."

touch "${CWD}/${lock_file}"

# Wait for some time

echo -e "\nINFO: Waiting for 30 seconds ..."

sleep 30

# Check addresses

echo -e "\nINFO: Checking balance after TX ..."

cardano-cli shelley query utxo --address ${from} --testnet-magic "${testnet_magic}"

