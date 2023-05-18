#!/bin/bash

export ETH_FROM=0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266
SD="$(dirname "$(readlink -f "$0")")"
BYTECODES="$SD/bytecode"

# load deployment specific config
source "$SD/../config/$DEPLOYMENT/deployment.ini"

function extract_contract_address() {
  cat < /dev/stdin | grep contractAddress | awk '{ print $2 }' | cut -c 3-43 | tr '[:upper:]' '[:lower:]'
}

# official deployment addresses - suffix underscored
WETH_ADDRESS_="c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2"
V2_FACTORY_ADDRESS_="5c69bee701ef814a2b6a3edd4b1652cb9cc5aa6f"
V3_FACTORY_ADDRESS_="1f98431c8ad98523631ae4a59f267346ea31f984"
V3_ROUTER_ADDRESS_="e592427a0aece92de3edee1f18e0157c05861564"
V3_TPD_ADDRESS_="ee6a57ec80ea46401049e92587e52f5ec1c24785"

MAX_ALLOWANCE="0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"

# Token
USDC_BYTECODE=$(cat "$BYTECODES/USDC")
WETH_BYTECODE=$(cat "$BYTECODES/WETH")

if [ $TOKEN_OUT_FIRST -eq 1 ]
then
  TOKEN0_ADDRESS=$(cast send --create "$USDC_BYTECODE" | extract_contract_address)
  TOKEN1_ADDRESS=$(cast send --create "$WETH_BYTECODE" | extract_contract_address)
  USDC_ADDRESS=$TOKEN0_ADDRESS
  WETH_ADDRESS=$TOKEN1_ADDRESS
else
  TOKEN0_ADDRESS=$(cast send --create "$WETH_BYTECODE" | extract_contract_address)
  TOKEN1_ADDRESS=$(cast send --create "$USDC_BYTECODE" | extract_contract_address)
  WETH_ADDRESS=$TOKEN0_ADDRESS
  USDC_ADDRESS=$TOKEN1_ADDRESS
fi

cast send --value 200000000000000000000000 "0x$WETH_ADDRESS" "deposit()" > /dev/null

# Uniswap V2
V2_FACTORY_BYTECODE=$(cat "$BYTECODES/UniswapV2Factory")
V2_FACTORY_ADDRESS=$(cast send --create "$V2_FACTORY_BYTECODE" | extract_contract_address)

V2_ROUTER_BYTECODE=$(sed < "$BYTECODES/UniswapV2Router" "s/$V2_FACTORY_ADDRESS_/$V2_FACTORY_ADDRESS/;s/$WETH_ADDRESS_/$WETH_ADDRESS/")
V2_ROUTER_ADDRESS=$(cast send --create "$V2_ROUTER_BYTECODE" | extract_contract_address)

# Uniswap V3
V3_FACTORY_BYTECODE=$(cat "$BYTECODES/UniswapV3Factory")
V3_FACTORY_ADDRESS=$(cast send --create "$V3_FACTORY_BYTECODE" | extract_contract_address)

V3_TPD_BYTECODE=$(sed < "$BYTECODES/UniswapV3PositionDescriptor" "s/$WETH_ADDRESS_/$WETH_ADDRESS/")

V3_TPD_ADDRESS=$(cast send --create "$V3_TPD_BYTECODE" | extract_contract_address)

V3_NPM_BYTECODE=$(sed < "$BYTECODES/UniswapV3PositionManager" "s/$V3_FACTORY_ADDRESS_/$V3_FACTORY_ADDRESS/;s/$WETH_ADDRESS_/$WETH_ADDRESS/;s/$V3_TPD_ADDRESS_/$V3_TPD_ADDRESS/")
V3_NPM_ADDRESS=$(cast send --create "$V3_NPM_BYTECODE" | extract_contract_address)

V3_ROUTER_BYTECODE=$(sed < "$BYTECODES/UniswapV3Router" "s/$V3_FACTORY_ADDRESS_/$V3_FACTORY_ADDRESS/;s/$WETH_ADDRESS_/$WETH_ADDRESS/")
V3_ROUTER_ADDRESS=$(cast send --create "$V3_ROUTER_BYTECODE" | extract_contract_address)

cast send "0x$WETH_ADDRESS" "approve(address,uint256)" "0x$V3_NPM_ADDRESS" $MAX_ALLOWANCE > /dev/null
cast send "0x$USDC_ADDRESS" "approve(address,uint256)" "0x$V3_NPM_ADDRESS" $MAX_ALLOWANCE > /dev/null
cast send "0x$WETH_ADDRESS" "approve(address,uint256)" "0x$V3_ROUTER_ADDRESS" $MAX_ALLOWANCE > /dev/null
cast send "0x$USDC_ADDRESS" "approve(address,uint256)" "0x$V3_ROUTER_ADDRESS" $MAX_ALLOWANCE > /dev/null
cast send "0x$V3_FACTORY_ADDRESS" "createPool(address,address,uint24)" "0x$USDC_ADDRESS" "0x$WETH_ADDRESS" 500 > /dev/null
POOL_ADDRESS=$(cast call "0x$V3_FACTORY_ADDRESS" "getPool(address,address,uint24)" "0x$WETH_ADDRESS" "0x$USDC_ADDRESS" 500 | cut -c 27-66)

cast send "0x$POOL_ADDRESS" "initialize(uint160)" "$INIT_SQRT_PRICE" > /dev/null
cast send "0x$V3_NPM_ADDRESS" "mint((address,address,uint24,int24,int24,uint256,uint256,uint256,uint256,address,uint256))(uint256,uint128,uint256,uint256)" "(0x$TOKEN0_ADDRESS,0x$TOKEN1_ADDRESS,500,-886800,886800,$MINT_TOKEN0,$MINT_TOKEN1,0,0,$ETH_FROM,10000000000000000000000000000)" > /dev/null

# Lido
LIDO_BYTECODE=$(cat "$BYTECODES/Lido")
LIDO_ADDRESS=$(cast send --create "$LIDO_BYTECODE" | extract_contract_address)

# Our stuff
SWAPPER_BYTECODE=$(sed < "$BYTECODES/Swapper" "s/$V3_FACTORY_ADDRESS_/$V3_FACTORY_ADDRESS/;s/$V3_ROUTER_ADDRESS_/$V3_ROUTER_ADDRESS/")
SWAPPER_ADDRESS=$(cast send --create "$SWAPPER_BYTECODE" | extract_contract_address)
cast send "0x$POOL_ADDRESS" "increaseObservationCardinalityNext(uint16)" 2 > /dev/null
sleep 2
cast send >> /dev/null

BLOCK=$(cast rpc eth_blockNumber | jq -r . | awk -n '{print $1+1}')

echo "# LOCAL INFRASTRUCTURE CONFIG
WETH=0x$WETH_ADDRESS
USDC=0x$USDC_ADDRESS
UNISWAP_V3_FACTORY=0x$V3_FACTORY_ADDRESS
UNISWAP_V3_ROUTER=0x$V3_ROUTER_ADDRESS
UNISWAP_V3_NPM=0x$V3_NPM_ADDRESS
SWAPPER=0x$SWAPPER_ADDRESS
POOL=0x$POOL_ADDRESS
UNISWAP_V2_FACTORY=0x$V2_FACTORY_ADDRESS
UNISWAP_V2_ROUTER=0x$V2_ROUTER_ADDRESS
LIDO=0x$LIDO_ADDRESS
START_BLOCK=$BLOCK

" > "$SD/../config/$DEPLOYMENT/infrastructure.ini"