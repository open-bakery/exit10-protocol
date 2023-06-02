#!/bin/bash

SD="$(dirname "$(readlink -f "$0")")"
source <(grep "=" "$SD/../.env")
source <(grep "=" "$SD/../config/$DEPLOYMENT/exit10.ini")

CONTRACTS="Exit10 STOToken AMasterchefBase Masterchef MasterchefExit FeeSplitter"
echo "{
  \"startBlock\": $START_BLOCK,
  \"network\": \"$GRAPH_NETWORK\",
  \"Exit10\": \"$EXIT10\",
  \"STOToken\": \"$STO\",
  \"EXIT\": \"$EXIT\",
  \"ExitLp\": \"$EXIT_LP\",
  \"Pool\": \"$POOL\",
  \"Masterchef\": \"$MASTERCHEF\",
  \"MasterchefExit\": \"$MASTERCHEF_EXIT\",
  \"FeeSplitter\": \"$FEE_SPLITTER\"
}" > "$EXIT10_SUBGRAPH_PATH/networks/$DEPLOYMENT.json"

for contract in $CONTRACTS; do
  jq .abi "$SD/../out/$contract.sol/$contract.json" > "$EXIT10_SUBGRAPH_PATH/abis/$contract.json"
done
