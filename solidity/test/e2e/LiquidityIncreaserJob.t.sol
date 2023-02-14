// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4 <0.9.0;

import 'uni-v3-core/libraries/SqrtPriceMath.sol';
import '@test/e2e/Common.sol';
import '@contracts/jobs/LiquidityIncreaserJob.sol';

contract E2ELiquidityIncreaserJob is CommonE2EBase {
  LiquidityIncreaserJob liquidityIncreaserJob;
  IPoolManager _poolManager;
  IUniswapV3Pool _pool;
  uint160 _sqrtPriceX96;
  uint256 _wethFees;
  uint256 _tokenFees = 50 ether;
  int24 _tickUpper;
  int24 _tickLower;

  function setUp() public override {
    super.setUp();

    _poolManager = lockManager.POOL_MANAGER();
    _pool = _poolManager.POOL();
    (_sqrtPriceX96, , , , , , ) = _pool.slot0();
    _tickUpper = MAX_TICK - (MAX_TICK % _pool.tickSpacing());
    _tickLower = -_tickUpper;

    uint128 _liquidity = 1 ether;

    if (_poolManager.IS_WETH_TOKEN0()) {
      _wethFees = SqrtPriceMath.getAmount0Delta(_sqrtPriceX96, TickMath.getSqrtRatioAtTick(_tickUpper), _liquidity, false);
    } else {
      _wethFees = SqrtPriceMath.getAmount1Delta(TickMath.getSqrtRatioAtTick(_tickLower), _sqrtPriceX96, _liquidity, false);
    }

    // Increase the amount of fees available for the job
    vm.startPrank(governance);
    weth.transfer(address(feeManager), _wethFees);
    _poolManager.TOKEN().transfer(address(feeManager), _tokenFees);
    vm.stopPrank();

    vm.prank(address(_poolManager));
    feeManager.depositFromPoolManager(_wethFees, _tokenFees);

    // Deploy the job
    liquidityIncreaserJob = new LiquidityIncreaserJob(poolManagerFactory, governance, weth);
    label(address(liquidityIncreaserJob), 'LiquidityIncreaserJob');

    // Make sure the threshold is low enough
    vm.prank(governance);
    liquidityIncreaserJob.setMinIncreaseWeth(_wethFees / 2);

    // approve and fund the job
    _setUpJob(liquidityIncreaserJob);
  }

  // token and WETH amounts should be < than the available fees
  // token and WETH balance after increasing should be < 1% of the initial fees
  function testLiquidityIncrease() public {
    (_sqrtPriceX96, , , , , , ) = _pool.slot0();
    (uint256 _wethForFullRange, uint256 _tokenForFullRange) = feeManager.poolManagerDeposits(_poolManager);
    uint256 _wethAmount = (_wethForFullRange * 203) / 100;
    uint256 _tokenAmount = (_tokenForFullRange * 98) / 100;

    // Calculate by how much we can increase the liquidity in the pool given the amount of fees in the FeeManager
    uint128 maxLiquidity = LiquidityAmounts.getLiquidityForAmounts(
      _sqrtPriceX96,
      TickMath.getSqrtRatioAtTick(_tickLower),
      TickMath.getSqrtRatioAtTick(_tickUpper),
      _poolManager.IS_WETH_TOKEN0() ? _wethAmount : _tokenAmount,
      _poolManager.IS_WETH_TOKEN0() ? _tokenAmount : _wethAmount
    );

    uint128 liquidityBefore = _pool.liquidity();

    // Work
    vm.prank(keeper);
    liquidityIncreaserJob.work(_poolManager, _wethAmount, _tokenAmount);

    (uint256 _wethForFullRangeAfter, uint256 _tokenForFullRangeAfter) = feeManager.poolManagerDeposits(_poolManager);

    assertGt(_wethForFullRange / 100, _wethForFullRangeAfter);
    assertGt(_tokenForFullRange / 100, _tokenForFullRangeAfter);
    assertGt(_pool.liquidity(), liquidityBefore);
    assertApproxEqAbs(liquidityBefore + maxLiquidity, _pool.liquidity(), _pool.liquidity() / 1e12);
  }

  function testRevertIfExcessiveLiquidityLeft() public {
    (uint256 _wethForFullRange, uint256 _tokenForFullRange) = feeManager.poolManagerDeposits(_poolManager);

    uint256 _wethAmount = (_wethForFullRange * 202) / 100; // Just a little bit less should have too much remaining liquidity
    uint256 _tokenAmount = (_tokenForFullRange * 98) / 100;

    // Work
    vm.expectRevert(IFeeManager.FeeManager_ExcessiveLiquidityLeft.selector);
    vm.prank(keeper);
    liquidityIncreaserJob.work(_poolManager, _wethAmount, _tokenAmount);
  }

  function testRevertIfInsufficientIncrease() public {
    (uint256 _wethForFullRange, uint256 _tokenForFullRange) = feeManager.poolManagerDeposits(_poolManager);
    uint256 _wethAmount = (_wethForFullRange * 203) / 100;
    uint256 _tokenAmount = (_tokenForFullRange * 98) / 100;

    // Set unreasonably high minIncreaseWeth
    vm.prank(governance);
    liquidityIncreaserJob.setMinIncreaseWeth(_wethAmount * 1000);

    // The job should revert because the increase is tiny compared to minIncreaseWeth
    vm.expectRevert(ILiquidityIncreaserJob.LiquidityIncreaserJob_InsufficientIncrease.selector);

    // Work
    vm.prank(keeper);
    liquidityIncreaserJob.work(_poolManager, _wethAmount, _tokenAmount);
  }
}
