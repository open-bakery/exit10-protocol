#!/bin/bash

SD="$(dirname "$(readlink -f "$0")")"
source "$SD/../config/$DEPLOYMENT/infrastructure.ini"
source "$SD/../config/$DEPLOYMENT/deployment.ini"
source "$SD/../config/$DEPLOYMENT/exit10.ini"
source "$SD/../.env.secret"
SRC="$SD/../src"

DEPLOY_PARAMS=""
if [ $LOCAL_DEPLOYMENT -ne 1 ]
then
  if [ -z "$PRIVATE_KEY" ]; then
    echo "Error: PRIVATE_KEY variable required"
    exit 1
  fi
  if [ -z "$ETH_RPC_URL" ]; then
    echo "Error: ETH_RPC_URL variable required"
    exit 1
  fi
  DEPLOY_PARAMS="--private-key $PRIVATE_KEY --rpc-url $ETH_RPC_URL"
fi

# Uniswap V2 Pool for EXIT/USDC
cast send $DEPLOY_PARAMS "$UNISWAP_V2_FACTORY" "createPair(address,address)" "$EXIT" "$USDC" > /dev/null

EXIT_LP="0x$(cast call $DEPLOY_PARAMS "$UNISWAP_V2_FACTORY" "getPair(address,address)" "$EXIT" "$USDC" | cut -c 27-66)"
echo "EXIT_LP: $EXIT_LP"

# Post-deploy setup
echo "nft.setExit10"
cast send $DEPLOY_PARAMS "$NFT" "setExit10(address)" "$EXIT10" > /dev/null
cast send $DEPLOY_PARAMS "$NFT" "setArtwork(address)" "$NFT_ARTWORK" > /dev/null
echo "feeSplitter.setExit10"
cast send $DEPLOY_PARAMS "$FEE_SPLITTER" "setExit10(address)" "$EXIT10" > /dev/null

echo "SETUP MASTERCHEF"
cast send $DEPLOY_PARAMS "$MASTERCHEF" "add(uint32,address)" 50 "$STO" > /dev/null
cast send $DEPLOY_PARAMS "$MASTERCHEF" "add(uint32,address)" 50 "$BOOT" > /dev/null

echo "SETUP MASTERCHEF_EXIT"
cast send $DEPLOY_PARAMS "$MASTERCHEF_EXIT" "add(uint32,address)" 20 "$EXIT_LP" > /dev/null
cast send $DEPLOY_PARAMS "$MASTERCHEF_EXIT" "add(uint32,address)" 80 "$BLP" > /dev/null

echo "TRANSFER OWNERSHIPS"
cast send $DEPLOY_PARAMS "$MASTERCHEF_EXIT" "transferOwnership(address)" "$EXIT10" > /dev/null
cast send $DEPLOY_PARAMS "$MASTERCHEF" "transferOwnership(address)" "$FEE_SPLITTER" > /dev/null
cast send $DEPLOY_PARAMS "$BOOT" "transferOwnership(address)" "$EXIT10" > /dev/null
cast send $DEPLOY_PARAMS "$STO" "transferOwnership(address)" "$EXIT10" > /dev/null
cast send $DEPLOY_PARAMS "$BLP" "transferOwnership(address)" "$EXIT10" > /dev/null
cast send $DEPLOY_PARAMS "$EXIT" "transferOwnership(address)" "$EXIT10" > /dev/null

echo "EXIT_LP=$EXIT_LP" >> "$SD/../config/${DEPLOYMENT}/exit10.ini"
echo "All done"