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
    create_stake_addr_registration_cert, get_key_deposit, get_pool_deposit, get_registered_stake_pools_ledger_state, \
    create_and_register_stake_pool, write_to_file, gen_pool_metadata_hash, create_stake_addr_delegation_cert, \
    register_stake_pool, wait_for_new_epoch

# Scenario
# 1. Step1: create 1 new payment key pair and addresses (addr0.addr)
# 2. Step2: create 1 new stake key pair and addresses (addr0_stake.addr)
# 3. Step3: create and submit the stake addresses registration certificate
# 4. Step4: send some funds from user1 (the faucet) to addr0.addr
# 5. Step5: create and register 1 stake pool with 1 owner
# 6. Step6: create 1 stake addresses registration certificate
# 7. Step7: create 1 stake addresses delegation certificate in order to meet the pledge requirements
# 8. Step8: submit the 2 certificates through a tx - stake address registration, stake address delegation
# 9. Step9: check that the pool was registered on chain
# 10. Step10: update the pool parameters by resubmitting the pool registration certificate
# TO DO: updating the pool parameters might cost less than pool registration (to validate this)
# 11. Step11: wait_for_new_epoch and check that the pool parameters were correctly updated on chain

addr_name = "owner"
node_name = "poolA"
pool_pledge = 4567
pool_cost = 3
pool_margin = 0.01
pool_pledge_updated = 1
pool_cost_updated = 1000000
pool_margin_updated = 0.9

pool_metadata = {
    "name": "QA E2E test",
    "description": "Shelley QA E2E test Test",
    "ticker": "QA1",
    "homepage": "www.test1.com"
}
pool_metadata_url = "www.where_metadata_file_is_located.com"

print("Creating a new folder for the files created by the current test...")
tmp_directory_for_script_files = "tmp_" + sys.argv[0].split(".")[0]
Path(tmp_directory_for_script_files).mkdir(parents=True, exist_ok=True)

print("Add the pool metadata into a different file")
pool_metadata_file = write_to_file(tmp_directory_for_script_files, pool_metadata, "pool_metadata.json")

print(f"====== Step1: create 1 new payment key pair and addresses ({addr_name}.addr)")
addr, addr_vkey_file, addr_skey_file = create_payment_key_pair_and_address(tmp_directory_for_script_files, addr_name)
print(f"Address successfully created - {addr}; {addr_vkey_file}; {addr_skey_file}")

print(f"====== Step2: create 1 new stake key pair and addresses ({addr_name}_stake.addr)")
created_stake_addresses_dict = {}
stake_addr, stake_addr_vkey_file, stake_addr_skey_file = create_stake_key_pair_and_address(tmp_directory_for_script_files, addr_name)
print(f"Stake address successfully created - {stake_addr}; {stake_addr_vkey_file}; {stake_addr_skey_file}")

print(f"====== Step3: create 1 stake addresses registration cert")
stake_addr_reg_cert_file = create_stake_addr_registration_cert(tmp_directory_for_script_files, stake_addr_vkey_file, addr_name)
print(f"Stake address registration certificate created - {stake_addr_reg_cert_file}")

print(f"====== Step4: send some funds from user1 (the faucet) to {addr_name}.addr")
key_deposit = get_key_deposit()
pool_deposit = get_pool_deposit()
tx_ttl = calculate_tx_ttl()
tx_fee = calculate_tx_fee(1, 2, tx_ttl, signing_keys=[USER1_SKEY_FILE_PATH])

src_address = USER1_ADDRESS
dst_addresses_list = [addr]
transferred_amounts_list = [int(4 * tx_fee + key_deposit + pool_deposit + pool_pledge)]
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

print(f"====== Step5: create and register 1 stake pool with 1 owner")
pool_owner = [addr, addr_vkey_file, addr_skey_file, stake_addr, stake_addr_vkey_file, stake_addr_skey_file]
pool_metadata_hash = gen_pool_metadata_hash(pool_metadata_file)
stake_pool_id, node_cold_vkey_file, node_cold_skey_file, node_vrf_vkey_file = \
    create_and_register_stake_pool(tmp_directory_for_script_files, node_name, pool_pledge, pool_cost, pool_margin,
                                   pool_owner, pool_metadata=[pool_metadata_url, pool_metadata_hash])

print(f"====== Step6: create 1 stake addresses registration certificate")
stake_addr_reg_cert_file = create_stake_addr_registration_cert(tmp_directory_for_script_files, stake_addr_vkey_file, addr_name)
print(f"Stake address registration certificate created - {stake_addr_reg_cert_file}")

print(f"====== Step7: create 1 stake addresses delegation certificate in order to meet the pledge requirements")
stake_addr_delegation_cert_file = create_stake_addr_delegation_cert(tmp_directory_for_script_files, stake_addr_vkey_file,
                                                                    node_cold_vkey_file, addr_name)
print(f"Stake pool owner-delegation certificate created - {stake_addr_delegation_cert_file}")

print(f"====== Step8: submit the 2 certificates through a tx - stake address registration, stake address delegation")
src_address = addr
certificates_list = [stake_addr_reg_cert_file, stake_addr_delegation_cert_file]
signing_keys_list = [addr_skey_file, stake_addr_skey_file, node_cold_skey_file]
tx_ttl = calculate_tx_ttl()
tx_fee = calculate_tx_fee(1, 1, tx_ttl, certificates=certificates_list, signing_keys=signing_keys_list)
src_add_balance_init = get_address_balance(src_address)

send_funds(src_address, tx_fee + key_deposit, tx_ttl,
           certificates=certificates_list,
           signing_keys=signing_keys_list)

wait_for_new_tip()
wait_for_new_tip()

print(f"Check that the balance for source address was correctly updated")
assert_address_balance(src_address, src_add_balance_init - tx_fee)

print(f"====== Step9: check that the pool was registered on chain")
if stake_pool_id not in list(get_registered_stake_pools_ledger_state().keys()):
    print(f"ERROR: newly created stake pool id is not shown inside the available stake pools; "
          f"\n\t- Pool ID: {stake_pool_id} vs Existing IDs: {list(get_registered_stake_pools_ledger_state().keys())}")
    exit(2)
else:
    print(f"{stake_pool_id} is included into the output of ledger_state() command")

on_chain_stake_pool_details = get_registered_stake_pools_ledger_state().get(stake_pool_id)
on_chain_pool_details_errors_list = []
if on_chain_stake_pool_details['owners'][0] not in stake_addr:
    on_chain_pool_details_errors_list.append(f"'owner' value is different than expected; "
                                             f"Expected: {stake_addr} vs Returned: {on_chain_stake_pool_details['owners'][0]}")

if on_chain_stake_pool_details['cost'] != pool_cost:
    on_chain_pool_details_errors_list.append(f"'cost' value is different than expected; "
                                             f"Expected: {pool_cost} vs Returned: {on_chain_stake_pool_details['cost']}")

if on_chain_stake_pool_details['margin'] != pool_margin:
    on_chain_pool_details_errors_list.append(f"'margin' value is different than expected; "
                                             f"Expected: {pool_margin} vs Returned: {on_chain_stake_pool_details['margin']}")

if on_chain_stake_pool_details['pledge'] != pool_pledge:
    on_chain_pool_details_errors_list.append(f"'pledge' value is different than expected; "
                                             f"Expected: {pool_pledge} vs Returned: {on_chain_stake_pool_details['pledge']}")

if on_chain_stake_pool_details['metadata'] is None:
    on_chain_pool_details_errors_list.append(f"'metadata' value is different than expected; "
                                             f"Expected: None vs Returned: {on_chain_stake_pool_details['metadata']}")

if on_chain_stake_pool_details['relays'] != []:
    on_chain_pool_details_errors_list.append(f"'relays' value is different than expected; "
                                             f"Expected: [] vs Returned: {on_chain_stake_pool_details['relays']}")

if len(on_chain_pool_details_errors_list) > 0:
    print(f"{len(on_chain_pool_details_errors_list)} pool parameter(s) have different values on chain than expected:")
    for er in on_chain_pool_details_errors_list:
        print(f"\tERROR: {er}")
else:
    print(f"All pool details were correctly registered on chain for {stake_pool_id} - {on_chain_stake_pool_details}")

print(f"====== Step10: update the pool parameters by resubmitting the pool registration certificate")
pool_reg_cert_file = register_stake_pool(pool_owner, pool_pledge_updated, pool_cost_updated, pool_margin_updated,
                                         node_vrf_vkey_file, node_cold_vkey_file, node_cold_skey_file,
                                         tmp_directory_for_script_files, node_name,
                                         pool_metadata=[pool_metadata_url, pool_metadata_hash])

print(f"====== Step11: wait_for_new_epoch and check that the pool parameters were correctly updated on chain for pool id: {stake_pool_id}")
wait_for_new_epoch()
on_chain_stake_pool_details = get_registered_stake_pools_ledger_state().get(stake_pool_id)
on_chain_pool_details_errors_list = []
if on_chain_stake_pool_details['owners'][0] not in stake_addr:
    on_chain_pool_details_errors_list.append(f"'owner' value is different than expected; "
                                             f"Expected: {stake_addr} vs Returned: {on_chain_stake_pool_details['owners'][0]}")

if on_chain_stake_pool_details['cost'] != pool_cost_updated:
    on_chain_pool_details_errors_list.append(f"'cost' value is different than expected; "
                                             f"Expected: {pool_cost_updated} vs Returned: {on_chain_stake_pool_details['cost']}")

if on_chain_stake_pool_details['margin'] != pool_margin_updated:
    on_chain_pool_details_errors_list.append(f"'margin' value is different than expected; "
                                             f"Expected: {pool_margin_updated} vs Returned: {on_chain_stake_pool_details['margin']}")

if on_chain_stake_pool_details['pledge'] != pool_pledge_updated:
    on_chain_pool_details_errors_list.append(f"'pledge' value is different than expected; "
                                             f"Expected: {pool_pledge_updated} vs Returned: {on_chain_stake_pool_details['pledge']}")

if on_chain_stake_pool_details['metadata'] is None:
    on_chain_pool_details_errors_list.append(f"'metadata' value is different than expected; "
                                             f"Expected: None vs Returned: {on_chain_stake_pool_details['metadata']}")

if on_chain_stake_pool_details['relays'] != []:
    on_chain_pool_details_errors_list.append(f"'relays' value is different than expected; "
                                             f"Expected: [] vs Returned: {on_chain_stake_pool_details['relays']}")

if len(on_chain_pool_details_errors_list) > 0:
    print(f"{len(on_chain_pool_details_errors_list)} pool parameter(s) have different values on chain than expected:")
    for er in on_chain_pool_details_errors_list:
        print(f"\tERROR: {er}")
else:
    print(f"All pool details were correctly registered on chain for {stake_pool_id} - {on_chain_stake_pool_details}")
