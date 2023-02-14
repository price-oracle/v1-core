// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4 <0.9.0;

import 'uni-v3-core/interfaces/IUniswapV3Pool.sol';
import 'uni-v3-core/libraries/TickMath.sol';
import 'solidity-utils/test/DSTestPlus.sol';

import '@interfaces/strategies/IStrategy.sol';
import '@contracts/utils/GasCheckLib.sol';
import '@test/utils/TestConstants.sol';

// The contract is needed for tests with `expectRevert` because it ignores calls to the library
contract GasCheckLibForTest {
  function collectFromFullRangePosition(
    IUniswapV3Pool _pool,
    IPriceOracle _priceOracle,
    int24 _tickLower,
    int24 _tickUpper,
    uint256 _collectMultiplier,
    bool _isWethToken0
  ) public returns (uint256 _amount0, uint256 _amount1) {
    (_amount0, _amount1) = GasCheckLib.collectFromFullRangePosition(
      _pool,
      _priceOracle,
      _collectMultiplier,
      _tickLower,
      _tickUpper,
      _isWethToken0
    );
  }

  function collectFromConcentratedPosition(
    IUniswapV3Pool _pool,
    uint160 _sqrtPriceX96,
    uint256 _collectMultiplier,
    uint256 _slot0CostPerPosition,
    bool _isWethToken0,
    IStrategy.Position memory _position
  ) public returns (uint256 _amount0, uint256 _amount1) {
    (_amount0, _amount1) = GasCheckLib.collectFromConcentratedPosition(
      _pool,
      _sqrtPriceX96,
      _collectMultiplier,
      _slot0CostPerPosition,
      _position.lowerTick,
      _position.upperTick,
      _isWethToken0
    );
  }
}

abstract contract Base is DSTestPlus, TestConstants {
  IPriceOracle mockPriceOracle = IPriceOracle(mockContract('mockPriceOracle'));
  IUniswapV3Pool mockPool = IUniswapV3Pool(mockContract('mockPool'));
  GasCheckLibForTest mockGasCheckLib;

  function setUp() public virtual {
    vm.mockCall(address(mockPriceOracle), abi.encodeWithSignature('isManipulated(address)', mockPool), abi.encode(false));
    vm.mockCall(address(mockPool), abi.encodeWithSelector(IUniswapV3PoolActions.burn.selector), abi.encode(0, 0));
    mockGasCheckLib = new GasCheckLibForTest();
  }
}

contract UnitGasCheckLibCollectFromFullRangePosition is Base {
  uint256 collectMultiplier = 50;

  function testOverflowAndUnderflow(
    int24 tickUpper,
    uint160 sqrtPriceX96,
    bool isWethToken0
  ) public {
    vm.assume(tickUpper > MIN_TICK && tickUpper < MAX_TICK);
    vm.assume(sqrtPriceX96 > MIN_SQRT_RATIO && sqrtPriceX96 < MAX_SQRT_RATIO);

    int24 tickLower = -tickUpper;

    vm.mockCall(
      address(mockPool),
      abi.encodeWithSelector(
        IUniswapV3PoolActions.collect.selector,
        address(mockGasCheckLib),
        tickLower,
        tickUpper,
        type(uint128).max,
        type(uint128).max
      ),
      abi.encode(type(uint120).max, type(uint120).max)
    );

    vm.mockCall(address(mockPool), abi.encodeWithSelector(IUniswapV3PoolState.slot0.selector), abi.encode(sqrtPriceX96, 0, 0, 0, 0, 0, false));

    mockGasCheckLib.collectFromFullRangePosition(mockPool, mockPriceOracle, tickLower, tickUpper, collectMultiplier, isWethToken0);
  }

  function testRevertIfSmallCollect(int24 tickUpper, bool isWethToken0) public {
    vm.assume(tickUpper > MIN_TICK && tickUpper < MAX_TICK);

    // With 1:1 price ratio neither token represents the majority of the collected fees
    uint160 sqrtPriceX96 = TickMath.getSqrtRatioAtTick(0);
    int24 tickLower = -tickUpper;

    vm.mockCall(
      address(mockPool),
      abi.encodeWithSelector(
        IUniswapV3PoolActions.collect.selector,
        address(mockGasCheckLib),
        tickLower,
        tickUpper,
        type(uint128).max,
        type(uint128).max
      ),
      abi.encode(1, 1)
    );

    vm.mockCall(address(mockPool), abi.encodeWithSelector(IUniswapV3PoolState.slot0.selector), abi.encode(sqrtPriceX96, 0, 0, 0, 0, 0, false));

    vm.expectRevert(GasCheckLib.GasCheckLib_InsufficientFees.selector);
    mockGasCheckLib.collectFromFullRangePosition(mockPool, mockPriceOracle, tickLower, tickUpper, collectMultiplier, isWethToken0);
  }

  function testRevertIfPoolManipulated(int24 tickUpper, bool isWethToken0) public {
    vm.assume(tickUpper > MIN_TICK && tickUpper < MAX_TICK);
    int24 tickLower = -tickUpper;

    vm.mockCall(address(mockPriceOracle), abi.encodeWithSignature('isManipulated(address)', mockPool), abi.encode(true));

    vm.expectRevert(GasCheckLib.GasCheckLib_PoolManipulated.selector);
    mockGasCheckLib.collectFromFullRangePosition(mockPool, mockPriceOracle, tickLower, tickUpper, collectMultiplier, isWethToken0);
  }
}

contract UnitGasCheckLibCollectFromConcentratedPosition is Base {
  uint256 collectMultiplier = 1;
  uint256 slot0CostPerPosition = 6200;

  function testOverflowAndUnderflow(
    bool isWethToken0,
    uint160 sqrtPriceX96,
    IStrategy.Position memory position
  ) public {
    vm.assume(sqrtPriceX96 > MIN_SQRT_RATIO && sqrtPriceX96 < MAX_SQRT_RATIO);

    vm.mockCall(
      address(mockPool),
      abi.encodeWithSelector(IUniswapV3PoolActions.burn.selector, position.lowerTick, position.upperTick, 0),
      abi.encode(0, 0)
    );

    vm.mockCall(
      address(mockPool),
      abi.encodeWithSelector(
        IUniswapV3PoolActions.collect.selector,
        address(mockGasCheckLib),
        position.lowerTick,
        position.upperTick,
        type(uint128).max,
        type(uint128).max
      ),
      abi.encode(type(uint120).max, type(uint120).max)
    );

    mockGasCheckLib.collectFromConcentratedPosition(mockPool, sqrtPriceX96, collectMultiplier, slot0CostPerPosition, isWethToken0, position);
  }
}
