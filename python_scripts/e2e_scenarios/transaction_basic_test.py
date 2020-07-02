#!/usr/bin/env python3

import os, sys
from pathlib import Path

# TO DO: this could be moved out of the scripts (somehow..)
dir_path = os.path.dirname(os.path.realpath(__file__))
parent_dir_path = os.path.abspath(os.path.join(dir_path, os.pardir))
sys.path.insert(0, parent_dir_path)

from e2e_scenarios.constants import ADDRESSES_DIR_PATH, USER1_SKEY_FILE_PATH
from e2e_scenarios.utils import create_payment_key_pair_and_address, calculate_tx_fee, calculate_tx_ttl, send_funds, \
    get_address_balance, wait_for_new_tip, assert_address_balance, read_address_from_file

# Scenario
# 1. Step1: create 2 new payment addresses (addr0, addr1)
# 2. Step2: send (tx_fee + 2000) Lovelace form user1 (the faucet) to addr0
# 3. Step3: send ALL funds from addr0 to addr1
# 4. check that the balances of the 3 addresses were correctly updated after each step

print("Creating a new folder for the files created by the current test...")
tmp_directory_for_script_files = "tmp_" + sys.argv[0].split(".")[0]
Path(tmp_directory_for_script_files).mkdir(parents=True, exist_ok=True)

no_of_addr_to_be_created = 2
print(f"====== Step1: Creating {no_of_addr_to_be_created} new payment key pair(s) and address(es)")
created_addresses_dict = {}
for count in range(0, no_of_addr_to_be_created):
    addr_name = "addr" + str(count)
    addr, addr_vkey, addr_skey = create_payment_key_pair_and_address(tmp_directory_for_script_files, addr_name)
    created_addresses_dict[addr_name] = [addr, addr_vkey, addr_skey]

print(f"{len(created_addresses_dict)} addresses created for the current test: {created_addresses_dict}")

print(f"====== Step2: Send funds from user1 (faucet) to {list(created_addresses_dict)[0]}")
src_address = read_address_from_file(ADDRESSES_DIR_PATH, "user1")
dst_addresses_list = [created_addresses_dict.get(list(created_addresses_dict)[0])[0]]

print("Calculate the ttl for the funds transfer transaction")
tx_ttl = calculate_tx_ttl()

print("Calculate the tx fee for the funds transfer transaction")
tx_fee = calculate_tx_fee(1, len(dst_addresses_list) + 1, tx_ttl, signing_keys=[USER1_SKEY_FILE_PATH])

transferred_amounts_list = [tx_fee + 2000]
signing_keys_list = [USER1_SKEY_FILE_PATH]

src_add_balance_init = get_address_balance(src_address)
dst_init_balances = {}
for dst_address in dst_addresses_list:
    dst_addr_balance = get_address_balance(dst_address)
    dst_init_balances[dst_address] = dst_addr_balance

print(f"Send {transferred_amounts_list} Lovelace from {src_address} to {dst_addresses_list}")
send_funds(src_address, tx_fee, tx_ttl,
           destinations_list=dst_addresses_list,
           transferred_amounts=transferred_amounts_list,
           signing_keys=signing_keys_list)

wait_for_new_tip()
wait_for_new_tip()

print(f"Check that the balance for source address was correctly updated")
assert_address_balance(src_address, src_add_balance_init - tx_fee - sum(transferred_amounts_list))

print(f"Check that the balance for destination addresses was correctly updated")
for dst_address in dst_addresses_list:
    assert_address_balance(dst_address, dst_init_balances.get(dst_address) + transferred_amounts_list[0])

print(f"====== Step3: Send ALL funds from addr0 to addr1")

print("Calculate the ttl for the funds transfer transaction")
tx_ttl = calculate_tx_ttl()

print("Calculate the tx fee for the funds transfer transaction")
tx_fee = calculate_tx_fee(1, 1, tx_ttl, signing_keys=[USER1_SKEY_FILE_PATH])

src_address = created_addresses_dict.get(list(created_addresses_dict)[0])[0]
dst_addresses_list = [created_addresses_dict.get(list(created_addresses_dict)[1])[0]]
transferred_amounts_list = [get_address_balance(src_address) - tx_fee]
signing_keys_list = [created_addresses_dict.get(list(created_addresses_dict)[0])[2]]

src_add_balance_init = get_address_balance(src_address)
dst_init_balances = {}
for dst_address in dst_addresses_list:
    dst_addr_balance = get_address_balance(dst_address)
    dst_init_balances[dst_address] = dst_addr_balance

print(f"Send {transferred_amounts_list} Lovelace from {src_address} to {dst_addresses_list}")
send_funds(src_address, tx_fee, tx_ttl,
           destinations_list=dst_addresses_list,
           transferred_amounts=transferred_amounts_list,
           signing_keys=signing_keys_list)

wait_for_new_tip()
wait_for_new_tip()

print(f"Check that the balance for source address was correctly updated")
assert_address_balance(src_address, src_add_balance_init - tx_fee - sum(transferred_amounts_list))

print(f"Check that the balance for destination addresses was correctly updated")
for dst_address in dst_addresses_list:
    assert_address_balance(dst_address, dst_init_balances.get(dst_address) + transferred_amounts_list[0])

# TO DO: create a separate script to clean up all the folders (that are starting with tmp_)
