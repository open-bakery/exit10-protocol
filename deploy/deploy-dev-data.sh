#!/bin/bash

export ETH_FROM=0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266

SD="$(dirname "$(readlink -f "$0")")"
source "$SD/../.env";

function extract_contract_address() {
  cat < /dev/stdin | grep contractAddress | awk '{ print $2 }' | cut -c 3-43 | tr '[:upper:]' '[:lower:]'
}

DEC6="000000"
DEC18="000000000000000000"

# send tokens to alice
cast send --from "$ALICE_ADDRESS" --value "2000$DEC18" "$WETH" "deposit()" > /dev/null
cast send --from "$DEPLOYER_ADDRESS" "$USDC" "transfer(address,uint256)" "$ALICE_ADDRESS" "100000$DEC6" > /dev/null


