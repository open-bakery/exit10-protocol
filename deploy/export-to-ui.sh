#!/bin/bash

SD="$(dirname "$(readlink -f "$0")")"
source "$SD/../.env"
source "$SD/../config/local.ini"

CONTRACTS="Exit10 DepositHelper STOToken"
for contract in $CONTRACTS; do
  echo "export const $contract = $(jq .abi "$SD/../out/$contract.sol/$contract.json") as const" > "$EXIT10_UI_PATH/src/abis/$contract.ts"
done


echo "export default {
  weth: '$WETH',
  usdc: '$USDC',
  uniswapV3Factory: '$UNISWAP_V3_FACTORY',
  uniswapV3Router: '$UNISWAP_V3_ROUTER',
  uniswapV3NPM: '$UNISWAP_V3_NPM',
  uniswapV2Factory: '$UNISWAP_V2_FACTORY',
  uniswapV2Router: '$UNISWAP_V2_ROUTER',
  swapper: '$SWAPPER',
  stoDistributor: '$STO_DISTRIBUTOR',
  pool: '$POOL',

  nft: '$NFT',
  sto: '$STO',
  boot: '$BOOT',
  blp: '$BLP',
  exit: '$EXIT',
  masterchef0: '$MASTERCHEF0',
  masterchef1: '$MASTERCHEF1',
  masterchefExit: '$MASTERCHEF_EXIT',
  feeSplitter: '$FEE_SPLITTER',
  exit10: '$EXIT10',
  depositHelper: '$DEPOSIT_HELPER',
  exitLp: '$EXIT_LP',
} as const;" > "$EXIT10_UI_PATH/src/const/knownAddresses/local.ts"

# this oneliner below does it automatically but keeps the ugly UPPER_CASE.
# Also we probably don't need all of them for the UI so let's keep it clean and explicit
# echo -en "export default {\n$(sed -E < ./config/local.ini "s/^(.*)=(0x[a-zA-Z0-9]+)/  \1: '\2',/g")\n} as const;" > "$EXIT10_UI_PATH/src/const/knownAddresses/local.ts"
