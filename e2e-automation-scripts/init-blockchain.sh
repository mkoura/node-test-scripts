#!/usr/bin/env bash

set -e
#set -x

root=example
output_log=output.log
test_results=tests-results.txt

if [ -f $output_log ]; then
    rm output.log
fi

if [ -f $test_results ]; then
    rm tests-results.txt
fi

if [ -d $root ]; then
    rm -rf $root
fi

bft_nodes="node-bft1 node-bft2"
bft_nodes_N="1 2"
num_bft_nodes=2

pool_nodes="node-pool1"

all_nodes="$bft_nodes $pool_nodes"

if ! mkdir "$root"; then
  echo "The $root directory already exists, please move or remove it"
  exit
fi

# copy and tweak the configuration
cp configuration/defaults/byron-mainnet/configuration.yaml $root/
sed -i $root/configuration.yaml \
    -e 's/Protocol: RealPBFT/Protocol: TPraos/' \
    -e 's/minSeverity: Info/minSeverity: Debug/'

# Set up our template
cardano-cli shelley genesis create --testnet-magic 42 --genesis-dir $root

# Then edit the genesis.spec.json ...

supply=1000000000000

# We're going to use really quick epochs (300 seconds), by using short slots 0.2s
# and K=10, but we'll keep long KES periods so we don't have to bother
# cycling KES keys
sed -i $root/genesis.spec.json \
    -e 's/"slotLength": 1/"slotLength": 0.2/' \
    -e 's/"activeSlotsCoeff": 5.0e-2/"activeSlotsCoeff": 0.1/' \
    -e 's/"securityParam": 2160/"securityParam": 10/' \
    -e 's/"epochLength": 432000/"epochLength": 1500/' \
    -e 's/"maxLovelaceSupply": 0/"maxLovelaceSupply": 1000000000000/' \
    -e 's/"decentralisationParam": 1/"decentralisationParam": 0.7/' \
    -e 's/"minFeeA": 0/"minFeeA": 44/' \
    -e 's/"minFeeB": 0/"minFeeB": 155381/' \
    -e 's/"keyDeposit": 0/"keyDeposit": 400000/' \
    -e 's/"poolDeposit": 0/"poolDeposit": 5000000/'


# Now generate for real:

cardano-cli shelley genesis create \
    --testnet-magic 42 \
    --genesis-dir $root/ \
    --gen-genesis-keys $num_bft_nodes \
    --gen-utxo-keys 1

pushd $root

echo "====================================================================="
echo "Generated genesis keys and genesis files:"
echo
ls -1 *
echo "====================================================================="

echo "Generated genesis.json:"
echo
cat genesis.json
echo
echo "====================================================================="

mkdir $all_nodes

# Make the pool operator cold keys
# This was done already for the BFT nodes as part of the genesis creation

for node in $pool_nodes; do

  cardano-cli shelley node key-gen \
      --cold-verification-key-file                 $node/operator.vkey \
      --cold-signing-key-file                      $node/operator.skey \
      --operational-certificate-issue-counter-file $node/operator.counter

  cardano-cli shelley node key-gen-VRF \
      --verification-key-file $node/vrf.vkey \
      --signing-key-file      $node/vrf.skey

done

# Symlink the BFT operator keys from the genesis delegates, for uniformity

for n in $bft_nodes_N; do

  ln -s ../delegate-keys/delegate$n.skey node-bft$n/operator.skey
  ln -s ../delegate-keys/delegate$n.vkey node-bft$n/operator.vkey
  ln -s ../delegate-keys/delegate$n.counter node-bft$n/operator.counter
  ln -s ../delegate-keys/delegate$n.vrf.vkey node-bft$n/vrf.vkey
  ln -s ../delegate-keys/delegate$n.vrf.skey node-bft$n/vrf.skey

done


# Make hot keys and for all nodes

for node in ${all_nodes}; do

  cardano-cli shelley node key-gen-KES \
      --verification-key-file $node/kes.vkey \
      --signing-key-file      $node/kes.skey

  cardano-cli shelley node issue-op-cert \
      --kes-period 0 \
      --kes-verification-key-file                  $node/kes.vkey \
      --cold-signing-key-file                      $node/operator.skey \
      --operational-certificate-issue-counter-file $node/operator.counter \
      --out-file                                   $node/node.cert

done

# Make topology files
#TODO generalise this over the N BFT nodes and pool nodes
(cat <<TOPOLOGY_FILE
{
   "Producers": [
     {
       "addr": "127.0.0.1",
       "port": 3002,
       "valency": 1
     }
   , {
       "addr": "127.0.0.1",
       "port": 3003,
       "valency": 1
     }
   ]
 }
TOPOLOGY_FILE
) > node-bft1/topology.json
echo 3001 > node-bft1/port

(cat <<TOPOLOGY_FILE
{
   "Producers": [
     {
       "addr": "127.0.0.1",
       "port": 3001,
       "valency": 1
     }
   , {
       "addr": "127.0.0.1",
       "port": 3003,
       "valency": 1
     }
   ]
 }
TOPOLOGY_FILE
) > node-bft2/topology.json
echo 3002 > node-bft2/port

(cat <<TOPOLOGY_FILE
{
   "Producers": [
     {
       "addr": "127.0.0.1",
       "port": 3001,
       "valency": 1
     }
   , {
       "addr": "127.0.0.1",
       "port": 3002,
       "valency": 1
     }
   ]
 }
TOPOLOGY_FILE
) > node-pool1/topology.json
echo 3003 > node-pool1/port


echo "Generated node operator keys (cold, hot) and operational certs:"
echo
ls -1 $all_nodes
echo "====================================================================="


# Make some payment and stake addresses
# user1..n:       will own all the funds in the system, we'll set this up from
#                 initial utxo the
# pool-owner1..n: will be the owner of the pools and we'll use their reward
#                 account for pool rewards

user_addrs="user1"
pool_addrs="pool-owner1"

addrs="$user_addrs $pool_addrs"

mkdir addresses

for addr in $addrs; do

  # Payment address keys
  cardano-cli shelley address key-gen \
      --verification-key-file addresses/$addr.vkey \
      --signing-key-file      addresses/$addr.skey

  # Stake address keys
  cardano-cli shelley stake-address key-gen \
      --verification-key-file addresses/$addr-stake.vkey \
      --signing-key-file      addresses/$addr-stake.skey

  # Payment addresses
  cardano-cli shelley address build \
      --payment-verification-key-file addresses/$addr.vkey \
      --stake-verification-key-file addresses/$addr-stake.vkey \
      --testnet-magic 42 \
      --out-file addresses/$addr.addr

  # Stake addresses
  cardano-cli shelley stake-address build \
      --stake-verification-key-file addresses/$addr-stake.vkey \
      --testnet-magic 42 \
      --out-file addresses/$addr-stake.addr

  # Stake addresses registration certs
  cardano-cli shelley stake-address registration-certificate \
      --stake-verification-key-file addresses/$addr-stake.vkey \
      --out-file addresses/$addr-stake.reg.cert

done

# user N will delegate to pool N
user_pool_n="1"

for n in $user_pool_n; do

  # Stake address delegation certs
  cardano-cli shelley stake-address delegation-certificate \
      --stake-verification-key-file addresses/user$n-stake.vkey \
      --cold-verification-key-file  node-pool$n/operator.vkey \
      --out-file addresses/user$n-stake.deleg.cert

  ln -s ../addresses/pool-owner$n-stake.vkey node-pool$n/owner.vkey
  ln -s ../addresses/pool-owner$n-stake.skey node-pool$n/owner.skey

done

echo "Generated payment address keys, stake address keys,"
echo "stake address regitration certs, and stake address delegatation certs"
echo
ls -1 addresses/
echo "====================================================================="


# Next is to make the stake pool registration cert

for node in $pool_nodes; do

  cardano-cli shelley stake-pool registration-certificate \
    --testnet-magic 42 \
    --pool-pledge 1000000 --pool-cost 2000000 --pool-margin 0.7 \
    --cold-verification-key-file             $node/operator.vkey \
    --vrf-verification-key-file              $node/vrf.vkey \
    --reward-account-verification-key-file   $node/owner.vkey \
    --pool-owner-stake-verification-key-file $node/owner.vkey \
    --out-file                               $node/registration.cert
done

echo "Generated stake pool registration certs:"
ls -1 node-*/registration.cert
echo "====================================================================="


fee=1000000
change=$(( supply - fee ))

cardano-cli shelley transaction build-raw \
    --ttl 1000 \
    --fee $fee \
    --tx-in $(cardano-cli shelley genesis initial-txin \
                --testnet-magic 42 \
                --verification-key-file utxo-keys/utxo1.vkey) \
    --tx-out "$(cat addresses/user1.addr)+$change" \
    --out-file tx1.txbody


cardano-cli shelley transaction sign \
   --signing-key-file utxo-keys/utxo1.skey \
   --testnet-magic 42 \
   --tx-body-file  tx1.txbody \
   --out-file      tx1.tx

echo "Generated a signed transaction that transfer all funds from initial utxo to address 1:"
ls -1 tx1.tx

run_cmds=()

for node in $all_nodes; do
    run_cmd="cardano-node run --config $root/configuration.yaml --topology $root/$node/topology.json --database-path $root/$node/db --socket-path $root/$node/node.sock --shelley-kes-key $root/$node/kes.skey --shelley-vrf-key $root/$node/vrf.skey --shelley-operational-certificate $root/$node/node.cert --port $(cat ${node}/port)"
    run_cmds+=("$run_cmd")
done

echo "Wait until epoch #2 (counting from 0) starting at slot 3000"
echo "to query the stake distribution, and see if the pool node creates blocks"
echo
echo "CARDANO_node_SOCKET_PATH=example/node-bft1/node.sock \\"
echo "  cardano-cli shelley query stake-distribution --testnet-magic 42"
echo

popd

if ! which tmux > /dev/null; then
    echo "This script requires tmux to be installed on a machine"
    exit 1
fi

session_name="TA Shelley Blockchain"
tmux new-session -d -s "$session_name"

tmux split-window -h
tmux split-window -v -t 0
tmux split-window -v -t 2

for i in $(seq 0 ${#run_cmds[@]}); do
    tmux select-pane -t "$i"
    tmux send-keys -t "$session_name"  "${run_cmds[$i]}" C-m
done

tmux select-pane -t 3
tmux send-keys -t "$session_name" "./e2e-automation-scripts/submit-initial-blockchain-transaction.sh" C-m
tmux send-keys -t "$session_name" "sleep 5; ./e2e-automation-scripts/tests-runner.sh" C-m

# For debugging: attach session
# tmux attach -t "$session_name"
