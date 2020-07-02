#!/usr/bin/env python3

import os, sys
from pathlib import Path

# TO DO: this could be moved out of the scripts (somehow..)
dir_path = os.path.dirname(os.path.realpath(__file__))
parent_dir_path = os.path.abspath(os.path.join(dir_path, os.pardir))
sys.path.insert(0, parent_dir_path)

from e2e_scenarios.constants import USER1_ADDRESS, USER1_SKEY_FILE_PATH
from e2e_scenarios.utils import create_payment_key_pair_and_address, calculate_tx_fee, calculate_tx_ttl, send_funds, \
    get_address_balance, wait_for_new_tip, assert_address_balance, create_stake_key_pair_and_address, \
    create_stake_addr_registration_cert, get_key_deposit, delegate_stake_address, get_stake_address_info, \
    get_stake_distribution

# Scenario
# 1. Step1: create 1 new payment key pair and addresses (addr0.addr)
# 2. Step2: create 1 new stake key pair and addresses (addr0_stake.addr)
# 3. Step3: create 1 stake addresses registration certificate
# 4. Step4: send some funds from user1 (the faucet) to addr0.addr
# 5. Step5: submit the stake addresses registration certificate through a tx
# 6. Step6: delegate the addr0_stake.addr to one stake pool id
# 7. Step7: check the delegation details for addr0_stake.addr

print("Creating a new folder for the files created by the current test...")
tmp_directory_for_script_files = "tmp_" + sys.argv[0].split(".")[0]
Path(tmp_directory_for_script_files).mkdir(parents=True, exist_ok=True)

print(f"====== Step1: create 1 new payment key pair and addresses (addr0.addr)")
addr_name = "addr0"
addr, addr_vkey_file, addr_skey_file = create_payment_key_pair_and_address(tmp_directory_for_script_files, addr_name)
print(f"Address successfully created - {addr}; {addr_vkey_file}; {addr_skey_file}")

print(f"====== Step2: create 1 new stake key pair and addresses (addr0_stake.addr)")
created_stake_addresses_dict = {}
stake_addr, stake_addr_vkey_file, stake_addr_skey_file = create_stake_key_pair_and_address(tmp_directory_for_script_files, addr_name)
print(f"Stake address successfully created - {stake_addr}; {stake_addr_vkey_file}; {stake_addr_skey_file}")

print(f"====== Step3: create 1 stake addresses registration cert")
stake_addr_reg_cert_file = create_stake_addr_registration_cert(tmp_directory_for_script_files, stake_addr_vkey_file, addr_name)
print(f"Stake address registration certificate created - {stake_addr_reg_cert_file}")

print(f"====== Step4: send some funds from user1 (the faucet) to addr0.addr")
key_deposit = get_key_deposit()
tx_ttl = calculate_tx_ttl()
tx_fee = calculate_tx_fee(1, 2, tx_ttl, signing_keys=[USER1_SKEY_FILE_PATH])

src_address = USER1_ADDRESS
dst_addresses_list = [addr]
transferred_amounts_list = [int(4 * tx_fee + key_deposit + 1000)]
signing_keys_list = [USER1_SKEY_FILE_PATH]

src_add_balance_init = get_address_balance(src_address)
dst_init_balance = get_address_balance(dst_addresses_list[0])

print(f"Send {transferred_amounts_list} Lovelace from {src_address} to {dst_addresses_list}")
send_funds(src_address, tx_fee, tx_ttl,
           destinations_list=dst_addresses_list,
           transferred_amounts=transferred_amounts_list,
           signing_keys=signing_keys_list)

wait_for_new_tip()
wait_for_new_tip()

print(f"Check that the balance for source address was correctly updated")
assert_address_balance(src_address, src_add_balance_init - tx_fee - transferred_amounts_list[0])

print(f"Check that the balance for destination address was correctly updated")
assert_address_balance(dst_addresses_list[0], dst_init_balance + transferred_amounts_list[0])

print(f"====== Step5: submit the certificate through a tx")
tx_ttl = calculate_tx_ttl()
src_address = addr
signing_keys_list = [addr_skey_file, stake_addr_skey_file]
certificates_list = [stake_addr_reg_cert_file]

print(f"signing_keys_list: {signing_keys_list}")
print(f"certificates_list: {certificates_list}")

tx_fee = calculate_tx_fee(1, 1, tx_ttl, certificates=certificates_list, signing_keys=signing_keys_list)
src_add_balance_init = get_address_balance(src_address)

print(f"tx_fee: {tx_fee}")
print(f"key_deposit: {key_deposit}")
print(f"src_add_balance_init: {src_add_balance_init}")

send_funds(src_address, tx_fee + key_deposit, tx_ttl,
           certificates=certificates_list,
           signing_keys=signing_keys_list)

wait_for_new_tip()
wait_for_new_tip()

print(f"Check that the balance for source address was correctly updated")
assert_address_balance(src_address, src_add_balance_init - tx_fee)

print(f"====== Step6: delegate the addr0_stake.addr to one stake pool id")
src_add_balance_init = get_address_balance(src_address)
first_pool_id_in_stake_distribution = list(get_stake_distribution())[0]
print(f"Stake Pool ID: {first_pool_id_in_stake_distribution}")

tx_fee = calculate_tx_fee(1, 1, tx_ttl, signing_keys=signing_keys_list)
aa = delegate_stake_address(stake_addr_skey_file, first_pool_id_in_stake_distribution, tx_fee)

print(f"aa: {aa}")

wait_for_new_tip()
wait_for_new_tip()

print(f"Check that the balance for source address was correctly updated")
assert_address_balance(src_address, src_add_balance_init - tx_fee)

print(f"====== Step7: check the delegation details for addr0_stake.addr")
delegation, reward_account_balance = get_stake_address_info(stake_addr)

if delegation is None:
    print(f"ERROR: address delegation is None (address was not delegated yet)")
    exit(2)