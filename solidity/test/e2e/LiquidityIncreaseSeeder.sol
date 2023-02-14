// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4 <0.9.0;

import 'uni-v3-core/libraries/SqrtPriceMath.sol';
import '@test/e2e/Common.sol';

contract E2ELiquidityIncreaseSeeder is CommonE2EBase {
  IUniswapV3Pool _pool;
  IPoolManager _poolManager;
  IERC20 _token;

  uint256 priceOracleChange = uint256(IPoolManagerGovernor.Methods.PriceOracleChange);
  int24 _tickUpper;
  int24 _tickLower;
  uint160 _sqrtPriceX96;

  uint256 internal constant _SLIPPAGE_PERCENTAGE = 2_000;
  uint256 internal constant _DISTRIBUTION_BASE = 100_000;

  function setUp() public override {
    super.setUp();

    _poolManager = poolManagerDai;
    _pool = _poolManager.POOL();
    _token = _poolManager.TOKEN();

    (_sqrtPriceX96, , , , , , ) = _pool.slot0();
    _tickUpper = MAX_TICK - (MAX_TICK % _pool.tickSpacing());
    _tickLower = -_tickUpper;

    // Approves the transfers from the user for DAI and WETH
    vm.startPrank(user1);
    weth.approve(address(_poolManager), type(uint256).max);
    dai.approve(address(_poolManager), type(uint256).max);
    vm.stopPrank();
  }

  function testE2EDonorIncreasesFullRange(uint128 liquidityToAdd) public {
    vm.assume(liquidityToAdd > DELTA);

    // Check that the user has enough WETH and token
    uint256 _maxAmount0 = LiquidityAmounts08.getAmount0ForLiquidity(_sqrtPriceX96, MAX_SQRT_RATIO, liquidityToAdd);
    uint256 _maxAmount1 = LiquidityAmounts08.getAmount1ForLiquidity(MIN_SQRT_RATIO, _sqrtPriceX96, liquidityToAdd);

    if (_poolManager.IS_WETH_TOKEN0()) {
      vm.assume(weth.balanceOf(user1) > _maxAmount0);
      vm.assume(_token.balanceOf(user1) > _maxAmount1);
    } else {
      vm.assume(weth.balanceOf(user1) > _maxAmount1);
      vm.assume(_token.balanceOf(user1) > _maxAmount0);
    }

    // User1 has't provided to full range yet
    assertApproxEqAbs(_poolManager.seederBalance(user1), 0, DELTA);
    uint256 liquidityBefore = _pool.liquidity();

    // Increases the full range of pool manager WETH/DAI as user1
    vm.prank(user1);
    _poolManager.increaseFullRangePosition(user1, liquidityToAdd, _sqrtPriceX96);

    // The balance of User1 as a seeder has to be increased
    assertApproxEqAbs(_poolManager.seederBalance(user1), liquidityToAdd, DELTA);

    // The liquidity has to be incremented
    assertApproxEqAbs(_pool.liquidity(), liquidityBefore + liquidityToAdd, DELTA);
  }

  function testE2EIncreasesFullRangePoolManipulated(uint128 liquidityToAdd) public {
    // Save the current liquidity amount
    uint256 liquidityBefore = _pool.liquidity();

    // Reverts if the UniswapV3 Pool is manipulated
    vm.expectRevert(IPoolManager.PoolManager_PoolManipulated.selector);

    // Try to increase the full-range position with a sqrt price that differs too much from the current price in the pool
    uint256 _maxSlippage = PRBMath.mulDiv(_sqrtPriceX96, _SLIPPAGE_PERCENTAGE, _DISTRIBUTION_BASE);
    vm.prank(user1);
    _poolManager.increaseFullRangePosition(user1, liquidityToAdd, _sqrtPriceX96 + uint160(_maxSlippage) + 1);

    // The liquidity should not change if the pool is manipulated
    assertEq(_pool.liquidity(), liquidityBefore);
  }
}
