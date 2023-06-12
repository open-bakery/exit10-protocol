#!/bin/bash

SD="$(dirname "$(readlink -f "$0")")"

# load deployment specific config
source "$SD/../config/$DEPLOYMENT/deployment.ini"
source "$SD/../.env.secret"
SRC="$SD/../src"

function extract_addr() {
  cat < /dev/stdin | grep "Deployed to" | awk -F ": " '{ print $2 }'
}

DEPLOY_PARAMS=""
if [ $LOCAL_DEPLOYMENT -eq 1 ]
then
  DEPLOY_PARAMS="$DEPLOY_PARAMS --unlocked"
else
  DEPLOY_PARAMS="$DEPLOY_PARAMS --private-key $PRIVATE_KEY --rpc-url $ETH_RPC_URL"
fi

if [ $VERIFY_DEPLOYMENT -eq 1 ]
then
  DEPLOY_PARAMS="$DEPLOY_PARAMS --verify --etherscan-api-key $ETHERSCAN_API_KEY"
fi


echo "ETH_RPC_URL: $ETH_RPC_URL"
echo "LOCAL_DEPLOYMENT: $LOCAL_DEPLOYMENT"
echo "DEPLOY_PARAMS: $DEPLOY_PARAMS"
echo "PRIVATE_KEY: $PRIVATE_KEY"

forge create "$SRC/BaseToken.sol:BaseToken" $DEPLOY_PARAMS --constructor-args "Testing Token" "TTK"

