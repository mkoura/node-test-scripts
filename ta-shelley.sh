#!/usr/bin/env nix-shell
#!nix-shell -i bash -p yj


set -euo pipefail

git clone git@github.com:input-output-hk/cardano-node.git
cd cardano-node
git checkout ${GIT_REV:-master}

git clone git@github.com:ArturWieczorek/node-test-scripts.git
cp node-test-scripts/e2e-automation-scripts .
./e2e-automation-scripts/init-blockchain.sh
