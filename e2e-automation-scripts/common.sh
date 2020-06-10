#!/bin/bash

export CARDANO_NODE_SOCKET_PATH=example/node-pool1/node.sock
export genesis_filepath=example/genesis.json
export testnet_magic=42
export protocol_params_file="${PWD}/example/protocol-params.json"
export counter_file=example/counter
export pool_counter_file=example/pool_counter
export root_addresses_dir=example/addresses
export pool_1_dir=example/node-pool1
export signing_key=${root_addresses_dir}/user1.skey
export from_address=$(cat ${root_addresses_dir}/user1.addr)
# TO DO: to get the slotLength from the protocol_params_file once it will be added there (or from genesis)
export slotLength=1

if [ -f "${counter_file}" ]; then
    counter_value=$(cat "${counter_file}")
    export counter_value="${counter_value}"
fi

if [ -f "${pool_counter_file}" ]; then
    pool_counter_value=$(cat "${pool_counter_file}")
    export pool_counter_value="${pool_counter_value}"
fi

check_counter_file () {
    if [ -f "${counter_file}" ]; then
        echo "INFO: Counter file exist - read the counter and increment by 1" > /dev/tty
        counter_value=$(cat "${counter_file}")
        export counter_value=$((counter_value+1))
        echo ${counter_value} > "${counter_file}"
        echo "INFO: Current run: ${counter_value}" > /dev/tty
    else
        echo "INFO: Counter file does NOT exist - initializing it with value 2" > /dev/tty
        touch "${counter_file}"
        echo 2 > "${counter_file}"
        export counter_value=2
    fi
}

check_pool_counter_file () {
    if [ -f "${pool_counter_file}" ]; then
        echo "INFO: Pool counter file exist - read the counter and increment by 1" > /dev/tty
        pool_counter_value=$(cat "${pool_counter_file}")
        export pool_counter_value=$((pool_counter_value+1))
        echo ${pool_counter_value} > "${pool_counter_file}"
        echo "INFO: Pool current run: ${pool_counter_value}" > /dev/tty
    else
        echo "INFO: Pool counter file does NOT exist - initializing it with value 2" > /dev/tty
        touch "${pool_counter_file}"
        echo 2 > "${pool_counter_file}"
        export pool_counter_value=2
    fi
}

get_protocol_params () {
    local query_params="$(cardano-cli shelley query protocol-parameters \
        --testnet-magic "${testnet_magic}" \
        --out-file "${protocol_params_file}"
    )"

    if [ $?	!= 0 ]; then
        echo "ERROR: Error when querying protocol parameters" > /dev/tty
        exit 1
    fi

    if [ ! -f "${protocol_params_file}" ]; then
        echo "ERROR: protocol params file was not created" > /dev/tty
        exit 1
    fi
    exit 0
}

get_current_tip () {
    local current_tip="$(cardano-cli shelley query tip --testnet-magic "${testnet_magic}" | awk -F= '{print $2}' | grep -o '[0-9]\+')"
    if (( $current_tip	< 1 )); then
        echo "ERROR: Tip is at location: ${current_tip}" > /dev/tty
        exit 1
    fi
    echo ${current_tip}
    exit 0
}

get_pool_deposit () {
    local pool_deposit="$(cat "${protocol_params_file}" | jq '.poolDeposit')"
    echo ${pool_deposit}
    exit 0
}

get_slots_per_kes_period () {
    local slots_per_kes_period="$(cat ${genesis_filepath} | grep KESPeriod |grep -o '[0-9]\+')"
    echo ${slots_per_kes_period}
    exit 0
}

calculate_kes_period () {
    local current_tip=$(get_current_tip)
    local slots_per_kes_period=$(get_slots_per_kes_period)
    local kes_period="$((${current_tip} / ${slots_per_kes_period}))"
    echo ${kes_period}
    exit 0
}

calculate_ttl () {
    local tip=$(get_current_tip)
    local ttl=$((tip + 10000))
    echo ${ttl}
    exit 0
}

get_tx_info_for_address () {
    local _address=$1
    local tx=$(cardano-cli shelley query utxo --testnet-magic "${testnet_magic}" --address "${_address}" | grep "^[^- ]" | sort -k 2n | tail -1)
    echo ${tx}
    exit 0
}

get_input_for_tx () {
    local utxo=$1
    local id=$2
    local input="${utxo}#${id}"
    echo ${input}
    exit 0
}

get_balance_for_tx () {
    local balance=$3
    echo ${balance}
    exit 0
}

wait_for_new_tip () {
    local timeout_no_of_slots=200
    local counter=$((${slotLength} * ${timeout_no_of_slots}))
    initialTip=$(get_current_tip)
    actualTip=$(get_current_tip)
    echo "INFO: initialSlotNo: ${initialTip}" > /dev/tty

    while [ "${actualTip}" = "${initialTip}" ]; do
        sleep ${slotLength}
	actualTip=$(get_current_tip)
	counter=$((counter - 1))
	if [ ${counter} -lt 2 ]; then
	    echo "ERROR: Waited ${counter} secs but no new block was created" > /dev/tty
	    exit 1
	fi
    done
    echo "INFO: New block was created; newSlotNo: ${actualTip}" > /dev/tty
}

exec "$@"
