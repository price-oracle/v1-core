// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4 <0.9.0;

import 'uni-v3-core/interfaces/pool/IUniswapV3PoolActions.sol';
import 'uni-v3-core/interfaces/pool/IUniswapV3PoolImmutables.sol';
import 'solidity-utils/interfaces/IRoles.sol';
import 'solidity-utils/test/DSTestPlus.sol';

import '@contracts/PoolManagerFactory.sol';
import '@contracts/utils/LiquidityAmounts08.sol';

import '@test/utils/TestConstants.sol';
import '@test/utils/ContractDeploymentAddress.sol';

contract PoolManagerFactoryForTest is PoolManagerFactory {
  constructor(
    IStrategy _strategy,
    IFeeManager _feeManager,
    ILockManagerFactory _lockManagerFactory,
    IPriceOracle _priceOracle,
    IPoolManagerDeployer _poolManagerDeployer,
    IUniswapV3Factory _uniswapV3Factory,
    bytes32 _poolBytecodeHash,
    IERC20 _weth,
    address _owner
  )
    PoolManagerFactory(
      _strategy,
      _feeManager,
      _lockManagerFactory,
      _priceOracle,
      _poolManagerDeployer,
      _uniswapV3Factory,
      _poolBytecodeHash,
      _weth,
      _owner
    )
  {}

  function addChildForTest(IPoolManager _child) external {
    children[childrenCount] = (_child);
    isChild[_child] = true;
    childrenCount++;
  }
}

abstract contract Base is DSTestPlus, TestConstants {
  address governance = label(address(100), 'governance');

  IERC20 mockWeth = IERC20(mockContract(WETH_ADDRESS, 'mockWeth'));
  IERC20 mockToken = IERC20(mockContract('mockToken'));
  IERC20 mockTokenWethToken0 = IERC20(mockContract(0xdBdb4d16EdA451D0503b854CF79D55697F90c8DF, 'mockTokenWethToken0'));
  ILockManager mockLockManager = ILockManager(mockContract('mockLockManager'));
  IFeeManager mockFeeManager = IFeeManager(mockContract('mockFeeManager'));
  IPoolManager mockPoolManager = IPoolManager(mockContract('mockPoolManager'));
  IStrategy mockStrategy = IStrategy(mockContract('mockStrategy'));
  ILockManagerFactory mockLockManagerFactory = ILockManagerFactory(mockContract('mockLockManagerFactory'));
  IUniswapV3Pool mockPool = IUniswapV3Pool(mockContract('mockPool'));
  IPriceOracle mockPriceOracle = IPriceOracle(mockContract('mockPriceOracle'));
  IPoolManagerDeployer mockPoolManagerDeployer = IPoolManagerDeployer(mockContract('mockPoolManagerDeployer'));

  PoolManagerFactoryForTest public poolManagerFactory;

  uint160 sqrtPriceX96 = 1 << 96;

  function setUp() public virtual {
    vm.mockCall(
      address(mockLockManagerFactory),
      abi.encodeWithSelector(ILockManagerFactory.createLockManager.selector),
      abi.encode(mockLockManager)
    );

    vm.mockCall(address(mockPriceOracle), abi.encodeWithSignature('isManipulated(address)'), abi.encode(false));
    vm.mockCall(
      address(mockPoolManagerDeployer),
      abi.encodeWithSelector(IPoolManagerDeployer.deployPoolManager.selector),
      abi.encode(mockPoolManager)
    );

    poolManagerFactory = new PoolManagerFactoryForTest(
      mockStrategy, // IStrategy _strategy,
      mockFeeManager, // IFeeManager _feeManager,
      mockLockManagerFactory, // ILockManagerFactory _lockManagerFactory,
      mockPriceOracle, // IPriceOracle _priceOracle,
      mockPoolManagerDeployer, // IPoolManagerDeployer _poolManagerDeployer,
      UNISWAP_V3_FACTORY, // IUniswapV3Factory _uniswapV3Factory,
      POOL_BYTECODE_HASH, // bytes32 _poolBytecodeHash,
      mockWeth, // IERC20 _weth,
      governance // address _owner
    );
  }

  /// @notice Mock pool manager constructor calls
  /// @param pool UniswapV3 pool that is going to be initialized
  function mockPoolManagerConstructor(IUniswapV3Pool pool, IERC20 token) internal {
    mockContract(address(pool), 'pool');
    mockContract(address(token), 'token');

    vm.mockCall(address(mockWeth), abi.encodeWithSelector(IERC20.allowance.selector), abi.encode(type(uint256).max));
    vm.mockCall(address(token), abi.encodeWithSelector(IERC20.allowance.selector), abi.encode(type(uint256).max));

    // mock needed calls of _createAndInitializePool and _initializePoolIfNeeded functions
    vm.mockCall(address(UNISWAP_V3_FACTORY), abi.encodeWithSelector(IUniswapV3Factory.getPool.selector), abi.encode(pool));
    vm.mockCall(address(UNISWAP_V3_FACTORY), abi.encodeWithSelector(IUniswapV3Factory.createPool.selector), abi.encode(pool));
    vm.mockCall(address(pool), abi.encodeWithSelector(IUniswapV3PoolState.slot0.selector), abi.encode(sqrtPriceX96, 0, 0, 0, 0, 0, false));

    // mock needed calls of _increaseFullRangePosition function
    vm.mockCall(address(pool), abi.encodeWithSelector(IUniswapV3PoolImmutables.tickSpacing.selector), abi.encode(int24(10)));
    vm.mockCall(address(pool), abi.encodeWithSelector(IUniswapV3PoolActions.mint.selector), abi.encode(100, 100));

    // Assume the tick spacing is one of the default values from UniswapV3Factory
    // Needed to create the PoolManager
    vm.mockCall(address(UNISWAP_V3_FACTORY), abi.encodeWithSelector(IUniswapV3Factory.feeAmountTickSpacing.selector), abi.encode(int24(10)));
  }
}

contract UnitPoolManagerFactoryCreatePoolManager is Base {
  event PoolManagerCreated(IPoolManager _poolManager);

  function setUp() public virtual override {
    super.setUp();
    mockPoolManagerConstructor(mockPool, mockToken);
    mockPoolManagerConstructor(mockPool, mockTokenWethToken0);
  }

  function testRevertIfManagerAlreadyExists(uint24 fee, uint128 liquidity) public {
    vm.assume(liquidity > poolManagerFactory.minEthAmount());
    vm.startPrank(governance);
    poolManagerFactory.createPoolManager(mockToken, fee, liquidity, sqrtPriceX96);

    vm.expectRevert(IPoolManagerFactory.PoolManagerFactory_ExistingPoolManager.selector);
    poolManagerFactory.createPoolManager(mockToken, fee, liquidity, sqrtPriceX96);
  }

  function testRevertIfLiquidityIsTooLow(uint24 fee, uint128 liquidity) public {
    vm.assume(liquidity < poolManagerFactory.minEthAmount());
    vm.expectRevert(IPoolManagerFactory.PoolManagerFactory_SmallAmount.selector);
    poolManagerFactory.createPoolManager(mockToken, fee, liquidity, sqrtPriceX96);
  }

  function testRevertIfLiquidityIsTooLowWethToken0(uint24 fee, uint128 liquidity) public {
    vm.assume(liquidity < poolManagerFactory.minEthAmount());
    vm.expectRevert(IPoolManagerFactory.PoolManagerFactory_SmallAmount.selector);
    poolManagerFactory.createPoolManager(mockTokenWethToken0, fee, liquidity, sqrtPriceX96);
  }

  function testRevertWithoutRoundingThreshold(uint24 fee) public {
    vm.expectRevert(IPoolManagerFactory.PoolManagerFactory_SmallAmount.selector);
    poolManagerFactory.createPoolManager(mockToken, fee, 25 ether - 100, sqrtPriceX96);
  }

  function testRoundingThreshold(uint24 fee) public {
    IUniswapV3Pool pool = ContractDeploymentAddress.getTheoreticalUniPool(mockWeth, mockToken, fee, UNISWAP_V3_FACTORY);
    mockPoolManagerConstructor(pool, mockToken);

    IPoolManager expectedPoolManager = ContractDeploymentAddress.getTheoreticalPoolManager(poolManagerFactory.POOL_MANAGER_DEPLOYER(), pool);
    expectedPoolManager = IPoolManager(mockContract(address(expectedPoolManager), 'expectedPoolManager'));

    vm.mockCall(
      address(poolManagerFactory.POOL_MANAGER_DEPLOYER()),
      abi.encodeWithSelector(IPoolManagerDeployer.deployPoolManager.selector),
      abi.encode(expectedPoolManager)
    );

    expectEmitNoIndex();
    emit PoolManagerCreated(expectedPoolManager);

    poolManagerFactory.createPoolManager(mockToken, fee, 25 ether, sqrtPriceX96);
  }

  function testCreatePoolManagerWithCorrectProperties(uint24 fee, uint128 liquidity) public virtual {
    vm.assume(liquidity > poolManagerFactory.minEthAmount());

    IUniswapV3Pool pool = ContractDeploymentAddress.getTheoreticalUniPool(mockWeth, mockToken, fee, UNISWAP_V3_FACTORY);
    mockPoolManagerConstructor(pool, mockToken);

    IPoolManager expectedPoolManager = ContractDeploymentAddress.getTheoreticalPoolManager(poolManagerFactory.POOL_MANAGER_DEPLOYER(), pool);
    vm.mockCall(
      address(poolManagerFactory.POOL_MANAGER_DEPLOYER()),
      abi.encodeWithSelector(IPoolManagerDeployer.deployPoolManager.selector),
      abi.encode(expectedPoolManager)
    );

    vm.mockCall(address(expectedPoolManager), abi.encodeWithSelector(IPoolManager.FEE.selector), abi.encode(fee));
    vm.mockCall(address(expectedPoolManager), abi.encodeWithSelector(IPoolManager.TOKEN.selector), abi.encode(mockToken));

    IPoolManager poolManager = poolManagerFactory.createPoolManager(mockToken, fee, liquidity, sqrtPriceX96);

    assertEq(poolManagerFactory.childrenCount(), 1);
    assertEq(poolManagerFactory.isChild(poolManager), true);
    assertEq(poolManager.FEE(), fee);
    assertEq(address(poolManager.TOKEN()), address(mockToken));
  }

  function testCreatePoolManagerWithCorrectPropertiesWethToken0(uint24 fee, uint128 liquidity) public virtual {
    vm.assume(liquidity > poolManagerFactory.minEthAmount());

    IUniswapV3Pool pool = ContractDeploymentAddress.getTheoreticalUniPool(mockWeth, mockTokenWethToken0, fee, UNISWAP_V3_FACTORY);
    mockPoolManagerConstructor(pool, mockTokenWethToken0);

    IPoolManager expectedPoolManager = ContractDeploymentAddress.getTheoreticalPoolManager(poolManagerFactory.POOL_MANAGER_DEPLOYER(), pool);
    vm.mockCall(
      address(poolManagerFactory.POOL_MANAGER_DEPLOYER()),
      abi.encodeWithSelector(IPoolManagerDeployer.deployPoolManager.selector),
      abi.encode(expectedPoolManager)
    );

    vm.mockCall(address(expectedPoolManager), abi.encodeWithSelector(IPoolManager.FEE.selector), abi.encode(fee));
    vm.mockCall(address(expectedPoolManager), abi.encodeWithSelector(IPoolManager.TOKEN.selector), abi.encode(mockTokenWethToken0));

    IPoolManager poolManager = poolManagerFactory.createPoolManager(mockTokenWethToken0, fee, liquidity, sqrtPriceX96);

    assertEq(poolManagerFactory.childrenCount(), 1);
    assertEq(poolManagerFactory.isChild(poolManager), true);
    assertEq(poolManager.FEE(), fee);
    assertEq(address(poolManager.TOKEN()), address(mockTokenWethToken0));
  }

  function testCreatePoolManagerWithDeterministicAddress(uint24 fee, uint128 liquidity) public virtual {
    vm.assume(liquidity > poolManagerFactory.minEthAmount());

    IUniswapV3Pool pool = ContractDeploymentAddress.getTheoreticalUniPool(mockWeth, mockToken, fee, UNISWAP_V3_FACTORY);
    mockPoolManagerConstructor(pool, mockToken);

    IPoolManager expectedPoolManager = ContractDeploymentAddress.getTheoreticalPoolManager(poolManagerFactory.POOL_MANAGER_DEPLOYER(), pool);
    expectedPoolManager = IPoolManager(mockContract(address(expectedPoolManager), 'expectedPoolManager'));

    vm.mockCall(
      address(poolManagerFactory.POOL_MANAGER_DEPLOYER()),
      abi.encodeWithSelector(IPoolManagerDeployer.deployPoolManager.selector),
      abi.encode(expectedPoolManager)
    );

    expectEmitNoIndex();
    emit PoolManagerCreated(expectedPoolManager);

    IPoolManager poolManager = poolManagerFactory.createPoolManager(mockToken, fee, liquidity, sqrtPriceX96);

    assertEq(address(poolManager), address(expectedPoolManager));
  }
}

contract UnitPoolManagerFactoryChildrenCount is Base {
  function testCount(IPoolManager[] memory children) public {
    for (uint256 i; i < children.length; i++) {
      poolManagerFactory.addChildForTest(children[i]);
    }

    assertEq(poolManagerFactory.childrenCount(), children.length);
  }
}

contract UnitPoolManagerFactoryListChildren is Base {
  function testLimitateToLength(IPoolManager[] memory children, uint256 amount) public {
    vm.assume(amount > children.length);

    for (uint256 i; i < children.length; i++) {
      poolManagerFactory.addChildForTest(children[i]);
    }

    assertEqChildren(poolManagerFactory.listChildren(0, amount), children);
  }

  function testLimitateToAmount(
    IPoolManager pm1,
    IPoolManager pm2,
    IPoolManager pm3,
    IPoolManager pm4
  ) public {
    poolManagerFactory.addChildForTest(pm1);
    poolManagerFactory.addChildForTest(pm2);
    poolManagerFactory.addChildForTest(pm3);
    poolManagerFactory.addChildForTest(pm4);

    IPoolManager[] memory expected = new IPoolManager[](2);
    expected[0] = pm1;
    expected[1] = pm2;

    assertEqChildren(poolManagerFactory.listChildren(0, 2), expected);
  }

  function testStartFrom(
    IPoolManager pm1,
    IPoolManager pm2,
    IPoolManager pm3,
    IPoolManager pm4,
    IPoolManager pm5
  ) public {
    poolManagerFactory.addChildForTest(pm1);
    poolManagerFactory.addChildForTest(pm2);
    poolManagerFactory.addChildForTest(pm3);
    poolManagerFactory.addChildForTest(pm4);
    poolManagerFactory.addChildForTest(pm5);

    IPoolManager[] memory expected = new IPoolManager[](3);
    expected[0] = pm3;
    expected[1] = pm4;
    expected[2] = pm5;

    assertEqChildren(poolManagerFactory.listChildren(2, 3), expected);
  }

  function assertEqChildren(IPoolManager[] memory a, IPoolManager[] memory b) private {
    require(a.length == b.length, 'LENGTH_MISMATCH');

    for (uint256 i = 0; i < a.length; i++) {
      assertEq(address(a[i]), address(b[i]));
    }
  }
}

contract UnitPoolManagerFactoryTheoreticalAddresses is Base {
  function testGetUniswapV3PoolTheoreticalAddress(uint24 _fee) public {
    (IUniswapV3Pool _pool, bool _isWethToken0) = poolManagerFactory.getWethPoolAddress(mockToken, _fee);
    IUniswapV3Pool _theoreticalPoolAddress = ContractDeploymentAddress.getTheoreticalUniPool(mockWeth, mockToken, _fee, UNISWAP_V3_FACTORY);
    assertEq(address(_pool), address(_theoreticalPoolAddress));
    assertEq(address(mockToken) > address(mockWeth), _isWethToken0);
  }

  function testGetPoolManagerTheoreticalAddress(uint24 _fee) public virtual {
    IPoolManager _poolManager = poolManagerFactory.getPoolManagerAddress(mockToken, _fee);

    IUniswapV3Pool _theoreticalPoolAddress = ContractDeploymentAddress.getTheoreticalUniPool(mockWeth, mockToken, _fee, UNISWAP_V3_FACTORY);
    IPoolManager _theoreticalPoolManagerAddress = ContractDeploymentAddress.getTheoreticalPoolManager(
      poolManagerFactory.POOL_MANAGER_DEPLOYER(),
      _theoreticalPoolAddress
    );
    assertEq(address(_poolManager), address(_theoreticalPoolManagerAddress));
  }
}

contract UnitPoolManagerFactorySetLockManagerFactory is Base {
  event LockManagerFactoryChanged(ILockManagerFactory _lockManagerFactory);

  ILockManagerFactory newLockManagerFactory = ILockManagerFactory(newAddress());

  function testRevertIfNotRole() public {
    address unauthorized = newAddress();
    vm.expectRevert(abi.encodeWithSelector(IRoles.Unauthorized.selector, unauthorized, poolManagerFactory.FACTORY_SETTER_ROLE()));

    vm.prank(unauthorized);
    poolManagerFactory.setLockManagerFactory(newLockManagerFactory);
  }

  function testRevertIfAddressZero() public {
    vm.expectRevert(IPoolManagerFactory.PoolManagerFactory_ZeroAddress.selector);

    vm.prank(governance);
    poolManagerFactory.setLockManagerFactory(ILockManagerFactory(address(0)));
  }

  function testChangesLockManagerFactory() public {
    vm.prank(governance);
    poolManagerFactory.setLockManagerFactory(newLockManagerFactory);

    assertEq(address(poolManagerFactory.lockManagerFactory()), address(newLockManagerFactory));
  }

  function testEmitEvent() public {
    expectEmitNoIndex();

    emit LockManagerFactoryChanged(newLockManagerFactory);

    vm.prank(governance);
    poolManagerFactory.setLockManagerFactory(newLockManagerFactory);
  }
}

contract UnitPoolManagerFactorySetStrategy is Base {
  event StrategyChanged(IStrategy _strategy);

  IStrategy newStrategy = IStrategy(newAddress());

  function testRevertIfNotRole() public {
    address unauthorized = newAddress();
    vm.expectRevert(abi.encodeWithSelector(IRoles.Unauthorized.selector, unauthorized, poolManagerFactory.STRATEGY_SETTER_ROLE()));

    vm.prank(unauthorized);
    poolManagerFactory.setStrategy(newStrategy);
  }

  function testRevertIfAddressZero() public {
    vm.expectRevert(IPoolManagerFactory.PoolManagerFactory_ZeroAddress.selector);

    vm.prank(governance);
    poolManagerFactory.setStrategy(IStrategy(address(0)));
  }

  function testChangesStrategy() public {
    vm.prank(governance);
    poolManagerFactory.setStrategy(newStrategy);

    assertEq(address(poolManagerFactory.strategy()), address(newStrategy));
  }

  function testEmitEvent() public {
    expectEmitNoIndex();

    emit StrategyChanged(newStrategy);

    vm.prank(governance);
    poolManagerFactory.setStrategy(newStrategy);
  }
}

contract UnitPoolManagerFactoryNominateOwner is Base {
  event OwnerNominated(address _newOwner);

  address newOwner = newAddress();

  function testRevertIfNotRole() public {
    address unauthorized = newAddress();
    vm.expectRevert(abi.encodeWithSelector(IRoles.Unauthorized.selector, unauthorized, poolManagerFactory.DEFAULT_ADMIN_ROLE()));

    vm.prank(unauthorized);
    poolManagerFactory.nominateOwner(newOwner);
  }

  function testSetsPendingOwner() public {
    vm.prank(governance);
    poolManagerFactory.nominateOwner(newOwner);

    assertEq(poolManagerFactory.pendingOwner(), newOwner);
  }

  function testEmitEvent() public {
    expectEmitNoIndex();

    emit OwnerNominated(newOwner);

    vm.prank(governance);
    poolManagerFactory.nominateOwner(newOwner);
  }
}

contract UnitPoolManagerFactoryAcceptOwnership is Base {
  event OwnerChanged(address _owner);

  address newOwner = newAddress();

  function setUp() public virtual override {
    super.setUp();

    vm.prank(governance);
    poolManagerFactory.nominateOwner(newOwner);
  }

  function testRevertIfNotPendingOwner() public {
    vm.expectRevert(abi.encodeWithSelector(IPoolManagerFactory.PoolManagerFactory_InvalidPendingOwner.selector));

    vm.prank(newAddress());
    poolManagerFactory.acceptOwnership();
  }

  function testChangesOwner() public {
    vm.prank(newOwner);
    poolManagerFactory.acceptOwnership();

    assertEq(poolManagerFactory.owner(), newOwner);
  }

  function testResetPendingOwner() public {
    vm.prank(newOwner);
    poolManagerFactory.acceptOwnership();

    assertEq(poolManagerFactory.pendingOwner(), address(0));
  }

  function testSetsAdminRoles() public {
    vm.prank(newOwner);
    poolManagerFactory.acceptOwnership();

    assertTrue(poolManagerFactory.hasRole(poolManagerFactory.DEFAULT_ADMIN_ROLE(), newOwner));
    assertTrue(poolManagerFactory.hasRole(poolManagerFactory.FACTORY_SETTER_ROLE(), newOwner));
    assertTrue(poolManagerFactory.hasRole(poolManagerFactory.STRATEGY_SETTER_ROLE(), newOwner));
    assertTrue(poolManagerFactory.hasRole(poolManagerFactory.MIGRATOR_SETTER_ROLE(), newOwner));
    assertTrue(poolManagerFactory.hasRole(poolManagerFactory.PRICE_ORACLE_SETTER_ROLE(), newOwner));
  }

  function testRevokeOldAdminRoles() public {
    vm.prank(newOwner);
    poolManagerFactory.acceptOwnership();

    assertFalse(poolManagerFactory.hasRole(poolManagerFactory.DEFAULT_ADMIN_ROLE(), governance));
    assertFalse(poolManagerFactory.hasRole(poolManagerFactory.FACTORY_SETTER_ROLE(), governance));
    assertFalse(poolManagerFactory.hasRole(poolManagerFactory.STRATEGY_SETTER_ROLE(), governance));
    assertFalse(poolManagerFactory.hasRole(poolManagerFactory.MIGRATOR_SETTER_ROLE(), governance));
    assertFalse(poolManagerFactory.hasRole(poolManagerFactory.PRICE_ORACLE_SETTER_ROLE(), governance));
  }

  function testEmitEvent() public {
    expectEmitNoIndex();

    emit OwnerChanged(newOwner);

    vm.prank(newOwner);
    poolManagerFactory.acceptOwnership();
  }
}

contract UnitPoolManagerFactorySetPoolManagerMigrator is Base {
  event PoolManagerMigratorChanged(address _poolManagerMigrator);

  address poolManagerMigrator = newAddress();

  function testRevertIfNotRole() public {
    address unauthorized = newAddress();
    vm.expectRevert(abi.encodeWithSelector(IRoles.Unauthorized.selector, unauthorized, poolManagerFactory.MIGRATOR_SETTER_ROLE()));

    vm.prank(unauthorized);
    poolManagerFactory.setPoolManagerMigrator(poolManagerMigrator);
  }

  function testChangesPoolManagerMigrator() public {
    vm.prank(governance);
    poolManagerFactory.setPoolManagerMigrator(poolManagerMigrator);

    assertEq(poolManagerFactory.poolManagerMigrator(), poolManagerMigrator);
  }

  function testEmitEvent() public {
    expectEmitNoIndex();

    emit PoolManagerMigratorChanged(poolManagerMigrator);

    vm.prank(governance);
    poolManagerFactory.setPoolManagerMigrator(poolManagerMigrator);
  }
}

contract UnitPoolManagerFactorySetPriceOracle is Base {
  event PriceOracleChanged(IPriceOracle _priceOracle);

  IPriceOracle newPriceOracle = IPriceOracle(mockContract('newPriceOracle'));

  function testRevertIfNotRole() public {
    address unauthorized = newAddress();
    vm.expectRevert(abi.encodeWithSelector(IRoles.Unauthorized.selector, unauthorized, poolManagerFactory.PRICE_ORACLE_SETTER_ROLE()));

    vm.prank(unauthorized);
    poolManagerFactory.setPriceOracle(newPriceOracle);
  }

  function testRevertIfAddressZero() public {
    vm.expectRevert(IPoolManagerFactory.PoolManagerFactory_ZeroAddress.selector);

    vm.prank(governance);
    poolManagerFactory.setPriceOracle(IPriceOracle(address(0)));
  }

  function testChangesPriceOracle() public {
    vm.prank(governance);
    poolManagerFactory.setPriceOracle(newPriceOracle);

    assertEq(address(poolManagerFactory.priceOracle()), address(newPriceOracle));
  }

  function testEmitEvent() public {
    expectEmitNoIndex();

    emit PriceOracleChanged(newPriceOracle);

    vm.prank(governance);
    poolManagerFactory.setPriceOracle(newPriceOracle);
  }
}

contract UnitPoolManagerFactorySetFeeManager is Base {
  event FeeManagerChanged(IFeeManager _feeManager);

  IFeeManager newFeeManager = IFeeManager(mockContract('newFeeManager'));

  function testRevertIfNotRole() public {
    address unauthorized = newAddress();
    vm.expectRevert(abi.encodeWithSelector(IRoles.Unauthorized.selector, unauthorized, poolManagerFactory.FEE_MANAGER_SETTER_ROLE()));

    vm.prank(unauthorized);
    poolManagerFactory.setFeeManager(newFeeManager);
  }

  function testRevertIfAddressZero() public {
    vm.expectRevert(IPoolManagerFactory.PoolManagerFactory_ZeroAddress.selector);

    vm.prank(governance);
    poolManagerFactory.setFeeManager(IFeeManager(address(0)));
  }

  function testChangesFeeManager() public {
    vm.prank(governance);
    poolManagerFactory.setFeeManager(newFeeManager);

    assertEq(address(poolManagerFactory.feeManager()), address(newFeeManager));
  }

  function testEmitEvent() public {
    expectEmitNoIndex();

    emit FeeManagerChanged(newFeeManager);

    vm.prank(governance);
    poolManagerFactory.setFeeManager(newFeeManager);
  }
}

contract UnitPoolManagerFactorySetFeeCollectorJob is Base {
  event FeeCollectorJobChanged(IFeeCollectorJob _feeCollectorJob);

  IFeeCollectorJob newFeeCollectorJob = IFeeCollectorJob(mockContract('newFeeCollectorJob'));

  function testRevertIfNotRole() public {
    address unauthorized = newAddress();
    vm.expectRevert(abi.encodeWithSelector(IRoles.Unauthorized.selector, unauthorized, poolManagerFactory.FEE_COLLECTOR_SETTER_ROLE()));

    vm.prank(unauthorized);
    poolManagerFactory.setFeeCollectorJob(newFeeCollectorJob);
  }

  function testRevertIfAddressZero() public {
    vm.expectRevert(IPoolManagerFactory.PoolManagerFactory_ZeroAddress.selector);

    vm.prank(governance);
    poolManagerFactory.setFeeCollectorJob(IFeeCollectorJob(address(0)));
  }

  function testChangesFeeManager() public {
    vm.prank(governance);
    poolManagerFactory.setFeeCollectorJob(newFeeCollectorJob);

    assertEq(address(poolManagerFactory.feeCollectorJob()), address(newFeeCollectorJob));
  }

  function testEmitEvent() public {
    expectEmitNoIndex();

    emit FeeCollectorJobChanged(newFeeCollectorJob);

    vm.prank(governance);
    poolManagerFactory.setFeeCollectorJob(newFeeCollectorJob);
  }
}

contract UnitPoolManagerFactorySetMinEthAmount is Base {
  event MinEthAmountChanged(uint256 _minEthAmount);

  function testRevertIfNotRole(uint256 _minEthAmount) public {
    vm.assume(_minEthAmount > 0);

    address unauthorized = newAddress();
    vm.expectRevert(abi.encodeWithSelector(IRoles.Unauthorized.selector, unauthorized, poolManagerFactory.MIN_ETH_AMOUNT_SETTER_ROLE()));

    vm.prank(unauthorized);
    poolManagerFactory.setMinEthAmount(_minEthAmount);
  }

  function testRevertIfInvalidAmount() public {
    uint256 _minEthAmount = 0;
    vm.expectRevert(IPoolManagerFactory.PoolManagerFactory_InvalidMinEthAmount.selector);

    vm.prank(governance);
    poolManagerFactory.setMinEthAmount(_minEthAmount);
  }

  function testChangeMinEthAmount(uint256 _minEthAmount) public {
    vm.assume(_minEthAmount > 0);

    vm.prank(governance);
    poolManagerFactory.setMinEthAmount(_minEthAmount);

    assertEq(poolManagerFactory.minEthAmount(), _minEthAmount);
  }

  function testEmitEvent(uint256 _minEthAmount) public {
    vm.assume(_minEthAmount > 0);

    expectEmitNoIndex();
    emit MinEthAmountChanged(_minEthAmount);

    vm.prank(governance);
    poolManagerFactory.setMinEthAmount(_minEthAmount);
  }
}

contract UnitPoolManagerFactoryGetPoolManagers is Base {
  uint24[] feeTiers;
  address[] expectedPoolManagers;
  IPoolManager poolManagerA;
  IPoolManager poolManagerB;

  function setUp() public virtual override {
    super.setUp();

    poolManagerA = IPoolManager(poolManagerFactory.getPoolManagerAddress(mockToken, 300));
    poolManagerB = IPoolManager(poolManagerFactory.getPoolManagerAddress(mockToken, 1000));

    poolManagerFactory.addChildForTest(poolManagerA);
    poolManagerFactory.addChildForTest(poolManagerB);
  }

  function testListsExistingPoolManagers() public {
    expectedPoolManagers.push(address(poolManagerA));
    expectedPoolManagers.push(address(0));
    expectedPoolManagers.push(address(poolManagerB));
    expectedPoolManagers.push(address(0));

    feeTiers.push(300);
    feeTiers.push(500);
    feeTiers.push(1000);
    feeTiers.push(10000);

    address[] memory poolManagers = poolManagerFactory.getPoolManagers(mockToken, feeTiers);

    assertEq(poolManagers, expectedPoolManagers);
  }
}

contract UnitPoolManagerFactoryIsSupportedPool is Base {
  using stdStorage for StdStorage;

  function testSupportedPool() public {
    stdstore.target(address(poolManagerFactory)).sig(poolManagerFactory.poolManagers.selector).with_key(address(mockPool)).checked_write(
      address(mockPoolManager)
    );
    assertEq(poolManagerFactory.isSupportedPool(mockPool), true);
  }

  function testNotSupportedPool() public {
    assertEq(poolManagerFactory.isSupportedPool(IUniswapV3Pool(newAddress())), false);
  }
}

contract UnitPoolManagerFactoryIsSupportedToken is Base {
  function setUp() public virtual override {
    super.setUp();
    mockPoolManagerConstructor(mockPool, mockToken);
  }

  function testIsSupportedTokenReturnsTrue(uint24 fee, uint128 liquidity) public {
    vm.assume(liquidity > poolManagerFactory.minEthAmount());
    vm.startPrank(governance);
    poolManagerFactory.createPoolManager(mockToken, fee, liquidity, sqrtPriceX96);
    assertEq(poolManagerFactory.isSupportedToken(mockToken), true);
    vm.stopPrank();
  }

  function testIsSupportedTokenReturnsFalse() public {
    assertEq(poolManagerFactory.isSupportedToken(mockToken), false);
  }
}

contract UnitPoolManagerFactoryIsSupportedTokenPair is Base {
  function setUp() public virtual override {
    super.setUp();
    mockPoolManagerConstructor(mockPool, mockToken);
  }

  function testIsSupportedTokenPair(uint24 fee, uint128 liquidity) public {
    vm.assume(liquidity > poolManagerFactory.minEthAmount());
    vm.startPrank(governance);
    poolManagerFactory.createPoolManager(mockToken, fee, liquidity, sqrtPriceX96);
    poolManagerFactory.createPoolManager(mockWeth, fee, liquidity, sqrtPriceX96);
    assertEq(poolManagerFactory.isSupportedTokenPair(mockToken, mockWeth), true);
    vm.stopPrank();
  }

  function testIsSupportedTokenPairFalseFirst(uint24 fee, uint128 liquidity) public {
    vm.assume(liquidity > poolManagerFactory.minEthAmount());
    vm.prank(governance);
    poolManagerFactory.createPoolManager(mockWeth, fee, liquidity, sqrtPriceX96);
    assertEq(poolManagerFactory.isSupportedTokenPair(mockToken, mockWeth), false);
  }

  function testIsSupportedTokenPairFalseSecond(uint24 fee, uint128 liquidity) public {
    vm.assume(liquidity > poolManagerFactory.minEthAmount());
    vm.prank(governance);
    poolManagerFactory.createPoolManager(mockToken, fee, liquidity, sqrtPriceX96);
    assertEq(poolManagerFactory.isSupportedTokenPair(mockToken, mockWeth), false);
  }
}

contract UnitPoolManagerFactoryDefaultToken is Base {
  function setUp() public virtual override {
    super.setUp();
    mockPoolManagerConstructor(mockPool, mockToken);
  }

  function testDefaultTokenFee(uint24 fee, uint128 liquidity) public {
    vm.assume(liquidity > poolManagerFactory.minEthAmount());
    vm.prank(governance);
    poolManagerFactory.createPoolManager(mockToken, fee, liquidity, sqrtPriceX96);
    assertEq(poolManagerFactory.defaultTokenFee(mockToken), fee);
  }
}

contract UnitSetDefaultTokenFee is Base {
  uint128 liquidity = 2000 ether;
  uint24 initialFee = 100;
  uint24 secondFee = 200;
  uint24 thirdFee = 300;
  uint24 fourthFee = 400;

  function setUp() public virtual override {
    super.setUp();
    mockPoolManagerConstructor(mockPool, mockToken);
    poolManagerFactory.createPoolManager(mockToken, initialFee, liquidity, sqrtPriceX96);
    poolManagerFactory.createPoolManager(mockToken, secondFee, liquidity, sqrtPriceX96);
    poolManagerFactory.createPoolManager(mockToken, thirdFee, liquidity, sqrtPriceX96);
    poolManagerFactory.createPoolManager(mockToken, fourthFee, liquidity, sqrtPriceX96);
  }

  function testSetDefaultTokenFeeLast() public {
    vm.prank(governance);
    poolManagerFactory.setDefaultTokenFee(mockToken, fourthFee);
    assertEq(poolManagerFactory.defaultTokenFee(mockToken), fourthFee);
    vm.stopPrank();
  }

  function testSetDefaultTokenFeeMiddle() public {
    vm.prank(governance);
    poolManagerFactory.setDefaultTokenFee(mockToken, thirdFee);
    assertEq(poolManagerFactory.defaultTokenFee(mockToken), thirdFee);
    vm.stopPrank();
  }

  function testRevertIfInvalidPool(uint24 invalidFee) public {
    vm.assume(invalidFee != initialFee && invalidFee != secondFee && invalidFee != thirdFee && invalidFee != fourthFee);
    vm.prank(governance);
    vm.expectRevert(IPoolManagerFactory.PoolManagerFactory_InvalidPool.selector);
    poolManagerFactory.setDefaultTokenFee(mockToken, invalidFee);
  }

  function testRevertIfInvalidRole(uint24 invalidFee) public {
    address unauthorized = newAddress();
    vm.assume(unauthorized != governance);

    vm.expectRevert(abi.encodeWithSelector(IRoles.Unauthorized.selector, unauthorized, poolManagerFactory.DEFAULT_ADMIN_ROLE()));

    vm.prank(unauthorized);
    poolManagerFactory.setDefaultTokenFee(mockToken, invalidFee);
  }
}
