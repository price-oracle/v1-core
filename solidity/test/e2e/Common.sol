// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4 <0.9.0;

import 'isolmate/interfaces/tokens/IERC20.sol';
import 'isolmate/utils/SafeTransferLib.sol';
import 'keep3r/interfaces/IKeep3rHelper.sol';
import 'uni-v3-core/interfaces/IUniswapV3Factory.sol';
import 'uni-v3-core/interfaces/IUniswapV3Pool.sol';
import 'uni-v3-periphery/interfaces/ISwapRouter.sol';
import 'solidity-utils/test/DSTestPlus.sol';
import 'forge-std/console.sol';

import '@interfaces/IPoolManager.sol';
import '@interfaces/jobs/IKeep3rJob.sol';

import '@contracts/LockManager.sol';
import '@contracts/PoolManagerFactory.sol';
import '@contracts/PoolManagerDeployer.sol';
import '@contracts/LockManagerFactory.sol';
import '@contracts/FeeManager.sol';
import '@contracts/periphery/PriceOracle.sol';
import '@contracts/periphery/LockedWethSecondaryMarket.sol';
import '@contracts/strategies/Strategy.sol';
import '@contracts/jobs/FeeCollectorJob.sol';
import '@contracts/periphery/Bribe.sol';

import '@test/utils/TestConstants.sol';
import '@test/utils/ContractDeploymentAddress.sol';

contract CommonE2EBase is DSTestPlus, TestConstants {
  using SafeTransferLib for IERC20;

  uint256 constant DELTA = 100;
  uint256 constant FORK_BLOCK = 16548402;

  address user1 = label(address(100), 'user1');
  address user2 = label(address(101), 'user2');
  address governance = label(address(103), 'governance');
  address rewardProvider = label(address(104), 'rewardProvider');
  address keeper = label(0x9429cd74A3984396f3117d51cde46ea8e0e21487, 'keeper');
  address keep3rGovernance = label(0x0D5Dc686d0a2ABBfDaFDFb4D0533E886517d4E83, 'keep3rGovernance');

  uint256 userInitialWethBalance = 1_000_000_000 ether;
  uint256 userInitialDaiBalance = 1_000_000_000 ether;
  uint160 sqrtPriceX96 = 1 << 96;
  uint128 liquidity = 1100 ether;
  uint24 poolFee = 500;

  FeeManager feeManager;
  Strategy strategy;
  LockManagerFactory lockManagerFactory;
  PoolManagerFactory poolManagerFactory;
  PoolManagerDeployer poolManagerDeployer;
  FeeCollectorJob feeCollectorJob;
  PriceOracle priceOracle;
  LockedWethSecondaryMarket lockedWethSecondaryMarket;
  Bribe bribe;
  ILockManager lockManager;
  IPoolManager poolManagerDai;
  IPoolManager poolManagerUsdc;

  address eth = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

  IERC20 dai = IERC20(label(0x6B175474E89094C44Da98b954EedeAC495271d0F, 'DAI'));
  IERC20 kp3r = IERC20(label(0x1cEB5cB57C4D4E2b2433641b95Dd330A33185A44, 'KP3R'));
  IERC20 usdc = IERC20(label(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48, 'USDC'));
  IERC20 aave = IERC20(label(0x7Fc66500c84A76Ad7e9c93437bFc5Ac33E2DDaE9, 'AAVE'));
  IERC20 yfi = IERC20(label(0x0bc529c00C6401aEF6D220BE8C6Ea1667F6Ad93e, 'YFI'));
  IERC20 weth = IERC20(label(WETH_ADDRESS, 'WETH'));

  ISwapRouter uniswapRouter = ISwapRouter(label(0xE592427A0AEce92De3Edee1F18E0157C05861564, 'UniswapV3Router'));
  IKeep3r keep3r = IKeep3r(label(0xeb02addCfD8B773A5FFA6B9d1FE99c566f8c44CC, 'Keep3rV2'));
  IKeep3rHelper keep3rHelper = IKeep3rHelper(label(0xeDDe080E28Eb53532bD1804de51BD9Cd5cADF0d4, 'Keep3rHelper'));
  IUniswapV3Pool daiEthPool = IUniswapV3Pool(label(0x60594a405d53811d3BC4766596EFD80fd545A270, 'DAI-ETH'));
  IUniswapV3Pool daiUsdtPool = IUniswapV3Pool(label(0x6f48ECa74B38d2936B02ab603FF4e36A6C0E3A77, 'DAI-USDT'));

  function setUp() public virtual {
    vm.createSelectFork(vm.rpcUrl('mainnet'), FORK_BLOCK);

    // Transfer some DAI, WETH and KP3R to user and governance
    deal(address(dai), user1, userInitialDaiBalance);
    deal(address(dai), user2, userInitialDaiBalance);
    deal(address(dai), governance, userInitialDaiBalance);
    deal(address(weth), user1, userInitialDaiBalance);
    deal(address(weth), user2, userInitialDaiBalance);
    deal(address(weth), governance, userInitialDaiBalance);
    deal(address(kp3r), governance, userInitialDaiBalance);
    deal(address(usdc), governance, userInitialDaiBalance);
    deal(address(aave), governance, userInitialDaiBalance);
    deal(address(yfi), governance, userInitialDaiBalance);
    deal(address(weth), rewardProvider, userInitialDaiBalance);
    deal(address(dai), rewardProvider, userInitialDaiBalance);

    // Deploy every contract needed
    vm.startPrank(governance);

    feeManager = FeeManager(ContractDeploymentAddress.addressFrom(governance, 3));
    priceOracle = PriceOracle(ContractDeploymentAddress.addressFrom(governance, 4));
    poolManagerDeployer = PoolManagerDeployer(ContractDeploymentAddress.addressFrom(governance, 5));

    strategy = new Strategy(); // nonce 1
    label(address(strategy), 'Strategy');

    lockManagerFactory = new LockManagerFactory(); // nonce 2
    label(address(lockManagerFactory), 'LockManagerFactory');

    poolManagerFactory = new PoolManagerFactory(
      strategy,
      feeManager,
      lockManagerFactory,
      priceOracle,
      poolManagerDeployer,
      UNISWAP_V3_FACTORY,
      POOL_BYTECODE_HASH,
      weth,
      governance
    ); // nonce 3
    label(address(poolManagerFactory), 'PoolManagerFactory');

    feeManager = new FeeManager(poolManagerFactory, governance, weth); // nonce 4
    label(address(feeManager), 'FeeManager');

    priceOracle = new PriceOracle(poolManagerFactory, UNISWAP_V3_FACTORY, POOL_BYTECODE_HASH, weth); // nonce 5
    label(address(priceOracle), 'PriceOracle');

    poolManagerDeployer = new PoolManagerDeployer(poolManagerFactory); // nonce 6
    label(address(poolManagerDeployer), 'PoolManagerDeployer');

    poolManagerDai = _createPoolManager(dai); // nonce 7
    label(address(poolManagerDai), 'PoolManagerDAI');

    poolManagerUsdc = _createPoolManager(usdc); // nonce 8
    label(address(poolManagerUsdc), 'PoolManagerUSDC');

    lockManager = poolManagerDai.lockManager();
    label(address(lockManager), 'LockManager');

    lockedWethSecondaryMarket = new LockedWethSecondaryMarket(poolManagerFactory, weth); // nonce 9
    label(address(lockedWethSecondaryMarket), 'LockedWethSecondaryMarket');

    bribe = new Bribe(poolManagerFactory); // nonce 10
    label(address(bribe), 'Bribe');

    vm.stopPrank();
  }

  /// @notice Adding job to the Keep3r network and providing credits
  function _setUpJob(IKeep3rJob job) internal {
    vm.startPrank(keep3rGovernance);

    // See if the job is already added
    address[] memory jobs = keep3r.jobs();
    bool added;
    for (uint256 _i; _i < jobs.length; _i++) {
      added = added || jobs[_i] == address(job);
    }

    // Add and fund if not added, otherwise just fund
    if (!added) keep3r.addJob(address(job));
    keep3r.forceLiquidityCreditsToJob(address(job), keep3r.liquidityMinimum() * 10);
    vm.stopPrank();
  }

  function _lockWeth(address who, uint256 amount) internal {
    vm.startPrank(who);
    weth.approve(address(lockManager), amount);
    lockManager.lock(amount);
    vm.stopPrank();
  }

  function _claimRewards(address who) internal returns (uint256 _rewardWeth, uint256 _rewardToken) {
    vm.prank(who);
    (_rewardWeth, _rewardToken) = lockManager.claimRewards(who);
  }

  function _claimableRewards(address who) internal returns (uint256 _rewardWeth, uint256 _rewardToken) {
    vm.prank(who);
    (_rewardWeth, _rewardToken) = lockManager.claimable(who);
  }

  function _addRewards(uint256 amountWeth, uint256 amountToken) internal {
    vm.startPrank(rewardProvider);
    weth.approve(address(lockManager), amountWeth);
    dai.approve(address(lockManager), amountToken);
    lockManager.addRewards(amountWeth, amountToken);
    vm.stopPrank();
  }

  function _createPoolManager(IERC20 token) internal returns (IPoolManager _poolManager) {
    _poolManager = _createPoolManager(token, poolFee);
  }

  function _createPoolManager(IERC20 token, uint24 fee) internal returns (IPoolManager _poolManager) {
    // Pre-calculate the address of UniswapV3 Pool and the pool manager to approve the pool.
    IUniswapV3Pool _pool = ContractDeploymentAddress.getTheoreticalUniPool(weth, token, fee, UNISWAP_V3_FACTORY);
    _poolManager = ContractDeploymentAddress.getTheoreticalPoolManager(poolManagerDeployer, _pool);

    uint160 _sqrtPriceX96 = sqrtPriceX96;
    if (UNISWAP_V3_FACTORY.getPool(address(weth), address(token), fee) != address(0)) {
      // The pool exists, we're going to use the current sqrt price
      (_sqrtPriceX96, , , , , , ) = _pool.slot0();
    }

    // Increase allowance for the pool manager
    _callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, address(_poolManager), type(uint256).max));
    weth.approve(address(_poolManager), type(uint256).max);

    // Creates the pool manager WETH/Tokens
    _poolManager = poolManagerFactory.createPoolManager(token, fee, liquidity, _sqrtPriceX96);
    label(address(_poolManager.POOL()), string(abi.encodePacked('WETH-', token.symbol())));
  }

  function _callOptionalReturn(IERC20 _token, bytes memory _data) internal {
    // We need to perform a low level call here, to bypass Solidity's return data size checking mechanism, since
    // we're implementing it ourselves. We use {Address.functionCall} to perform this call, which verifies that
    // the target address contains contract code and also asserts for success in the low-level call

    // solhint-disable avoid-low-level-calls
    (, bytes memory _returndata) = address(_token).call(_data);
    if (_returndata.length > 0) {
      // Return data is optional
      // solhint-disable reason-string
      require(abi.decode(_returndata, (bool)), 'SafeERC20: ERC20 operation did not succeed');
    }
  }

  function _swap(
    IERC20 _tokenIn,
    IERC20 _tokenOut,
    uint256 _swapSize
  ) internal {
    return _swap(_tokenIn, _tokenOut, _swapSize, true);
  }

  /// @notice Performs the swaps with given tokens and pre-defined fees, recipient, etc.
  /// @param _tokenIn The base token
  /// @param _tokenOut The quote token
  /// @param _swapSize Swap size in wei
  /// @param _mineBlock Should mine a block after swap
  function _swap(
    IERC20 _tokenIn,
    IERC20 _tokenOut,
    uint256 _swapSize,
    bool _mineBlock
  ) internal {
    ISwapRouter.ExactInputSingleParams memory _swapParams = ISwapRouter.ExactInputSingleParams({
      tokenIn: address(_tokenIn),
      tokenOut: address(_tokenOut),
      fee: poolFee,
      recipient: user1,
      deadline: block.timestamp + 3600,
      amountIn: _swapSize,
      amountOutMinimum: 0,
      sqrtPriceLimitX96: 0
    });

    uniswapRouter.exactInputSingle(_swapParams);
    if (_mineBlock) mineBlock();
  }

  function _performMultipleSwaps(
    IERC20 _tokenIn,
    IERC20 _tokenOut,
    uint256 _swapSize,
    uint256 _numberOfSwaps
  ) internal {
    _callOptionalReturn(_tokenIn, abi.encodeWithSelector(_tokenIn.approve.selector, address(uniswapRouter), type(uint256).max));
    _callOptionalReturn(_tokenOut, abi.encodeWithSelector(_tokenOut.approve.selector, address(uniswapRouter), type(uint256).max));

    // _swapSize cannot be the same for both directions
    // For instance, swapping 1 WETH to DAI and 1 DAI to WETH multiple times will imbalance the pool
    // We need to find out the exact amount of tokenOut received from the first swap
    uint256 _swapSizeTokenOut;
    uint256 _balanceBefore = _tokenOut.balanceOf(user1);

    // Make some trades
    for (uint16 _i; _i < _numberOfSwaps; _i++) {
      // Evenly distributing trades in both directions to keep the pool balanced
      // direction is the same as isWethToken0 for concentrated positions
      if (_i % 2 == 0) {
        _swap(_tokenIn, _tokenOut, _swapSize);
      } else {
        _swap(_tokenOut, _tokenIn, _swapSizeTokenOut);
      }

      if (_i == 0) {
        // Watch out for precision errors here, _swapSizeTokenOut must be > 0
        _swapSizeTokenOut = _tokenOut.balanceOf(user1) - _balanceBefore;
      }
    }
  }

  function _manipulatePool(IPoolManager _poolManager) internal returns (uint16 _manipulatedIndex, uint16 _period) {
    vm.startPrank(user1);
    IUniswapV3Pool _pool = _poolManager.POOL();
    IERC20 _token = _poolManager.TOKEN();

    // Save the starting observation index
    (, , uint16 _observationIndexBefore, uint16 _observationCardinality, , , ) = _pool.slot0();

    // Approve the router to spend user's WETH and non-WETH token
    weth.approve(address(uniswapRouter), type(uint256).max);
    _token.approve(address(uniswapRouter), type(uint256).max);

    // Saving the token balance to swap back exactly what was received from the pool
    uint256 balanceBefore = _token.balanceOf(user1);

    // Trade a lot of WETH or tokens in the pool
    uint256 _swapAmount = 750 ether;
    _swap(weth, _token, _swapAmount);
    _swap(weth, _token, _swapAmount);

    // Save the manipulated index
    _manipulatedIndex = (_observationIndexBefore + 1) % _observationCardinality;

    // The pool is manipulated now
    assertTrue(priceOracle.isManipulated(_pool));

    // Arbitrage back
    _swap(_token, weth, _token.balanceOf(user1) - balanceBefore);

    // Calculate the number of observations between the manipulated and non-manipulated indexes
    (, , uint16 _observationIndex, , , , ) = _pool.slot0();

    if (_observationIndex > _manipulatedIndex) {
      _period = _observationIndex - _manipulatedIndex;
    } else {
      _period = _observationCardinality + _observationIndex - _manipulatedIndex;
    }

    // Should be NOT manipulated
    assertFalse(priceOracle.isManipulated(_pool));
    vm.stopPrank();
  }

  function _manipulatePoolTick(IPoolManager _poolManager) internal returns (uint256 _arbitrageBackAmount) {
    vm.startPrank(user1);
    IUniswapV3Pool _pool = _poolManager.POOL();
    IERC20 _token = _poolManager.TOKEN();

    // Approve the router to spend user's WETH and non-WETH token
    weth.approve(address(uniswapRouter), type(uint256).max);
    _token.approve(address(uniswapRouter), type(uint256).max);

    // Saving the token balance to swap back exactly what was received from the pool
    uint256 balanceBefore = _token.balanceOf(user1);

    // Trade a lot of WETH or tokens in the pool
    _swap(weth, _token, weth.balanceOf(user1) / 2, false);

    // The pool is manipulated now
    assertTrue(priceOracle.isManipulated(_pool));

    // Arbitrage back
    _arbitrageBackAmount = _token.balanceOf(user1) - balanceBefore;

    vm.stopPrank();
  }

  function _arbitragePoolBack(IPoolManager _poolManager, uint256 _arbitrageBackAmount) internal {
    vm.startPrank(user1);
    IUniswapV3Pool _pool = _poolManager.POOL();
    IERC20 _token = _poolManager.TOKEN();

    // Arbitrage back
    _swap(_token, weth, _arbitrageBackAmount, false);

    // The pool is not manipulated now
    assertFalse(priceOracle.isManipulated(_pool));

    vm.stopPrank();
  }

  function _quoteUniswap(
    uint128 _baseAmount,
    IERC20 _baseToken,
    IERC20 _quoteToken
  ) internal view returns (uint256 _quote) {
    address _pool = UNISWAP_V3_FACTORY.getPool(address(_baseToken), address(_quoteToken), poolFee);
    (int24 _timeWeightedAverageTick, ) = _consultDefaultTimeWindow(address(_pool));
    _quote = OracleLibrary.getQuoteAtTick(_timeWeightedAverageTick, _baseAmount, address(_baseToken), address(_quoteToken));
  }

  function _consultDefaultTimeWindow(address _poolAddress) internal view returns (int24 _arithmeticMeanTick, uint128 _harmonicMeanLiquidity) {
    uint32[] memory _secondsAgos = new uint32[](2);
    _secondsAgos[0] = 12 minutes;
    _secondsAgos[1] = 2 minutes;
    uint32 timeDelta = _secondsAgos[0] - _secondsAgos[1];

    (int56[] memory _tickCumulatives, uint160[] memory _secondsPerLiquidityCumulativeX128s) = IUniswapV3Pool(_poolAddress).observe(_secondsAgos);

    int56 _tickCumulativesDelta = _tickCumulatives[1] - _tickCumulatives[0];
    uint160 _secondsPerLiquidityCumulativesDelta = _secondsPerLiquidityCumulativeX128s[1] - _secondsPerLiquidityCumulativeX128s[0];

    _arithmeticMeanTick = int24(_tickCumulativesDelta / int32(timeDelta));

    // Always round to negative infinity
    if (_tickCumulativesDelta < 0 && (_tickCumulativesDelta % int32(timeDelta) != 0)) _arithmeticMeanTick--;

    uint192 _secondsAgoX160 = uint192(timeDelta);
    _harmonicMeanLiquidity = uint128(_secondsAgoX160 / (uint192(_secondsPerLiquidityCumulativesDelta) << 32));
  }

  function mineBlock() internal {
    vm.warp(block.timestamp + BLOCK_TIME);
    vm.roll(block.number + 1);
  }
}
