#!/bin/bash

#export ETH_FROM=0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266
ZERO32=0x0000000000000000000000000000000000000000000000000000000000000000

SD="$(dirname "$(readlink -f "$0")")"
source "$SD/../config/$DEPLOYMENT/infrastructure.ini"
source "$SD/../config/$DEPLOYMENT/deployment.ini"
source "$SD/../.env.secret"
SRC="$SD/../src"

DEPLOY_PARAMS=""
if [ $LOCAL_DEPLOYMENT -eq 1 ]
then
  DEPLOY_PARAMS="$DEPLOY_PARAMS --unlocked"
else
  if [ -z "$ETHERSCAN_API_KEY" ]; then
    echo "Error: ETHERSCAN_API_KEY variable required"
    exit 1
  fi
  if [ -z "$PRIVATE_KEY" ]; then
    echo "Error: PRIVATE_KEY variable required"
    exit 1
  fi
  if [ -z "$ETH_RPC_URL" ]; then
    echo "Error: ETH_RPC_URL variable required"
    exit 1
  fi
  DEPLOY_PARAMS="$DEPLOY_PARAMS --private-key $PRIVATE_KEY --rpc-url $ETH_RPC_URL"
fi

if [ $VERIFY_DEPLOYMENT -eq 1 ]
then
  DEPLOY_PARAMS="$DEPLOY_PARAMS --verify --etherscan-api-key $ETHERSCAN_API_KEY"
fi

if [ $BOOTSTRAP_START = "0" ]
then
  BOOTSTRAP_START=$(date -d "$(date +%Y-%m-%d) +2 days" +%s)
fi

function extract_addr() {
  cat < /dev/stdin | grep "Deployed to" | awk -F ": " '{ print $2 }'
}

function extract_addr_cast() {
  cat < /dev/stdin | grep contractAddress | awk '{ print $2 }'
}

# Our Tokens
NFT=$(forge create "$SRC/NFT.sol:NFT" $DEPLOY_PARAMS --constructor-args "Bond Data" "BND" 0 | extract_addr)
echo "NFT: $NFT"
STO=$(forge create "$SRC/STOToken.sol:STOToken" $DEPLOY_PARAMS --constructor-args $STO_MERKLE_ROOT | extract_addr)
echo "STO: $STO"
BOOT=$(forge create "$SRC/BaseToken.sol:BaseToken" $DEPLOY_PARAMS --constructor-args "Exit10 Bootstrap" "BOOT" | extract_addr)
echo "BOOT: $BOOT"
BLP=$(forge create "$SRC/BaseToken.sol:BaseToken" $DEPLOY_PARAMS --constructor-args "Base Liquidity Position" "BLP" | extract_addr)
echo "BLP: $BLP"
EXIT=$(forge create "$SRC/BaseToken.sol:BaseToken" $DEPLOY_PARAMS --constructor-args "Exit Liquidity" "EXIT" | extract_addr)
echo "EXIT: $EXIT"

# Masterchefs
MASTERCHEF=$(forge create "$SRC/Masterchef.sol:Masterchef" $DEPLOY_PARAMS --constructor-args "$WETH" "$REWARDS_DURATION" | extract_addr)
echo "MASTERCHEF: $MASTERCHEF"
MASTERCHEF_EXIT=$(forge create "$SRC/MasterchefExit.sol:MasterchefExit" $DEPLOY_PARAMS --constructor-args "$EXIT" "$REWARDS_DURATION_EXIT" | extract_addr)
echo "MASTERCHEF_EXIT: $MASTERCHEF_EXIT"

# Exit10 Core (FeeSplitter, Exit10)
FEE_SPLITTER=$(forge create "$SRC/FeeSplitter.sol:FeeSplitter" $DEPLOY_PARAMS --constructor-args "$MASTERCHEF" "$SWAPPER" | extract_addr)
echo "FEE_SPLITTER: $FEE_SPLITTER"
EXIT10_BASE_PARAMS="($WETH,$UNISWAP_V3_FACTORY,$UNISWAP_V3_NPM,$WETH,$USDC,$FEE,$LOWER_TICK,$UPPER_TICK)"
EXIT10_DEPLOY_PARAMS="($NFT,$STO,$BOOT,$BLP,$EXIT,$MASTERCHEF_EXIT,$FEE_SPLITTER,$BENEFICIARY,$LIDO,$BOOTSTRAP_START,$BOOTSTRAP_DURATION,$BOOTSTRAP_LIQUIDITY_CAP,$ACCRUAL_PARAMETER)"

echo "Deploying Exit10...";
echo "EXIT10_BASE_PARAMS: $EXIT10_BASE_PARAMS"
echo "EXIT10_DEPLOY_PARAMS: $EXIT10_DEPLOY_PARAMS"

EXIT10=$(forge create "$SRC/Exit10.sol:Exit10" $DEPLOY_PARAMS --constructor-args "$EXIT10_BASE_PARAMS" "$EXIT10_DEPLOY_PARAMS" | extract_addr)
echo "EXIT10: $EXIT10"

DEPOSIT_HELPER=$(forge create "$SRC/DepositHelper.sol:DepositHelper" $DEPLOY_PARAMS --constructor-args "$UNISWAP_V3_ROUTER" "$EXIT10" "$WETH" | extract_addr)
echo "DEPOSIT_HELPER: $DEPOSIT_HELPER"

NFT_ARTWORK=$(forge create "$SRC/artwork/Artwork.sol:Artwork" $DEPLOY_PARAMS --constructor-args "$EXIT10" | extract_addr)
echo "NFT_ARTWORK: $NFT_ARTWORK"

echo "NFT=$NFT
STO=$STO
BOOT=$BOOT
BLP=$BLP
EXIT=$EXIT
MASTERCHEF=$MASTERCHEF
MASTERCHEF_EXIT=$MASTERCHEF_EXIT
FEE_SPLITTER=$FEE_SPLITTER
EXIT10=$EXIT10
DEPOSIT_HELPER=$DEPOSIT_HELPER
NFT_ARTWORK=$NFT_ARTWORK
" > "$SD/../config/${DEPLOYMENT}/exit10.ini"
