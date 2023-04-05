// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;
import { ERC20 } from '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import { console } from 'forge-std/console.sol';
import { Script } from 'forge-std/Script.sol';
import { Strings } from '@openzeppelin/contracts/utils/Strings.sol';
import { FeeSplitter, ABaseExit10Test } from './ABaseExit10.t.sol';
import { AMasterchefBase } from './AMasterchefBase.t.sol';

contract SystemLogsTest is ABaseExit10Test {
  mapping(address => string) userName;

  function setUp() public override {
    super.setUp();
    _setupNames();
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
    masterchef0.withdraw(0, 0, ERC20(usdc).balanceOf(feeSplitter));
    _displayRewardBalanceMasterchefs();
    _displayTreasury();
    _skip(bootstrapPeriod);
    uint bondId = _createBond(alice, _tokenAmount(usdc, 100_000), _tokenAmount(weth, 100));
    _skip(accrualParameter);
    _generateFees();
    _convertBond(bondId, alice);
    _displayTreasury();
    _lpExit(alice);
    _stake(alice, address(masterchefExit), 0, lp);
    _skip(accrualParameter);
    _claimExitRewards(alice);
    _distributeRewardsToMasterchefs();
  }

  function _skip(uint256 _seconds) internal {
    skip(_seconds);

    _title('TIME TRAVEL');
    console.log('Fastforward: ', _seconds);
    _spacer();
  }

  function _generateFees() internal {
    _generateFees(usdc, weth, _tokenAmount(usdc, 100_000_000));
    // Skips oracle requirement
    skip(ORACLE_SECONDS);
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

  function _distributeRewardsToMasterchefs() internal {
    uint256 prevBalanceMc0 = ERC20(weth).balanceOf(address(masterchef0));
    uint256 prevBalanceMc1 = ERC20(weth).balanceOf(address(masterchef1));
    uint256 usdcToSell = ERC20(usdc).balanceOf(address(feeSplitter));
    uint256 ETHAcquired = FeeSplitter(feeSplitter).updateFees(usdcToSell);
    uint256 depositedRewardsMc0 = ERC20(weth).balanceOf(address(masterchef0)) - prevBalanceMc0;
    uint256 depositedRewardsMc1 = ERC20(weth).balanceOf(address(masterchef1)) - prevBalanceMc1;

    _title('WETH REWARD DISTRIBUTION');
    console.log('Total USDC sold: ', usdcToSell);
    console.log('Total ETH acquired: ', ETHAcquired);
    console.log('Distributed to masterchef0: ', depositedRewardsMc0);
    console.log('Distributed to masterchef1: ', depositedRewardsMc1);
    _spacer();
  }

  function _displayRewardBalanceMasterchefs() internal view {
    _displayBalance('Masterchef0', address(masterchef0), weth);
    _displayBalance('Masterchef1', address(masterchef1), weth);
    _displayBalance('Masterchef2', address(masterchefExit), address(exit));
  }

  function _lpExit(address _user) internal returns (uint _amountAddedExit, uint _amountAddedUsdc, uint _liquidity) {
    uint balanceExit = exit.balanceOf(_user);
    uint amountUsdc = _tokenAmount(usdc, balanceExit / 1e18);
    deal(usdc, _user, amountUsdc);
    vm.startPrank(_user);
    (_amountAddedExit, _amountAddedUsdc, _liquidity) = _addLiquidity(address(exit), usdc, balanceExit, amountUsdc);
    vm.stopPrank();
    ERC20(lp).transfer(_user, _liquidity);

    string memory log0 = string.concat('User: ', userName[_user]);
    string memory log1 = string.concat('EXIT added: ', Strings.toString(_amountAddedExit));
    string memory log2 = string.concat('USDC added: ', Strings.toString(_amountAddedUsdc));
    string memory log3 = string.concat('Liquidity added: ', Strings.toString(_liquidity));
    _title('PROVIDING EXIT/USDC LIQUIDITY');
    console.log(log0);
    console.log(log1);
    console.log(log2);
    console.log(log3);
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
      _addLiquidityParams(_user, _usdcAmount, _wethAmount)
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
    (_bondId, , , ) = exit10.createBond(_addLiquidityParams(_user, _usdcAmount, _wethAmount));
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
    (uint usdcAmount, uint wethAmount) = exit10.cancelBond(_bondId, _removeLiquidityParams(bondAmount));
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
    (uint boostTokenAmount, uint exitTokenAmount) = exit10.convertBond(_bondId, _removeLiquidityParams(bondAmount));
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
    string memory log1 = string.concat('Token Staked: ', ERC20(_token).symbol());
    string memory log2 = string.concat('Amount: ', Strings.toString(balance));
    _title('STAKING IN MASTERCHEF');
    console.log(log0);
    console.log(log1);
    console.log(log2);
    _spacer();
  }

  function _claimExitRewards(address _user) internal {
    uint256 prevExitBalance = exit.balanceOf(_user);
    vm.startPrank(_user);
    masterchefExit.withdraw(0, 0);
    vm.stopPrank();
    uint256 claimedExit = exit.balanceOf(_user) - prevExitBalance;

    string memory log0 = string.concat('User: ', userName[_user]);
    string memory log1 = string.concat('Amount: ', Strings.toString(claimedExit));
    _title('CLAIMED EXIT IN MASTERCHEF');
    console.log(log0);
    console.log(log1);
    _spacer();
  }

  function _claimEthRewards(address _user, address _mc, uint256 _pid) internal {
    uint256 prevWethBalance = ERC20(weth).balanceOf(_user);
    vm.startPrank(_user);
    AMasterchefBase(_mc).withdraw(_pid, 0);
    vm.stopPrank();
    uint256 claimedWeth = ERC20(weth).balanceOf(_user) - prevWethBalance;

    string memory log0 = string.concat('User: ', userName[_user]);
    string memory log1 = string.concat('Amount: ', Strings.toString(claimedWeth));
    _title('CLAIMED WETH IN MASTERCHEF');
    console.log(log0);
    console.log(log1);
    _spacer();
  }

  function _displayTreasury() internal view {
    (uint256 pending, uint256 reserve, uint256 exitBucket, uint256 bootstrap) = exit10.getBuckets();
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

  function _displayInDecimals(address _token, uint256 _amount) internal view returns (string memory) {
    uint256 integer;
    uint256 decimal;
    uint256 decimals = 3;
    decimals = 10 ** decimals;

    integer = _amount / 10 ** ERC20(_token).decimals();
    decimal = ((_amount * decimals) / 10 ** ERC20(_token).decimals()) - (integer * decimals);
    return string.concat(ERC20(_token).symbol(), ': ', Strings.toString(integer), '.', Strings.toString(decimal));
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
}
