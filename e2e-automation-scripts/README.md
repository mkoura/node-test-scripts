### 1 To run scripts first clone node repo:

```
git clone git@github.com:input-output-hk/cardano-node.git
```
### 2 Build:

```
cd cardano-node
cabal new-build all
```

### 3 Copy binaries to your path (run inside cardano-node dir)

```
cp $(find . -name cardano-node -executable -type f) ~/.local/bin
cp $(find . -name cardano-cli -executable -type f) ~/.local/bin
```

### 4 Copy `e2e-automation-scripts` from this repo to `cardano-node`


### 5 Run script that creates blockchain from scratch

```
cardano-node$ ./scripts/shelley-from-scratch/mkfiles.sh
```

It will produce output ending with:

```
So you can now do various things:
 * Start the nodes
 * Submit the initial 'do it all' transaction
 * Query the node's ledger state

To start the nodes, in separate terminals use:

cardano-node run \
  --config                          example/configuration.yaml \
  --topology                        example/node-bft1/topology.json \
  --database-path                   example/node-bft1/db \
  --socket-path                     example/node-bft1/node.sock \
  --shelley-kes-key                 example/node-bft1/kes.skey \
  --shelley-vrf-key                 example/node-bft1/vrf.skey \
  --shelley-operational-certificate example/node-bft1/node.cert \
  --port                            3001
cardano-node run \
  --config                          example/configuration.yaml \
  --topology                        example/node-bft2/topology.json \
  --database-path                   example/node-bft2/db \
  --socket-path                     example/node-bft2/node.sock \
  --shelley-kes-key                 example/node-bft2/kes.skey \
  --shelley-vrf-key                 example/node-bft2/vrf.skey \
  --shelley-operational-certificate example/node-bft2/node.cert \
  --port                            3002
cardano-node run \
  --config                          example/configuration.yaml \
  --topology                        example/node-pool1/topology.json \
  --database-path                   example/node-pool1/db \
  --socket-path                     example/node-pool1/node.sock \
  --shelley-kes-key                 example/node-pool1/kes.skey \
  --shelley-vrf-key                 example/node-pool1/vrf.skey \
  --shelley-operational-certificate example/node-pool1/node.cert \
  --port                            3003

To submit the transaction

CARDANO_NODE_SOCKET_PATH=example/node-bft1/node.sock \
  cardano-cli shelley transaction submit \
    --tx-file example/tx1.tx \
    --testnet-magic 42

Then wait until epoch #2 (counting from 0) starting at slot 3000
and query the stake distribution, and see if the pool node creates blocks

CARDANO_NODE_SOCKET_PATH=example/node-bft1/node.sock \
  cardano-cli shelley query stake-distribution --testnet-magic 42

~/Projects/Node_1_13/cardano-node
```

So as the output suggests - open 3 terminals and start nodes then submit a transaction

### 6 Run some test scripts:

```
cardano-node$ ./e2e-automation-scripts/check-stake-distribution.sh
cardano-node$ ./e2e-automation-scripts/create-payment-and-stake-addresses-with-registartion.sh
```
