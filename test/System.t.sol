// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import 'forge-std/Test.sol';

import '../src/interfaces/IUniswapV3Factory.sol';
import '../src/interfaces/IUniswapV3Router.sol';

import '../src/Exit10.sol';
import '../src/FeeSplitter.sol';
import '../src/Masterchef.sol';
import '../src/MasterchefExit.sol';

import '../src/NFT.sol';
import '../src/BaseToken.sol';
import '../src/STO.sol';

import './ABaseExit10.t.sol';

contract SystemTest is Test, ABaseExit10Test {
  Exit10 exit10;
  NFT nft;
  STO sto;
  BaseToken boot;
  BaseToken blp;
  BaseToken exit;
  address lp; // EXIT/USDC LP Uniswap v2

  uint256 REWARDS_DURATION = 2 weeks;

  // Params Exit10
  address uniswapV3Factory = vm.envAddress('UNISWAP_V3_FACTORY');
  address nonfungiblePositionManager = vm.envAddress('UNISWAP_V3_NPM');
  address weth = vm.envAddress('WETH');
  address usdc = vm.envAddress('USDC');
  uint24 fee = uint24(vm.envUint('FEE'));
  int24 tickLower = int24(vm.envInt('LOWER_TICK'));
  int24 tickUpper = int24(vm.envInt('UPPER_TICK'));

  address alice = address(0xa);
  address bob = address(0xb);
  address charlie = address(0xc);

  uint256 bootstrapPeriod = 1 hours;
  uint256 accrualParameter = 1 days;
  uint256 lpPerUSD = 1; // made up number

  uint256 deployTime;
  uint256 constant MX = type(uint256).max;

  address feeSplitter;
  Masterchef masterchef0; // 50% BOOT 50% STO
  Masterchef masterchef1; // BLP
  MasterchefExit masterchef2; // EXIT/USDC LP Uniswap v2

  IUniswapBase.BaseDeployParams baseParams =
    IUniswapBase.BaseDeployParams({
      uniswapFactory: uniswapV3Factory,
      nonfungiblePositionManager: nonfungiblePositionManager,
      tokenIn: weth,
      tokenOut: usdc,
      fee: fee,
      tickLower: tickLower,
      tickUpper: tickUpper
    });

  function setUp() public {
    // Deploy tokens
    sto = new STO(bytes32('merkle_root'));
    boot = new BaseToken('Bootstap', 'BOOT');
    blp = new BaseToken('Boost LP', 'BLP');
    exit = new BaseToken('Exit Liquidity', 'EXIT');
    nft = new NFT('Bond Data', 'BND', 0);

    // Setup Exit Liquidity
    uint256 amountExit = _tokenAmount(address(exit), 10);
    uint256 amountUSDC = _tokenAmount(usdc, 10);
    exit.mint(address(this), amountExit);
    deal(usdc, address(this), amountUSDC);
    lp = _setUpExitLiquidity(amountExit, amountUSDC);

    // Deploy dependency contracts
    masterchef0 = new Masterchef(weth, REWARDS_DURATION);
    masterchef1 = new Masterchef(weth, REWARDS_DURATION);
    masterchef2 = new MasterchefExit(address(exit), REWARDS_DURATION);

    feeSplitter = address(new FeeSplitter(address(masterchef0), address(masterchef1), vm.envAddress('SWAPPER')));

    IExit10.DeployParams memory params = IExit10.DeployParams({
      NFT: address(nft),
      STO: address(sto),
      BOOT: address(boot),
      BLP: address(blp),
      EXIT: address(exit),
      masterchef: address(masterchef2),
      feeSplitter: feeSplitter,
      bootstrapPeriod: bootstrapPeriod,
      accrualParameter: accrualParameter,
      lpPerUSD: lpPerUSD
    });

    exit10 = new Exit10(baseParams, params);

    sto.setExit10(address(exit10));
    nft.setExit10(address(exit10));
    FeeSplitter(feeSplitter).setExit10(address(exit10));
    boot.transferOwnership(address(exit10));
    blp.transferOwnership(address(exit10));
    exit.transferOwnership(address(exit10));

    deployTime = block.timestamp;

    uint256 initialBalanceWeth = _tokenAmount(weth, 10);
    uint256 initialBalanceUsdc = _tokenAmount(usdc, 10_000);
    _mintAndApprove(weth, initialBalanceWeth, address(exit10));
    _mintAndApprove(usdc, initialBalanceUsdc, address(exit10));
    _maxApprove(weth, address(UNISWAP_V3_ROUTER));
    _maxApprove(usdc, address(UNISWAP_V3_ROUTER));
  }

  function testSetupMasterchef() public {
    _setMasterchefs(feeSplitter);
    assertTrue(Masterchef(masterchef0).poolLength() == 2, 'Check mc0 pool length');
    assertTrue(Masterchef(masterchef1).poolLength() == 1, 'Check mc1 pool length');
  }

  function _setMasterchefs(address _rewardDistributor) internal {
    masterchef0.add(50, address(sto));
    masterchef0.add(50, address(boot));
    masterchef1.add(100, address(blp));
    masterchef2.add(100, lp);
    masterchef0.setRewardDistributor(_rewardDistributor);
    masterchef1.setRewardDistributor(_rewardDistributor);
    masterchef0.renounceOwnership();
    masterchef1.renounceOwnership();
    masterchef2.renounceOwnership();
  }

  function _dealTokens() internal {
    deal(address(sto), alice, 10_000 ether);
  }

  function _setUpExitLiquidity(uint256 _amountExit, uint256 _amountUSDC) internal returns (address exit_usdc_lp) {
    exit_usdc_lp = UNISWAP_V2_FACTORY.createPair(address(exit), usdc);
    ERC20(usdc).approve(address(UNISWAP_V2_ROUTER), _amountUSDC);
    exit.approve(address(UNISWAP_V2_ROUTER), _amountExit);
    UNISWAP_V2_ROUTER.addLiquidity(address(exit), usdc, _amountExit, _amountUSDC, 0, 0, address(this), block.timestamp);
  }
}
