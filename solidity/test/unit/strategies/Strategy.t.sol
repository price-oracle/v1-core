// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4 <0.9.0;

import 'solidity-utils/test/DSTestPlus.sol';

import '@interfaces/ILockManager.sol';
import '@interfaces/IPoolManagerGovernor.sol';
import '@interfaces/strategies/IStrategy.sol';
import '@contracts/strategies/Strategy.sol';
import '@test/utils/TestConstants.sol';

abstract contract Base is DSTestPlus, TestConstants {
  IUniswapV3Pool mockPool = IUniswapV3Pool(mockContract('mockPool'));
  ILockManager mockLockManager = ILockManager(mockContract('mockLockManager'));
  IPoolManager mockPoolManager = IPoolManager(mockContract('mockPoolManager'));
  IPoolManagerFactory mockPoolManagerFactory = IPoolManagerFactory(mockContract('mockPoolManagerFactory'));
  Strategy mockStrategy;

  uint160 sqrtRatioX96 = MIN_SQRT_RATIO * 10;
  int24 currentTick = 205288;
  int24 tickSpacing = 10;

  function setUp() public {
    vm.mockCall(
      address(mockPoolManager),
      abi.encodeWithSelector(IPoolManagerGovernor.POOL_MANAGER_FACTORY.selector),
      abi.encode(mockPoolManagerFactory)
    );

    vm.mockCall(
      address(mockPool),
      abi.encodeWithSelector(IUniswapV3PoolState.slot0.selector),
      abi.encode(sqrtRatioX96, currentTick, 0, 0, 0, 0, 0)
    );

    mockStrategy = new Strategy();
  }
}

contract UnitStrategyGetPositionToMint is Base {
  function testRevertIfNotEnoughWeth(bool isWethToken0) public {
    IStrategy.LockManagerState memory _lockManagerState = IStrategy.LockManagerState({
      poolManager: mockPoolManager,
      pool: mockPool,
      availableWeth: mockStrategy.MIN_WETH_TO_MINT() - 1,
      isWethToken0: isWethToken0,
      tickSpacing: tickSpacing
    });

    vm.expectRevert(IStrategy.Strategy_NotEnoughWeth.selector);

    mockStrategy.getPositionToMint(_lockManagerState);
  }

  function testReturnPositionToMintWethIsToken0(uint128 availableWeth) public {
    vm.assume(availableWeth > mockStrategy.MIN_WETH_TO_MINT());
    bool isWethToken0 = true;

    IStrategy.LockManagerState memory _lockManagerState = IStrategy.LockManagerState({
      poolManager: mockPoolManager,
      pool: mockPool,
      availableWeth: availableWeth,
      isWethToken0: isWethToken0,
      tickSpacing: tickSpacing
    });
    IStrategy.LiquidityPosition memory _positionToMint = mockStrategy.getPositionToMint(_lockManagerState);

    assertGt(_positionToMint.upperTick, currentTick);
    assertGt(_positionToMint.lowerTick, currentTick);
    assertGt(_positionToMint.liquidity, 0);
  }

  function testReturnPositionToMintWethIsToken1(uint128 availableWeth) public {
    vm.assume(availableWeth > mockStrategy.MIN_WETH_TO_MINT());
    bool isWethToken0 = false;

    IStrategy.LockManagerState memory _lockManagerState = IStrategy.LockManagerState({
      poolManager: mockPoolManager,
      pool: mockPool,
      availableWeth: availableWeth,
      isWethToken0: isWethToken0,
      tickSpacing: tickSpacing
    });
    IStrategy.LiquidityPosition memory _positionToMint = mockStrategy.getPositionToMint(_lockManagerState);

    assertLe(_positionToMint.upperTick, currentTick);
    assertLt(_positionToMint.lowerTick, currentTick);
    assertGt(_positionToMint.liquidity, 0);
  }
}

contract UnitStrategyGetPositionToBurn is Base {
  function testRevertIfPositionNotFarEnoughToLeft(
    IStrategy.Position calldata position,
    uint256 availableWeth,
    int24 currentTick
  ) public {
    int24 upperBurnDiff = mockStrategy.UPPER_BURN_DIFF();
    vm.assume(position.upperTick < type(int24).max - upperBurnDiff);
    vm.assume(currentTick < (position.upperTick + upperBurnDiff));

    vm.mockCall(
      address(mockPool),
      abi.encodeWithSelector(IUniswapV3PoolState.slot0.selector),
      abi.encode(sqrtRatioX96, currentTick, 0, 0, 0, 0, 0)
    );

    bool isWethToken0 = false;
    IStrategy.LockManagerState memory _lockManagerState = IStrategy.LockManagerState({
      poolManager: mockPoolManager,
      pool: mockPool,
      availableWeth: availableWeth,
      isWethToken0: isWethToken0,
      tickSpacing: tickSpacing
    });

    vm.expectRevert(IStrategy.Strategy_NotFarEnoughToLeft.selector);

    mockStrategy.getPositionToBurn(position, 0, _lockManagerState);
  }

  function testRevertIfPositionNotFarEnoughToRight(
    IStrategy.Position calldata position,
    uint256 availableWeth,
    int24 currentTick
  ) public {
    int24 lowerBurnDiff = mockStrategy.LOWER_BURN_DIFF();
    vm.assume(position.lowerTick > lowerBurnDiff);
    vm.assume(currentTick > (position.lowerTick - lowerBurnDiff));

    vm.mockCall(
      address(mockPool),
      abi.encodeWithSelector(IUniswapV3PoolState.slot0.selector),
      abi.encode(sqrtRatioX96, currentTick, 0, 0, 0, 0, 0)
    );

    bool isWethToken0 = true;
    IStrategy.LockManagerState memory _lockManagerState = IStrategy.LockManagerState({
      poolManager: mockPoolManager,
      pool: mockPool,
      availableWeth: availableWeth,
      isWethToken0: isWethToken0,
      tickSpacing: tickSpacing
    });

    vm.expectRevert(IStrategy.Strategy_NotFarEnoughToRight.selector);

    mockStrategy.getPositionToBurn(position, 0, _lockManagerState);
  }

  function testReturnPositionToBurn(
    IStrategy.Position calldata position,
    bool isWethToken0,
    uint256 availableWeth,
    int24 currentTick,
    uint128 liquidity
  ) public {
    if (isWethToken0) {
      int24 lowerBurnDiff = mockStrategy.LOWER_BURN_DIFF();
      vm.assume(position.lowerTick > lowerBurnDiff);
      vm.assume(currentTick < (position.lowerTick - lowerBurnDiff));
    } else {
      int24 upperBurnDiff = mockStrategy.UPPER_BURN_DIFF();
      vm.assume(position.upperTick < type(int24).max - upperBurnDiff);
      vm.assume(currentTick > (position.upperTick + upperBurnDiff));
    }

    vm.mockCall(
      address(mockPool),
      abi.encodeWithSelector(IUniswapV3PoolState.slot0.selector),
      abi.encode(sqrtRatioX96, currentTick, 0, 0, 0, 0, 0)
    );

    IStrategy.LockManagerState memory _lockManagerState = IStrategy.LockManagerState({
      poolManager: mockPoolManager,
      pool: mockPool,
      availableWeth: availableWeth,
      isWethToken0: isWethToken0,
      tickSpacing: tickSpacing
    });
    IStrategy.LiquidityPosition memory _positionToBurn = mockStrategy.getPositionToBurn(position, liquidity, _lockManagerState);

    assertEq(_positionToBurn.upperTick, position.upperTick);
    assertEq(_positionToBurn.lowerTick, position.lowerTick);
    assertEq(_positionToBurn.liquidity, liquidity);
  }
}
