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

# Our Tokens
NFT=$(forge create "$SRC/NFT.sol:NFT" --unlocked --constructor-args "Bond Data" "BND" 0 | extract_addr)
STO=$(forge create "$SRC/STOToken.sol:STOToken" --unlocked --constructor-args $ZERO32 | extract_addr)
BOOT=$(forge create "$SRC/BaseToken.sol:BaseToken" --unlocked --constructor-args "Exit10 Bootstrap" "BOOT" | extract_addr)
BLP=$(forge create "$SRC/BaseToken.sol:BaseToken" --unlocked --constructor-args "Boost Liquidityp" "BLP" | extract_addr)
EXIT=$(forge create "$SRC/BaseToken.sol:BaseToken" --unlocked --constructor-args "Exit Liquidity" "EXIT" | extract_addr)

# Masterchefs
MASTERCHEF0=$(forge create "$SRC/Masterchef.sol:Masterchef" --unlocked --constructor-args "$WETH" "$REWARDS_DURATION" | extract_addr)
MASTERCHEF1=$(forge create "$SRC/Masterchef.sol:Masterchef" --unlocked --constructor-args "$WETH" "$REWARDS_DURATION" | extract_addr)
MASTERCHEF_EXIT=$(forge create "$SRC/MasterchefExit.sol:MasterchefExit" --unlocked --constructor-args "$EXIT" "$REWARDS_DURATION_EXIT" | extract_addr)

# Exit10 Core (FeeSplitter, Exit10)
FEE_SPLITTER=$(forge create "$SRC/FeeSplitter.sol:FeeSplitter" --unlocked --constructor-args "$MASTERCHEF0" "$MASTERCHEF1" "$SWAPPER" | extract_addr)
EXIT10_BASE_PARAMS="($WETH,$UNISWAP_V3_FACTORY,$UNISWAP_V3_NPM,$WETH,$USDC,$FEE,$LOWER_TICK,$UPPER_TICK)"
EXIT10_DEPLOY_PARAMS="($NFT,$STO,$BOOT,$BLP,$EXIT,$MASTERCHEF_EXIT,$FEE_SPLITTER,$BENEFICIARY,$BOOTSTRAP_PERIOD,$BOOTSTRAP_TARGET,$BOOTSTRAP_CAP,$LIQUIDITY_PER_USDC,$EXIT_DISCOUNT,$ACCRUAL_PARAMETER)"
EXIT10=$(forge create "$SRC/Exit10.sol:Exit10" --unlocked --constructor-args "$EXIT10_BASE_PARAMS" "$EXIT10_DEPLOY_PARAMS" | extract_addr)
echo "EXIT10: $EXIT10"

DEPOSIT_HELPER=$(forge create "$SRC/DepositHelper.sol:DepositHelper" --unlocked --constructor-args "$UNISWAP_V3_ROUTER" "$EXIT10" "$WETH" | extract_addr)

# Uniswap V2 Pool for EXIT/USDC
cast send "$UNISWAP_V2_FACTORY" "createPair(address,address)" "$EXIT" "$USDC" > /dev/null

EXIT_LP="0x$(cast call "$UNISWAP_V2_FACTORY" "getPair(address,address)" "$EXIT" "$USDC" | cut -c 27-66)"
echo "EXIT_LP: $EXIT_LP"

# Post-deploy setup
echo "nft.setExit10"
cast send "$NFT" "setExit10(address)" "$EXIT10" > /dev/null
echo "feeSplitter.setExit10"
cast send "$FEE_SPLITTER" "setExit10(address)" "$EXIT10" > /dev/null

echo "SETUP MASTERCHEF0"
cast send "$MASTERCHEF0" "add(uint32,address)" 50 "$STO" > /dev/null
cast send "$MASTERCHEF0" "add(uint32,address)" 50 "$BOOT" > /dev/null
cast send "$MASTERCHEF0" "transferOwnership(address)" "$FEE_SPLITTER" > /dev/null

echo "SETUP MASTERCHEF1"
cast send "$MASTERCHEF1" "add(uint32,address)" 100 "$BLP" > /dev/null
cast send "$MASTERCHEF1" "transferOwnership(address)" "$FEE_SPLITTER" > /dev/null

echo "SETUP MASTERCHEF_EXIT"
cast send "$MASTERCHEF_EXIT" "add(uint32,address)" 100 "$EXIT_LP" > /dev/null
cast send "$MASTERCHEF_EXIT" "transferOwnership(address)" "$EXIT10" > /dev/null

echo "TRANSFER OWNERSHIPS"
cast send "$BOOT" "transferOwnership(address)" "$EXIT10" > /dev/null
cast send "$STO" "transferOwnership(address)" "$EXIT10" > /dev/null
cast send "$BLP" "transferOwnership(address)" "$EXIT10" > /dev/null
cast send "$EXIT" "transferOwnership(address)" "$EXIT10" > /dev/null


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
DEPOSIT_HELPER=$DEPOSIT_HELPER
EXIT_LP=$EXIT_LP" >> "$SD/../config/local.ini"
