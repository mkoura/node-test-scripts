#!/bin/bash

# Scenario:
#	1. create 101 addresses (only with payment keys) - addr1 and addr2..101
#	2. send 100 transactions of 10 Lovelace from user1 (the faucet) to addr1 ($addr1) - 100 different UTXOs in addr1
#	3. send 9 Lovelace from addr1 ($addr1) to addr2...101 ($addr2 - $addr101) (100 input UTXOs / 100 output addresses)

# Current working dir: cardano-node

CWD=$PWD

# source common lib

. $CWD/e2e-automation-scripts/common.sh

# Lets create counter file that will keep the number of how many times this script was ran
# ran == how many addresses were created. It  will be used to create separate directories for each
# new key pair / addresses

# Create init variables, directory, payment keys and address for the first address (addr1)
counter=0
for i in `seq 1 11`; do
	check_address_counter_file

	keys_dirpath=$addresses_root_dirpath/$address_counter_value
	addr=user$address_counter_value
	payment_verification_keypath=$keys_dirpath/${addr}.vkey
	payment_signing_keypath=$keys_dirpath/${addr}.skey
	payment_address_path=$keys_dirpath/${addr}.addr
	
	# add all addresses into an array
	created_users_aray[$counter]=$addr

	info_msg "Creating directory: $keys_dirpath for payment key pair and address files ..."
	mkdir -p $keys_dirpath

	info_msg "Creating payment address keys for $addr ..."

	cardano-cli shelley address key-gen \
		--verification-key-file $payment_verification_keypath \
		--signing-key-file $payment_signing_keypath

	if [ $?	!= 0 ]; then
		echo "ERROR: Error during payment keypair creation for $addr1"
		exit 1
	fi

	info_msg "Building payment address for $addr ..."

	cardano-cli shelley address build \
		--payment-verification-key-file $payment_verification_keypath \
		--testnet-magic $testnet_magic \
		--out-file $payment_address_path

	if [ $? != 0 ]; then
		error_msg "Error during payment address creation for $addr1"
		exit 1
	fi
	counter=$(( counter + 1 ))
done

info_msg "${#created_users_aray[@]} payment addresses created: ${created_users_aray[@]}"

info_msg "============ Send 100 transactions of 10 Lovelace each from user1 (the faucet) to ${created_users_aray[0]}"
dst_address=${created_users_aray[0]}
user_number=$(get_user_number ${dst_address})

for i in `seq 1 10`; do
	tx_amount=10
	from_address=$user1_payment_address
	to_address=$(cat $addresses_root_dirpath/$user_number/$dst_address.addr)
	signing_key=$user1_payment_signing_keypath

	info_msg "============ Sending $tx_amount Lovelace from $from_address (faucet) to $to_address - ($i)"

	send_funds $from_address $to_address $tx_amount $signing_key

	if [ $?	!= 0 ]; then
		error_msg "Error when sending funds from faucet (user1) to $to_address"
		exit 1
	fi
done

info_msg "============ Send 9 Lovelace from addr1 (${created_users_aray[0]})) to addr2...101 (${created_users_aray[1]} - ${created_users_aray[100]})"
tx_amount_per_dst=9
from_address=${created_users_aray[0]}
signing_key=$payment_signing_keypath1

counter=0
for user in "${created_users_aray[@]}"; do
	to_address_array[counter]=${created_users_aray[$(( counter + 1 ))]}
	tx_amount_array[counter]=$tx_amount_per_dst
	counter=$(( counter + 1 ))
done


echo "from_address: $from_address"
echo "to_address_array: ${to_address_array[@]}"


send_funds $from_address ${to_address_array[@]} ${tx_amount_array[@]} $signing_key

if [ $?	!= 0 ]; then
	error_msg "Error when sending funds from user1 to addr1"
	exit 1
fi

