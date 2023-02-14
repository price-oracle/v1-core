// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4 <0.9.0;

import 'isolmate/interfaces/tokens/IERC20.sol';
import 'solidity-utils/test/DSTestPlus.sol';

import '@interfaces/IPoolManagerFactory.sol';
import '@interfaces/IPoolManager.sol';
import '@contracts/LockManagerFactory.sol';
import '@test/utils/TestConstants.sol';

abstract contract Base is DSTestPlus, TestConstants {
  address governance = label(address(100), 'governance');

  IERC20 mockWeth = IERC20(mockContract(WETH_ADDRESS, 'mockWeth'));
  IPoolManagerFactory mockPoolManagerFactory = IPoolManagerFactory(mockContract('mockPoolManagerFactory'));
  IPoolManager mockPoolManager = IPoolManager(mockContract('mockPoolManager'));
  IFeeManager mockFeeManager = IFeeManager(mockContract('mockFeeManager'));
  LockManagerFactory lockManagerFactory;
  string mockTokenSymbol = 'TEST';

  function setUp() public virtual {
    lockManagerFactory = new LockManagerFactory();

    vm.mockCall(address(mockPoolManager), abi.encodeWithSelector(IPoolManagerGovernor.feeManager.selector), abi.encode(mockFeeManager));
  }
}

contract UnitLockManagerFactoryCreateLockManager is Base {
  IPoolManager.LockManagerParams lockManagerParams =
    IPoolManager.LockManagerParams({
      fee: 500,
      factory: mockPoolManagerFactory,
      strategy: IStrategy(newAddress()),
      pool: IUniswapV3Pool(newAddress()),
      token: IERC20(newAddress()),
      weth: mockWeth,
      isWethToken0: true,
      governance: governance,
      index: 0
    });

  function setUp() public virtual override {
    super.setUp();

    vm.mockCall(address(lockManagerParams.token), abi.encodeWithSelector(IERC20.symbol.selector), abi.encode(mockTokenSymbol));
    vm.mockCall(
      address(mockPoolManagerFactory),
      abi.encodeWithSelector(IPoolManagerFactory.isChild.selector, address(mockPoolManager)),
      abi.encode(true)
    );
  }

  function testCreatesLockManager() external {
    int24 tickSpacing = 6;
    vm.mockCall(address(lockManagerParams.pool), abi.encodeWithSelector(IUniswapV3PoolImmutables.tickSpacing.selector), abi.encode(tickSpacing));

    vm.prank(address(mockPoolManager));
    ILockManager lockManager = lockManagerFactory.createLockManager(lockManagerParams);

    assertEq(lockManager.FEE(), lockManagerParams.fee);
    assertEq(address(lockManager.POOL_MANAGER_FACTORY()), address(mockPoolManagerFactory));
    assertEq(address(lockManager.STRATEGY()), address(lockManagerParams.strategy));
    assertEq(address(lockManager.POOL_MANAGER()), address(mockPoolManager));
    assertEq(address(lockManager.POOL()), address(lockManagerParams.pool));
    assertEq(address(lockManager.TOKEN()), address(lockManagerParams.token));
    assertEq(address(lockManager.WETH()), address(lockManagerParams.weth));
  }
}
