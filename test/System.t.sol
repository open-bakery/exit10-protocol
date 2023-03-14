// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import 'forge-std/Test.sol';

import '../src/interfaces/IUniswapV3Factory.sol';
import '../src/interfaces/IUniswapV3Router.sol';
import '@openzeppelin/contracts/utils/Strings.sol';

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

  mapping(address => string) userName;

  uint256 bootstrapPeriod = 2 weeks;
  uint256 accrualParameter = 1 weeks;
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

    // // Deploy dependency contracts
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
    _setMasterchefs(feeSplitter);

    // _setupNames();
  }

  function testScenario_0() public {
    (, , uint256 at0, uint256 at1) = _lockBootstrap(alice, _tokenAmount(usdc, 10_000), _tokenAmount(weth, 10));
    (, , uint256 bt0, uint256 bt1) = _lockBootstrap(bob, _tokenAmount(usdc, 1_000), _tokenAmount(weth, 1));
    (, , uint256 ct0, uint256 ct1) = _lockBootstrap(charlie, _tokenAmount(usdc, 100_000), _tokenAmount(weth, 100));
    _displayTotal('TOTAL BOOTSTRAPPED', at0 + bt0 + ct0, at1 + bt1 + ct1);
    _stake(alice, address(masterchef0), 1, address(boot));
    _stake(bob, address(masterchef0), 1, address(boot));
    _stake(charlie, address(masterchef0), 1, address(boot));
    _generateClaimAndDistributeFees();
    masterchef0.withdraw(0, 0, true, ERC20(usdc).balanceOf(feeSplitter));
    _displayRewardBalanceMasterchefs();
    _displayTreasury();
    skip(bootstrapPeriod);
    uint bondId = _createBond(alice, _tokenAmount(usdc, 100_000), _tokenAmount(weth, 100));
    skip(accrualParameter);
    _generateFees();
    _convertBond(bondId, alice);
    _displayTreasury();
    _lpExit(alice);
    _stake(alice, address(masterchef2), 0, lp);
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

  function _generateFees() internal {
    _generateFees(usdc, weth, _tokenAmount(usdc, 100_000_000));
    // Skips oracle requirement
    skip(60);
    _title('GENERATING FEE');
    _spacer();
  }

  function _generateClaimAndDistributeFees() internal {
    _generateFees();
    exit10.claimAndDistributeFees();

    _title('FEE DISTRIBUTION');
    console.log('Fee Splitter Balance of USDC: ', ERC20(usdc).balanceOf(feeSplitter));
    console.log('Fee Splitter Balance of WETH: ', ERC20(weth).balanceOf(feeSplitter));
    _spacer();
  }

  function _displayRewardBalanceMasterchefs() internal view {
    _displayBalance('Masterchef0', address(masterchef0), weth);
    _displayBalance('Masterchef1', address(masterchef1), weth);
    _displayBalance('Masterchef2', address(masterchef2), address(exit));
  }

  function _lpExit(address _user) internal returns (uint exitAmountAdded, uint usdcAmountAdded, uint liquidity) {
    uint balanceExit = ERC20(exit).balanceOf(_user);
    uint usdcAmount = _tokenAmount(usdc, balanceExit / 1e18);
    deal(usdc, _user, usdcAmount);
    vm.startPrank(_user);
    (exitAmountAdded, usdcAmountAdded, liquidity) = _addLP(balanceExit, usdcAmount);
    vm.stopPrank();

    string memory log0 = string.concat('User: ', userName[_user]);
    string memory log1 = string.concat('EXIT added: ', Strings.toString(balanceExit));
    string memory log2 = string.concat('USDC added: ', Strings.toString(usdcAmountAdded));
    _title('PROVIDING EXIT/USDC LIQUIDITY');
    console.log(log0);
    console.log(log1);
    console.log(log2);
    _spacer();
  }

  function _lockBootstrap(
    address _user,
    uint256 _usdcAmount,
    uint256 _wethAmount
  ) internal returns (uint256 tokenId, uint128 liquidityAdded, uint256 amountAdded0, uint256 amountAdded1) {
    deal(usdc, _user, _usdcAmount);
    deal(weth, _user, _wethAmount);

    vm.startPrank(_user);
    ERC20(weth).approve(address(exit10), _wethAmount);
    ERC20(usdc).approve(address(exit10), _usdcAmount);
    (tokenId, liquidityAdded, amountAdded0, amountAdded1) = exit10.bootstrapLock(
      IUniswapBase.AddLiquidity({
        depositor: _user,
        amount0Desired: _usdcAmount,
        amount1Desired: _wethAmount,
        amount0Min: 0,
        amount1Min: 0,
        deadline: block.timestamp
      })
    );
    vm.stopPrank();

    string memory log0 = string.concat('User: ', userName[_user]);
    string memory log1 = string.concat('USDC Value: ', Strings.toString(_usdcAmount));
    string memory log2 = string.concat('WETH Value: ', Strings.toString(_wethAmount));
    _title('ENTERING BOOTSTRAP PHASE');
    console.log(log0);
    console.log(log1);
    console.log(log2);
    _spacer();
  }

  function _createBond(address _user, uint256 _usdcAmount, uint256 _wethAmount) internal returns (uint _bondId) {
    deal(usdc, _user, _usdcAmount);
    deal(weth, _user, _wethAmount);

    vm.startPrank(_user);
    ERC20(weth).approve(address(exit10), _wethAmount);
    ERC20(usdc).approve(address(exit10), _usdcAmount);
    (_bondId, , , ) = exit10.createBond(
      IUniswapBase.AddLiquidity({
        depositor: _user,
        amount0Desired: _usdcAmount,
        amount1Desired: _wethAmount,
        amount0Min: 0,
        amount1Min: 0,
        deadline: block.timestamp
      })
    );
    vm.stopPrank();

    string memory log0 = string.concat('User: ', userName[_user]);
    string memory log1 = string.concat('Amount USDC: ', Strings.toString(_usdcAmount));
    string memory log2 = string.concat('Amount WETH: ', Strings.toString(_wethAmount));
    _title('CREATING BOND');
    console.log(log0);
    console.log(log1);
    console.log(log2);
    _spacer();
  }

  function _cancelBond(uint _bondId, address _user) internal {
    (uint bondAmount, , , , ) = exit10.getBondData(_bondId);
    vm.startPrank(_user);
    (uint usdcAmount, uint wethAmount) = exit10.cancelBond(
      _bondId,
      IUniswapBase.RemoveLiquidity({
        liquidity: uint128(bondAmount),
        amount0Min: 0,
        amount1Min: 0,
        deadline: block.timestamp
      })
    );
    vm.stopPrank();

    string memory log0 = string.concat('User: ', userName[_user]);
    string memory log1 = string.concat('Bond amount: ', Strings.toString(bondAmount));
    string memory log2 = string.concat('Amount USDC: ', Strings.toString(usdcAmount));
    string memory log3 = string.concat('Amount WETH: ', Strings.toString(wethAmount));
    _title('CANCELLED BOND');
    console.log(log0);
    console.log(log1);
    console.log(log2);
    console.log(log3);
    _spacer();
  }

  function _convertBond(uint _bondId, address _user) internal {
    (uint bondAmount, , , , ) = exit10.getBondData(_bondId);
    vm.startPrank(_user);
    (uint boostTokenAmount, uint exitTokenAmount) = exit10.convertBond(
      _bondId,
      IUniswapBase.RemoveLiquidity({
        liquidity: uint128(bondAmount),
        amount0Min: 0,
        amount1Min: 0,
        deadline: block.timestamp
      })
    );
    vm.stopPrank();

    string memory log0 = string.concat('User: ', userName[_user]);
    string memory log1 = string.concat('Bond amount: ', Strings.toString(bondAmount));
    string memory log2 = string.concat('Amount BLP: ', Strings.toString(boostTokenAmount));
    string memory log3 = string.concat('Amount EXIT: ', Strings.toString(exitTokenAmount));
    _title('BOND CONVERTED');
    console.log(log0);
    console.log(log1);
    console.log(log2);
    console.log(log3);
    _spacer();
  }

  function _stake(address _user, address _mc, uint256 _pid, address _token) internal {
    vm.startPrank(_user);
    uint256 balance = ERC20(_token).balanceOf(_user);
    ERC20(_token).approve(address(_mc), balance);
    AMasterchefBase(_mc).deposit(_pid, balance);
    vm.stopPrank();

    string memory log0 = string.concat('User: ', userName[_user]);
    string memory log1 = string.concat('Amount: ', Strings.toString(balance));
    _title('STAKING IN MASTERCHEF');
    console.log(log0);
    console.log(log1);
    _spacer();
  }

  function _displayTreasury() internal view {
    (uint256 pending, uint256 reserve, uint256 exitBucket, uint256 bootstrap) = exit10.getTreasury();
    _title('TREASURY BREAKDOWN');
    console.log('Pending Bucket: ', pending);
    console.log('Reserve Bucket: ', reserve);
    console.log('Exit Bucket: ', exitBucket);
    console.log('Bootstrap Bucket: ', bootstrap);
    _spacer();
  }

  function _displayBalance(string memory _targetTitle, address _target, address _token) internal view {
    string memory log0 = string.concat(
      _targetTitle,
      ' - balance of ',
      ERC20(_token).symbol(),
      ': ',
      Strings.toString(ERC20(_token).balanceOf(_target))
    );
    console.log(log0);
  }

  function _displayBalances(
    string memory _targetTitle,
    address _target,
    address _tokenA,
    address _tokenB
  ) internal view {
    _displayBalance(_targetTitle, _target, _tokenA);
    _displayBalance(_targetTitle, _target, _tokenB);
  }

  function _displayTotal(string memory _titleText, uint256 _amountUSDC, uint256 _amountWETH) internal view {
    _title(_titleText);
    console.log('Deposited USDC: ', _amountUSDC);
    console.log('Deposited WETH: ', _amountWETH);
    _spacer();
  }

  function _title(string memory _titleText) internal view {
    console.log(string.concat('-----', _titleText, '-----'));
  }

  function _spacer() internal view {
    console.log('----------------------------------');
  }

  function _setupNames() internal {
    userName[alice] = 'Alice';
    userName[bob] = 'Bob';
    userName[charlie] = 'Charlie';
  }

  function _addLP(
    uint256 _amountExit,
    uint256 _amountUSDC
  ) internal returns (uint usdcAmountAdded, uint exitAmountAdded, uint lpAmount) {
    ERC20(usdc).approve(address(UNISWAP_V2_ROUTER), _amountUSDC);
    exit.approve(address(UNISWAP_V2_ROUTER), _amountExit);
    (exitAmountAdded, usdcAmountAdded, lpAmount) = UNISWAP_V2_ROUTER.addLiquidity(
      address(exit),
      usdc,
      _amountExit,
      _amountUSDC,
      0,
      0,
      address(this),
      block.timestamp
    );
  }

  function _setUpExitLiquidity(uint256 _amountExit, uint256 _amountUSDC) internal returns (address exit_usdc_lp) {
    exit_usdc_lp = UNISWAP_V2_FACTORY.createPair(address(exit), usdc);
    _addLP(_amountExit, _amountUSDC);
  }
}
