#!/bin/bash

export ETH_FROM=0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266
MAX_ALLOWANCE="0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"
ZERO32=0x0000000000000000000000000000000000000000000000000000000000000000

SD="$(dirname "$(readlink -f "$0")")"
source "$SD/../.env"
SRC="$SD/../src"

function extract_addr() {
  cat < /dev/stdin | grep "Deployed to" | awk -F ": " '{ print $2 }'
}

function extract_addr_cast() {
  cat < /dev/stdin | grep contractAddress | awk '{ print $2 }'
}


REWARDS_DURATION="1209600" # 2 weeks
BOOTSTRAP_PERIOD="1209600"
ACCRUAL_PARAMETER="604800" # 1 week
LP_PER_USD="1"

# Our Tokens
NFT=$(forge create "$SRC/NFT.sol:NFT" --unlocked --constructor-args "Bond Data" "BND" 0 | extract_addr)
STO=$(forge create "$SRC/STO.sol:STO" --unlocked --constructor-args $ZERO32 | extract_addr)
BOOT=$(forge create "$SRC/BaseToken.sol:BaseToken" --unlocked --constructor-args "Exit10 Bootstrap" "BOOT" | extract_addr)
BLP=$(forge create "$SRC/BaseToken.sol:BaseToken" --unlocked --constructor-args "Boost Liquidityp" "BLP" | extract_addr)
EXIT=$(forge create "$SRC/BaseToken.sol:BaseToken" --unlocked --constructor-args "Exit Liquidity" "EXIT" | extract_addr)

# Masterchefs
MASTERCHEF0=$(forge create "$SRC/Masterchef.sol:Masterchef" --unlocked --constructor-args "$WETH" "$REWARDS_DURATION" | extract_addr)
MASTERCHEF1=$(forge create "$SRC/Masterchef.sol:Masterchef" --unlocked --constructor-args "$WETH" "$REWARDS_DURATION" | extract_addr)
MASTERCHEF_EXIT=$(forge create "$SRC/MasterchefExit.sol:MasterchefExit" --unlocked --constructor-args "$EXIT" "$REWARDS_DURATION" | extract_addr)

# Exit10 Core (FeeSplitter, Exit10)
FEE_SPLITTER=$(forge create "$SRC/FeeSplitter.sol:FeeSplitter" --unlocked --constructor-args "$MASTERCHEF0" "$MASTERCHEF1" "$SWAPPER" | extract_addr)
EXIT10_BASE_PARAMS="($UNISWAP_V3_FACTORY,$UNISWAP_V3_NPM,$WETH,$USDC,$FEE,$LOWER_TICK,$UPPER_TICK)"
EXIT10_DEPLOY_PARAMS="($NFT,$STO,$BOOT,$BLP,$EXIT,$MASTERCHEF_EXIT,$FEE_SPLITTER,$BOOTSTRAP_PERIOD,$ACCRUAL_PARAMETER,$LP_PER_USD)"
EXIT10=$(forge create "$SRC/Exit10.sol:Exit10" --unlocked --constructor-args "$EXIT10_BASE_PARAMS" "$EXIT10_DEPLOY_PARAMS" | extract_addr)
echo "EXIT10: $EXIT10"

# Uniswap V2 Pool for EXIT/USDC
cast send "$UNISWAP_V2_FACTORY" "createPair(address,address)" "$EXIT" "$USDC"

EXIT_LP="0x$(cast call "$UNISWAP_V2_FACTORY" "getPair(address,address)" "$EXIT" "$USDC" | cut -c 27-66)"
echo "EXIT_LP: $EXIT_LP"

# Post-deploy setup
echo "sto.setExit10"
cast send "$STO" "setExit10(address)" "$EXIT10"
echo "nft.setExit10"
cast send "$NFT" "setExit10(address)" "$EXIT10"
echo "feeSplitter.setExit10"
cast send "$FEE_SPLITTER" "setExit10(address)" "$EXIT10"

echo "SETUP MASTERCHEF0"
cast send "$MASTERCHEF0" "add(uint256,address)" 50 "$STO"
cast send "$MASTERCHEF0" "add(uint256,address)" 50 "$BOOT"
cast send "$MASTERCHEF0" "setRewardDistributor(address)" "$FEE_SPLITTER"
cast send "$MASTERCHEF0" "renounceOwnership()"

echo "SETUP MASTERCHEF1"
cast send "$MASTERCHEF1" "add(uint256,address)" 100 "$BOOT"
cast send "$MASTERCHEF1" "setRewardDistributor(address)" "$FEE_SPLITTER"
cast send "$MASTERCHEF1" "renounceOwnership()"

echo "SETUP MASTERCHEF_EXIT"
cast send "$MASTERCHEF_EXIT" "add(uint256,address)" 100 "$EXIT_LP"
cast send "$MASTERCHEF_EXIT" "renounceOwnership()"

echo "TRANSFER OWNERSHIPS"
cast send "$BOOT" "transferOwnership(address)" "$EXIT10"
cast send "$BLP" "transferOwnership(address)" "$EXIT10"
cast send "$EXIT" "transferOwnership(address)" "$EXIT10"


echo "NFT=$NFT
STO=$STO
BOOT=$BOOT
BLP=$BLP
EXIT=$EXIT
MASTERCHEF0=$MASTERCHEF0
MASTERCHEF1=$MASTERCHEF1
MASTERCHEF_EXIT=$MASTERCHEF_EXIT
FEE_SPLITTER=$FEE_SPLITTER
EXIT10=$EXIT10
EXIT_LP=$EXIT_LP" >> "$SD/../config/local.ini"

