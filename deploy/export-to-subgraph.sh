#!/bin/bash

SD="$(dirname "$(readlink -f "$0")")"
source "$SD/../.env"
source "$SD/../config/local.ini"

CONTRACTS="Exit10 IUniswapV3Pool STOToken"
echo "{
  \"startBlock\": 0,
  \"network\": \"mainnet\",
  \"Exit10\": \"$EXIT10\",
  \"STOToken\": \"$STO\",
  \"Pool\": \"$POOL\"
}" > "$EXIT10_SUBGRAPH_PATH/networks/local.json"

for contract in $CONTRACTS; do
  jq .abi "$SD/../out/$contract.sol/$contract.json" > "$EXIT10_SUBGRAPH_PATH/abis/$contract.json"
done




#  uniswapV3Router: '$UNISWAP_V3_ROUTER',
#  uniswapV3NPM: '$UNISWAP_V3_NPM',
#  uniswapV2Factory: '$UNISWAP_V2_FACTORY',
#  uniswapV2Router: '$UNISWAP_V2_ROUTER',
#  swapper: '$SWAPPER',
#  pool: '$POOL',
#
#  nft: '$NFT',
#  sto: '$STO',
#  boot: '$BOOT',
#  blp: '$BLP',
#  exit: '$EXIT',
#  masterchef0: '$MASTERCHEF0',
#  masterchef1: '$MASTERCHEF1',
#  masterchefExit: '$MASTERCHEF_EXIT',
#  feeSplitter: '$FEE_SPLITTER',
#  exit10: '$EXIT10',
#  exitLp: '$EXIT_LP',