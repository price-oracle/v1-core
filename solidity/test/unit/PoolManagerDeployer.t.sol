// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4 <0.9.0;

import 'solidity-utils/test/DSTestPlus.sol';

import '@contracts/PoolManagerDeployer.sol';
import '@interfaces/IPoolManagerFactory.sol';
import '@test/utils/TestConstants.sol';
import '@test/utils/ContractDeploymentAddress.sol';

abstract contract Base is DSTestPlus, TestConstants {
  IPoolManagerFactory mockPoolManagerFactory = IPoolManagerFactory(mockContract('mockPoolManagerFactory'));
  IFeeManager mockFeeManager = IFeeManager(mockContract('mockFeeManager'));
  IPriceOracle mockPriceOracle = IPriceOracle(mockContract('mockPriceOracle'));
  IStrategy mockStrategy = IStrategy(mockContract('mockStrategy'));
  ILockManagerFactory mockLockManagerFactory = ILockManagerFactory(mockContract('mockLockManagerFactory'));
  ILockManager mockLockManager = ILockManager(mockContract('mockLockManager'));
  IERC20 mockToken = IERC20(mockContract('mockToken'));
  IERC20 mockWeth = IERC20(mockContract(WETH_ADDRESS, 'mockWeth'));

  IUniswapV3Pool mockPool;
  PoolManagerDeployer poolManagerDeployer;

  address admin = label(newAddress(), 'admin');
  uint24 fee = 500;
  uint160 sqrtPriceX96 = 5;

  function setUp() public virtual {
    mockPool = IUniswapV3Pool(
      mockContract(address(ContractDeploymentAddress.getTheoreticalUniPool(mockToken, mockWeth, fee, UNISWAP_V3_FACTORY)), 'mockPool')
    );

    vm.mockCall(address(mockPoolManagerFactory), abi.encodeWithSelector(IPoolManagerFactory.WETH.selector), abi.encode(mockWeth));

    vm.mockCall(
      address(mockPoolManagerFactory),
      abi.encodeWithSelector(IPoolManagerFactory.constructorArguments.selector),
      abi.encode(UNISWAP_V3_FACTORY, POOL_BYTECODE_HASH, mockWeth, mockToken, mockFeeManager, mockPriceOracle, admin, fee, sqrtPriceX96)
    );

    vm.mockCall(address(UNISWAP_V3_FACTORY), abi.encodeWithSelector(IUniswapV3Factory.createPool.selector), abi.encode(mockPool));
    vm.mockCall(address(mockPoolManagerFactory), abi.encodeWithSelector(IPoolManagerFactory.strategy.selector), abi.encode(mockStrategy));

    // mock calls to create the lock manager
    vm.mockCall(
      address(mockPoolManagerFactory),
      abi.encodeWithSelector(IPoolManagerFactory.lockManagerFactory.selector),
      abi.encode(mockLockManagerFactory)
    );

    vm.mockCall(
      address(mockLockManagerFactory),
      abi.encodeWithSelector(ILockManagerFactory.createLockManager.selector),
      abi.encode(mockLockManager)
    );

    // mock needed calls of _increaseFullRangePosition function
    vm.mockCall(address(mockPool), abi.encodeWithSelector(IUniswapV3PoolImmutables.tickSpacing.selector), abi.encode(int24(10)));
    vm.mockCall(address(mockPool), abi.encodeWithSelector(IUniswapV3PoolActions.mint.selector), abi.encode(100, 100));

    vm.prank(address(mockPoolManagerFactory));
    poolManagerDeployer = new PoolManagerDeployer(mockPoolManagerFactory);
  }
}

contract UnitPoolManagerDeployerConstructor is Base {
  function testFactorySendParams() external {
    assertEq(address(poolManagerDeployer.POOL_MANAGER_FACTORY()), address(mockPoolManagerFactory));
  }
}

contract UnitPoolManagerDeployerDeployPoolManager is Base {
  function testRevertIfInvalidPoolManagerFactory() public {
    vm.expectRevert(IPoolManagerDeployer.PoolManagerDeployer_OnlyPoolManagerFactory.selector);

    vm.prank(newAddress());
    poolManagerDeployer.deployPoolManager(mockPool);
  }

  function testDeployPoolManagerForNewPool() public {
    vm.mockCall(address(UNISWAP_V3_FACTORY), abi.encodeWithSelector(IUniswapV3Factory.getPool.selector), abi.encode(address(0)));

    vm.expectCall(address(UNISWAP_V3_FACTORY), abi.encodeWithSelector(IUniswapV3Factory.createPool.selector));
    vm.expectCall(address(mockPool), abi.encodeWithSelector(IUniswapV3PoolActions.initialize.selector));
    vm.expectCall(address(mockPool), abi.encodeWithSelector(IUniswapV3PoolActions.increaseObservationCardinalityNext.selector));

    vm.prank(address(mockPoolManagerFactory));
    IPoolManager poolManager = poolManagerDeployer.deployPoolManager(mockPool);

    assertEq(address(poolManager.POOL_MANAGER_FACTORY()), address(mockPoolManagerFactory));
  }

  function testDeployPoolManagerForExistingPool() public {
    vm.mockCall(address(UNISWAP_V3_FACTORY), abi.encodeWithSelector(IUniswapV3Factory.getPool.selector), abi.encode(address(mockPool)));
    vm.mockCall(address(mockPool), abi.encodeWithSelector(IUniswapV3PoolState.slot0.selector), abi.encode(sqrtPriceX96, 0, 0, 0, 0, 0, false));

    vm.prank(address(mockPoolManagerFactory));
    IPoolManager poolManager = poolManagerDeployer.deployPoolManager(mockPool);

    assertEq(address(poolManager.POOL_MANAGER_FACTORY()), address(mockPoolManagerFactory));
  }
}
