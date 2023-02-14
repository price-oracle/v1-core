// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4 <0.9.0;

import 'solidity-utils/test/DSTestPlus.sol';

import '@interfaces/IFeeManager.sol';
import '@interfaces/IPoolManagerGovernor.sol';
import '@contracts/FeeManager.sol';
import '@test/utils/TestConstants.sol';

contract FeeManagerForTest is FeeManager {
  constructor(
    IPoolManagerFactory _poolManagerFactory,
    address _governor,
    IERC20 _weth
  ) payable FeeManager(_poolManagerFactory, _governor, _weth) {}

  function setPoolManagerDeposits(
    IPoolManager poolManager,
    uint256 balanceWeth,
    uint256 balanceToken
  ) public {
    poolManagerDeposits[poolManager] = FeeStore(balanceWeth, balanceToken);
  }

  function setPoolManagerDistributions(
    IPoolManager poolManager,
    uint256 wethForMaintenance,
    uint256 wethForCardinality,
    bool isInitialized
  ) public {
    poolDistribution[poolManager] = PoolDistributionFees(wethForMaintenance, wethForCardinality, isInitialized);
  }

  function setPoolCardinalityForTest(
    IPoolManager poolManager,
    uint256 wethAmount,
    uint16 cardinality,
    uint16 customMax
  ) public {
    poolCardinality[poolManager] = PoolCardinality(wethAmount, cardinality, customMax);
  }
}

abstract contract Base is DSTestPlus, TestConstants {
  address governance = label(address(100), 'governance');

  IERC20 mockToken = IERC20(mockContract('mockToken'));
  IERC20 mockWeth = IERC20(mockContract(WETH_ADDRESS, 'mockWeth'));
  IUniswapV3Pool mockPool = IUniswapV3Pool(mockContract('mockPool'));
  IPoolManager mockPoolManager = IPoolManager(mockContract('mockPoolManager'));
  IPoolManagerFactory mockPoolManagerFactory = IPoolManagerFactory(mockContract('mockPoolManagerFactory'));
  ILockManager mockLockManager = ILockManager(mockContract('mockLockManager'));
  IUniswapV3Pool otherMockPool = IUniswapV3Pool(mockContract('otherMockPool'));
  ICardinalityJob mockCardinalityJob = ICardinalityJob(mockContract('mockJob'));
  IFeeManager otherMockFeeManager = IFeeManager(mockContract('otherMockFeeManager'));

  FeeManagerForTest feeManager;

  uint256 constant DISTRIBUTION_BASE = 100_000;
  uint256 constant WETH_FOR_MAINTENANCE = 40_000;
  uint256 constant WETH_FOR_CARDINALITY = 20_000;
  uint256 constant MAX_WETH_MAINTENANCE_THRESHOLD = 60_000;
  uint256 constant MULTIPLIER = 1_000;
  uint256 constant SWAP_COST = 127_000;
  uint256 constant TOTAL_COST = MULTIPLIER * SWAP_COST * 100;

  function setUp() public virtual {
    vm.mockCall(
      address(mockPoolManagerFactory),
      abi.encodeWithSelector(IPoolManagerFactory.isChild.selector, address(mockPoolManager)),
      abi.encode(true)
    );

    vm.mockCall(address(mockPoolManager), abi.encodeWithSelector(IPoolManager.POOL.selector), abi.encode(address(mockPool)));
    vm.mockCall(address(mockPoolManager), abi.encodeWithSelector(IPoolManagerGovernor.feeManager.selector), abi.encode(otherMockFeeManager));
    vm.mockCall(address(mockPoolManager), abi.encodeWithSelector(IPoolManager.lockManager.selector), abi.encode(mockLockManager));
    vm.mockCall(address(mockPoolManager), abi.encodeWithSelector(IPoolManager.TOKEN.selector), abi.encode(mockToken));
    vm.mockCall(address(mockPoolManager), abi.encodeWithSelector(IPoolManager.mintLiquidityForFullRange.selector), abi.encode());
    vm.mockCall(address(mockWeth), abi.encodeWithSelector(IERC20.approve.selector), abi.encode(true));
    vm.mockCall(address(mockWeth), abi.encodeWithSelector(IERC20.transfer.selector), abi.encode(true));
    vm.mockCall(address(mockToken), abi.encodeWithSelector(IERC20.transfer.selector), abi.encode(true));

    feeManager = new FeeManagerForTest(mockPoolManagerFactory, governance, mockWeth);

    vm.prank(governance);
    feeManager.setSwapGasCostMultiplier(MULTIPLIER);
  }
}

contract UnitFeeManagerSetCardinalityJob is Base {
  event CardinalityJobSet(ICardinalityJob _cardinalityJob);

  function testRevertIfNotGovernance() public {
    vm.expectRevert(abi.encodeWithSelector(IRoles.Unauthorized.selector, address(this), feeManager.DEFAULT_ADMIN_ROLE()));
    feeManager.setCardinalityJob(mockCardinalityJob);
  }

  function testSetCardinalityJob(ICardinalityJob _cardinalityJob) public {
    vm.prank(governance);
    feeManager.setCardinalityJob(_cardinalityJob);

    assertEq(address(feeManager.cardinalityJob()), address(_cardinalityJob));
  }

  function testEmitEvent(ICardinalityJob _cardinalityJob) public {
    vm.expectEmit(false, false, false, true);

    emit CardinalityJobSet(_cardinalityJob);

    vm.prank(governance);
    feeManager.setCardinalityJob(_cardinalityJob);
  }
}

contract UnitFeeManagerDepositFromLockManager is Base {
  event FeesDeposited(
    IPoolManager _poolManager,
    uint256 _wethFees,
    uint256 _tokenFees,
    uint256 _wethForMaintenance,
    uint256 _wethForCardinality
  );

  function setUp() public virtual override {
    super.setUp();
    vm.mockCall(address(mockPoolManager), abi.encodeWithSelector(IPoolManager.lockManager.selector), abi.encode(mockLockManager));
    vm.mockCall(address(mockLockManager), abi.encodeWithSelector(ILockManager.POOL_MANAGER.selector), abi.encode(mockPoolManager));
  }

  function testRevertIfInvalidPoolManager(uint128 wethFees, uint128 tokenFees) public {
    vm.mockCall(
      address(mockPoolManagerFactory),
      abi.encodeWithSelector(IPoolManagerFactory.isChild.selector, address(mockPoolManager)),
      abi.encode(false)
    );

    vm.expectRevert(abi.encodeWithSelector(IFeeManager.FeeManager_InvalidPoolManager.selector, address(mockPoolManager)));
    vm.prank(address(mockLockManager));
    feeManager.depositFromLockManager(wethFees, tokenFees);
  }

  function testUpdatePoolManagerDeposit(uint128 wethFees, uint128 tokenFees) public {
    vm.assume(wethFees > 10 && wethFees < type(uint64).max && tokenFees > 0);
    uint256 _wethForMaintenance = (wethFees * WETH_FOR_MAINTENANCE) / DISTRIBUTION_BASE;
    uint256 _wethForCardinality = (wethFees * WETH_FOR_CARDINALITY) / DISTRIBUTION_BASE;

    vm.mockCall(
      address(mockWeth),
      abi.encodeWithSelector(IERC20.transfer.selector, governance, _wethForMaintenance + _wethForCardinality),
      abi.encode(true)
    );

    vm.prank(address(mockLockManager));
    feeManager.depositFromLockManager(wethFees, tokenFees);

    (uint256 depositedWethForFullRange, uint256 depositedTokenForFullRange) = feeManager.poolManagerDeposits(mockPoolManager);

    assertGe(depositedWethForFullRange, 0);
    assertGe(depositedTokenForFullRange, 0);
  }

  function testEmitEvent(uint128 wethFees, uint128 tokenFees) public {
    vm.assume(wethFees > 10 && wethFees < type(uint64).max && tokenFees > 0);
    vm.prank(address(mockLockManager));
    vm.expectEmit(false, false, false, true);

    uint256 _wethForMaintenance = (wethFees * WETH_FOR_MAINTENANCE) / DISTRIBUTION_BASE;
    uint256 _wethForCardinality = (wethFees * WETH_FOR_CARDINALITY) / DISTRIBUTION_BASE;

    vm.mockCall(
      address(mockWeth),
      abi.encodeWithSelector(IERC20.transfer.selector, governance, _wethForMaintenance + _wethForCardinality),
      abi.encode(true)
    );

    emit FeesDeposited(
      mockPoolManager,
      wethFees - _wethForMaintenance - _wethForCardinality,
      tokenFees,
      _wethForMaintenance,
      _wethForCardinality
    );

    feeManager.depositFromLockManager(wethFees, tokenFees);
  }
}

contract UnitFeeManagerDepositFromPoolManager is Base {
  event FeesDeposited(
    IPoolManager _poolManager,
    uint256 _wethFees,
    uint256 _tokenFees,
    uint256 _wethForMaintenance,
    uint256 _wethForCardinality
  );

  function setUp() public virtual override {
    super.setUp();
  }

  function testRevertIfInvalidPoolManager(uint128 wethFees, uint128 tokenFees) public {
    vm.mockCall(
      address(mockPoolManagerFactory),
      abi.encodeWithSelector(IPoolManagerFactory.isChild.selector, address(mockPoolManager)),
      abi.encode(false)
    );

    vm.expectRevert(abi.encodeWithSelector(IFeeManager.FeeManager_InvalidPoolManager.selector, address(mockPoolManager)));
    vm.prank(address(mockPoolManager));
    feeManager.depositFromPoolManager(wethFees, tokenFees);
  }

  function testUpdatePoolManagerDeposit(uint128 wethFees, uint128 tokenFees) public {
    vm.assume(wethFees > 10 && wethFees < type(uint64).max && tokenFees > 0);
    uint256 _wethForMaintenance = (wethFees * WETH_FOR_MAINTENANCE) / DISTRIBUTION_BASE;
    uint256 _wethForCardinality = (wethFees * WETH_FOR_CARDINALITY) / DISTRIBUTION_BASE;

    vm.mockCall(
      address(mockWeth),
      abi.encodeWithSelector(IERC20.transfer.selector, governance, _wethForMaintenance + _wethForCardinality),
      abi.encode(true)
    );

    vm.prank(address(mockPoolManager));
    feeManager.depositFromPoolManager(wethFees, tokenFees);

    (uint256 depositedWethForFullRange, uint256 depositedTokenForFullRange) = feeManager.poolManagerDeposits(mockPoolManager);

    assertGe(depositedWethForFullRange, 0);
    assertGe(depositedTokenForFullRange, 0);
  }

  function testUpdatePoolManagerDepositOnMaxCardinality(uint128 wethFees, uint128 tokenFees) public {
    vm.assume(wethFees > 10 && wethFees < type(uint64).max && tokenFees > 0);
    uint256 _wethForMaintenance = (wethFees * WETH_FOR_MAINTENANCE) / DISTRIBUTION_BASE;

    feeManager.setPoolCardinalityForTest(mockPoolManager, 0, feeManager.poolCardinalityMax(), 0);

    vm.expectCall(address(mockWeth), abi.encodeWithSelector(IERC20.transfer.selector, address(governance), _wethForMaintenance));

    vm.prank(address(mockPoolManager));
    feeManager.depositFromPoolManager(wethFees, tokenFees);

    (uint256 depositedWethForFullRange, ) = feeManager.poolManagerDeposits(mockPoolManager);

    assertEq(depositedWethForFullRange, wethFees - _wethForMaintenance);
  }

  function testEmitEvent(uint128 wethFees, uint128 tokenFees) public {
    vm.assume(wethFees > 10 && wethFees < type(uint64).max && tokenFees > 0);
    vm.prank(address(mockPoolManager));
    vm.expectEmit(false, false, false, true);

    uint256 _wethForMaintenance = (wethFees * WETH_FOR_MAINTENANCE) / DISTRIBUTION_BASE;
    uint256 _wethForCardinality = (wethFees * WETH_FOR_CARDINALITY) / DISTRIBUTION_BASE;

    vm.mockCall(
      address(mockWeth),
      abi.encodeWithSelector(IERC20.transfer.selector, governance, _wethForMaintenance + _wethForCardinality),
      abi.encode(true)
    );

    emit FeesDeposited(
      mockPoolManager,
      wethFees - _wethForMaintenance - _wethForCardinality,
      tokenFees,
      _wethForMaintenance,
      _wethForCardinality
    );

    feeManager.depositFromPoolManager(wethFees, tokenFees);
  }
}

contract UnitFeeManagerSetPoolCardinalityMax is Base {
  function testRevertIfNotGovernance(uint16 _cardinalityMax) public {
    vm.expectRevert(abi.encodeWithSelector(IRoles.Unauthorized.selector, address(this), feeManager.DEFAULT_ADMIN_ROLE()));

    feeManager.setPoolCardinalityMax(_cardinalityMax);
  }

  function testSetPoolCardinalityMax(uint16 _cardinalityMax) public {
    vm.prank(governance);
    feeManager.setPoolCardinalityMax(_cardinalityMax);

    assertEq(feeManager.poolCardinalityMax(), _cardinalityMax);
  }
}

contract UnitFeeManagerSetPoolCardinalityTarget is Base {
  function testRevertIfNotGovernance(IPoolManager _poolManager, uint16 _cardinality) public {
    vm.expectRevert(abi.encodeWithSelector(IRoles.Unauthorized.selector, address(this), feeManager.DEFAULT_ADMIN_ROLE()));

    feeManager.setPoolCardinalityTarget(_poolManager, _cardinality);
  }

  function testSetPoolCardinalityTarget(IPoolManager _poolManager, uint16 _cardinality) public {
    vm.prank(governance);
    feeManager.setPoolCardinalityTarget(_poolManager, _cardinality);

    (, , uint16 _customMax) = feeManager.poolCardinality(_poolManager);

    assertEq(_customMax, _cardinality);
  }
}

contract UnitFeeManagerIncreaseCardinality is Base {
  function setUp() public virtual override {
    super.setUp();
    vm.prank(governance);
    feeManager.setCardinalityJob(mockCardinalityJob);
    vm.startPrank(address(mockCardinalityJob));
  }

  function testRevertIfNotJob(
    IPoolManager _poolManager,
    uint256 _weth,
    uint16 _cardinality
  ) public {
    vm.stopPrank();
    vm.expectRevert(abi.encodeWithSelector(IFeeManager.FeeManager_NotCardinalityJob.selector));

    feeManager.increaseCardinality(_poolManager, _weth, _cardinality);
  }

  function testRevertIfCardinalityExceeded(
    IPoolManager _poolManager,
    uint256 _weth,
    uint16 _cardinality
  ) public {
    vm.assume(_cardinality < type(uint256).max && _cardinality > 0);

    feeManager.setPoolCardinalityForTest(_poolManager, _weth, _cardinality, 0);
    vm.stopPrank();
    vm.prank(governance);
    feeManager.setPoolCardinalityMax(0);
    vm.expectRevert(abi.encodeWithSelector(IFeeManager.FeeManager_CardinalityExceeded.selector));

    vm.prank(address(mockCardinalityJob));
    feeManager.increaseCardinality(_poolManager, _weth, _cardinality);
  }

  function testIncreaseCardinality(
    IPoolManager _poolManager,
    uint256 _weth,
    uint16 _cardinality
  ) public {
    vm.assume(_cardinality < 655 && _cardinality > 0);

    feeManager.setPoolCardinalityForTest(_poolManager, _weth, _cardinality, 0);
    feeManager.increaseCardinality(_poolManager, _weth, _cardinality);

    (uint256 _wethBalance, uint16 _cardinalityPool, uint16 _customMax) = feeManager.poolCardinality(_poolManager);
    assertEq(_wethBalance, 0);
    assertEq(_cardinalityPool, _cardinality);
    assertEq(_customMax, 0);
  }
}

contract UnitFeeManagerSetSwapGasCostMultiplier is Base {
  event SwapGasCostMultiplierChanged(uint256 _swapGasCostMultiplier);

  function testRevertIfNotGovernance(uint256 swapGasCostMultiplier) public {
    vm.expectRevert(abi.encodeWithSelector(IRoles.Unauthorized.selector, address(this), feeManager.DEFAULT_ADMIN_ROLE()));

    feeManager.setSwapGasCostMultiplier(swapGasCostMultiplier);
  }

  function testSetGasCostMultiplier(uint256 swapGasCostMultiplier) public {
    vm.prank(governance);
    feeManager.setSwapGasCostMultiplier(swapGasCostMultiplier);

    assertEq(feeManager.swapGasCostMultiplier(), swapGasCostMultiplier);
  }

  function testEmitEvent(uint256 swapGasCostMultiplier) public {
    vm.expectEmit(false, false, false, true);
    emit SwapGasCostMultiplierChanged(swapGasCostMultiplier);

    vm.prank(governance);
    feeManager.setSwapGasCostMultiplier(swapGasCostMultiplier);
  }
}

contract UnitFeeManagerSetMaintenanceGovernance is Base {
  event MaintenanceGovernanceChanged(address _maintenanceGovernance);

  function testRevertIfNotGovernance(address maintenanceGovernance) public {
    vm.expectRevert(abi.encodeWithSelector(IRoles.Unauthorized.selector, address(this), feeManager.DEFAULT_ADMIN_ROLE()));

    feeManager.setMaintenanceGovernance(maintenanceGovernance);
  }

  function testEmitEvent(address maintenanceGovernance) public {
    vm.expectEmit(false, false, false, true);
    emit MaintenanceGovernanceChanged(maintenanceGovernance);

    vm.prank(governance);
    feeManager.setMaintenanceGovernance(maintenanceGovernance);
  }
}

contract UnitFeeManagerFullRangeCallback is Base {
  uint256 balanceToken = 100 ether;
  uint256 balanceWeth = 100 ether;
  uint160 sqrtPriceX96 = 2**96;
  bool isWethToken0 = true;

  function setUp() public virtual override {
    super.setUp();

    feeManager.setPoolManagerDeposits(mockPoolManager, balanceWeth, balanceToken);
  }

  function testRevertIfCallerIsInvalidPoolManager(
    address notPoolManager,
    uint256 neededWeth,
    uint256 neededToken
  ) public {
    vm.mockCall(
      address(mockPoolManagerFactory),
      abi.encodeWithSelector(IPoolManagerFactory.isChild.selector, notPoolManager),
      abi.encode(false)
    );

    vm.expectRevert(abi.encodeWithSelector(IFeeManager.FeeManager_InvalidPoolManager.selector, notPoolManager));

    vm.prank(notPoolManager);
    feeManager.increaseFullRangePosition(mockPool, mockToken, neededWeth, neededToken, isWethToken0);
  }

  function testRevertIfInvalidTokenLiquidity(uint256 neededToken) public {
    vm.assume(neededToken > 0);
    uint256 neededWeth = 0;

    balanceWeth = 0;
    balanceToken = neededToken - 1;

    feeManager.setPoolManagerDeposits(mockPoolManager, balanceWeth, balanceToken);

    vm.expectRevert(abi.encodeWithSelector(IFeeManager.FeeManager_InvalidTokenLiquidity.selector));

    vm.prank(address(mockPoolManager));
    feeManager.increaseFullRangePosition(mockPool, mockToken, neededWeth, neededToken, isWethToken0);
  }

  function testRevertIfSmallSwap(uint256 neededWeth, uint256 neededToken) public {
    neededWeth = (100 ether + 100);
    vm.assume(balanceToken > neededToken);

    vm.expectRevert(abi.encodeWithSelector(IFeeManager.FeeManager_SmallSwap.selector));

    vm.prank(address(mockPoolManager));
    feeManager.increaseFullRangePosition(mockPool, mockToken, neededWeth, neededToken, isWethToken0);
  }

  function testUniswapV3PoolSwap(uint128 neededWeth, uint128 neededToken) public {
    vm.assume(neededWeth > neededToken / sqrtPriceX96);
    vm.assume(balanceToken > neededToken);
    vm.assume(neededWeth > balanceWeth);
    vm.assume((neededWeth - balanceWeth) > TOTAL_COST);

    int256 amountSwap = int256(balanceToken - neededToken);
    int256 neededWethResult = -int256(uint256(neededWeth));

    if (isWethToken0) {
      vm.mockCall(address(mockPool), abi.encodeWithSelector(IUniswapV3PoolActions.swap.selector), abi.encode(neededWethResult, amountSwap));
    } else {
      vm.mockCall(address(mockPool), abi.encodeWithSelector(IUniswapV3PoolActions.swap.selector), abi.encode(amountSwap, neededWethResult));
    }

    vm.mockCall(address(mockPool), abi.encodeWithSelector(IUniswapV3PoolState.slot0.selector), abi.encode(sqrtPriceX96, 0, 0, 0, 0, 0, 0));

    vm.expectCall(address(mockPool), abi.encodeWithSelector(IUniswapV3PoolActions.swap.selector));

    vm.prank(address(mockPoolManager));
    feeManager.increaseFullRangePosition(mockPool, mockToken, neededWeth, neededToken, isWethToken0);
  }

  function testRevertIfExcessiveLiquidityLeftOnAnySide(uint128 neededWeth, uint128 neededToken) public {
    vm.assume(neededWeth > neededToken);

    vm.assume((balanceToken) > neededToken);
    vm.assume((balanceWeth * 99) / DISTRIBUTION_BASE > neededWeth);

    if (isWethToken0) {
      vm.mockCall(address(mockPool), abi.encodeWithSelector(IUniswapV3PoolActions.swap.selector), abi.encode(neededWeth, 0));
    } else {
      vm.mockCall(address(mockPool), abi.encodeWithSelector(IUniswapV3PoolActions.swap.selector), abi.encode(0, neededWeth));
    }

    vm.mockCall(address(mockPool), abi.encodeWithSelector(IUniswapV3PoolState.slot0.selector), abi.encode(sqrtPriceX96, 0, 0, 0, 0, 0, 0));

    vm.expectRevert(abi.encodeWithSelector(IFeeManager.FeeManager_ExcessiveLiquidityLeft.selector));

    vm.prank(address(mockPoolManager));
    feeManager.fullRangeCallback(mockPool, mockToken, neededWeth, neededToken);
  }

  function testTransfers(uint128 neededWeth, uint128 neededToken) public {
    feeManager.setPoolManagerDeposits(mockPoolManager, neededWeth, neededToken);

    vm.expectCall(address(mockToken), abi.encodeWithSelector(IERC20.transfer.selector, address(mockPool), neededToken));
    vm.expectCall(address(mockWeth), abi.encodeWithSelector(IERC20.transfer.selector, address(mockPool), neededWeth));

    vm.prank(address(mockPoolManager));
    feeManager.fullRangeCallback(mockPool, mockToken, neededWeth, neededToken);
  }
}

contract UnitFeeManagerUniswapV3SwapCallback is Base {
  function setUp() public override {
    super.setUp();

    vm.mockCall(
      address(mockPoolManagerFactory),
      abi.encodeWithSelector(IPoolManagerFactory.isSupportedPool.selector, mockPool),
      abi.encode(true)
    );
  }

  function testRevertIfInvalidUniswapPool(
    int256 amount0Delta,
    int256 amount1Delta,
    bool isWethToken0
  ) public {
    bytes memory _data = abi.encode(mockPool, isWethToken0, mockToken);
    vm.mockCall(
      address(mockPoolManagerFactory),
      abi.encodeWithSelector(IPoolManagerFactory.isSupportedPool.selector, mockPool),
      abi.encode(false)
    );

    vm.expectRevert(abi.encodeWithSelector(IFeeManager.FeeManager_InvalidUniswapPool.selector, mockPool));

    vm.prank(address(otherMockPool));
    feeManager.uniswapV3SwapCallback(amount0Delta, amount1Delta, _data);
  }

  function testTransferToken(
    int256 amount0Delta,
    int256 amount1Delta,
    bool isWethToken0
  ) public {
    bytes memory _data = abi.encode(mockPool, isWethToken0, mockToken);

    vm.expectCall(address(mockToken), abi.encodeWithSelector(IERC20.transfer.selector));

    vm.prank(address(mockPool));
    feeManager.uniswapV3SwapCallback(amount0Delta, amount1Delta, _data);
  }
}

contract UnitFeeManagerMigrateTo is Base {
  uint256 balanceToken = 100 ether;
  uint256 balanceWeth = 100 ether;
  uint16 cardinality = 15;

  function setUp() public virtual override {
    super.setUp();
    feeManager.setPoolManagerDeposits(mockPoolManager, balanceWeth, balanceToken);

    feeManager.setPoolCardinalityForTest(mockPoolManager, balanceWeth, cardinality, 0);
    feeManager.setPoolManagerDeposits(mockPoolManager, balanceWeth, balanceToken);
  }

  function testMigrateToInvalidPool() public {
    address notPoolManager = newAddress();
    vm.mockCall(
      address(mockPoolManagerFactory),
      abi.encodeWithSelector(IPoolManagerFactory.isChild.selector, notPoolManager),
      abi.encode(false)
    );

    vm.expectRevert(abi.encodeWithSelector(IFeeManager.FeeManager_InvalidPoolManager.selector, notPoolManager));

    vm.prank(notPoolManager);
    feeManager.migrateTo(otherMockFeeManager);
  }

  function testMigrateCallsNewFeeManagerWithCorrectData() public {
    vm.expectCall(
      address(otherMockFeeManager),
      abi.encodeWithSelector(
        IFeeManager.migrateFrom.selector,
        mockPoolManager,
        IFeeManager.PoolCardinality(balanceWeth, cardinality, 0),
        IFeeManager.FeeStore(balanceWeth, balanceToken)
      )
    );
    vm.prank(address(mockPoolManager));
    feeManager.migrateTo(otherMockFeeManager);
  }

  function testMigrateSendsTheCorrectAmountOfTokens() public {
    vm.expectCall(address(mockWeth), abi.encodeWithSelector(IERC20.transfer.selector, address(otherMockFeeManager), balanceWeth));
    vm.expectCall(address(mockToken), abi.encodeWithSelector(IERC20.transfer.selector, address(otherMockFeeManager), balanceToken));
    vm.prank(address(mockPoolManager));
    feeManager.migrateTo(otherMockFeeManager);
  }
}

contract UnitFeeManagerMigrateFrom is Base {
  uint256 balanceToken = 100 ether;
  uint256 balanceWeth = 100 ether;
  uint16 cardinality = 15;

  IFeeManager.PoolCardinality _poolCardinality = IFeeManager.PoolCardinality(balanceWeth, cardinality, 0);
  IFeeManager.FeeStore _poolDeposits = IFeeManager.FeeStore(balanceWeth, balanceToken);
  IFeeManager.PoolDistributionFees _poolDistribution = IFeeManager.PoolDistributionFees(WETH_FOR_MAINTENANCE, WETH_FOR_CARDINALITY, true);

  function testMigrateFromRevertsIfInvalidPool() public {
    address notPoolManager = newAddress();
    vm.mockCall(
      address(mockPoolManagerFactory),
      abi.encodeWithSelector(IPoolManagerFactory.isChild.selector, notPoolManager),
      abi.encode(false)
    );

    vm.expectRevert(abi.encodeWithSelector(IFeeManager.FeeManager_InvalidPoolManager.selector, notPoolManager));

    vm.prank(address(otherMockFeeManager));
    feeManager.migrateFrom(IPoolManager(notPoolManager), _poolCardinality, _poolDeposits, _poolDistribution);
  }

  function testMigrateFromRevertsIfInvalidOldFeeManager() public {
    IFeeManager _notOldFeeManager = IFeeManager(mockContract('notOldFeeManager'));
    vm.expectRevert(abi.encodeWithSelector(IFeeManager.FeeManager_InvalidOldFeeManager.selector, _notOldFeeManager));

    vm.prank(address(_notOldFeeManager));
    feeManager.migrateFrom(mockPoolManager, _poolCardinality, _poolDeposits, _poolDistribution);
  }

  function testMigrateFromRevertsIfCardinalityNotZero(
    uint256 _wethAmount,
    uint16 _cardinality,
    uint16 _customMax
  ) public {
    vm.assume(_wethAmount > 0);
    feeManager.setPoolCardinalityForTest(mockPoolManager, _wethAmount, _cardinality, _customMax);
    vm.expectRevert(abi.encodeWithSelector(IFeeManager.FeeManager_NonZeroCardinality.selector));
    vm.prank(address(otherMockFeeManager));
    feeManager.migrateFrom(mockPoolManager, _poolCardinality, _poolDeposits, _poolDistribution);
  }

  function testMigrateFromRevertsIfDepositsNotZero(uint128 _balanceWeth, uint128 _balanceToken) public {
    vm.assume(_balanceWeth > 0 || _balanceToken > 0);
    feeManager.setPoolManagerDeposits(mockPoolManager, _balanceWeth, _balanceToken);
    vm.expectRevert(abi.encodeWithSelector(IFeeManager.FeeManager_NonZeroPoolDeposits.selector));
    vm.prank(address(otherMockFeeManager));
    feeManager.migrateFrom(mockPoolManager, _poolCardinality, _poolDeposits, _poolDistribution);
  }

  function testMigrateFromRevertsIfDistributionPoolIsInitialized() public {
    feeManager.setPoolManagerDistributions(mockPoolManager, WETH_FOR_MAINTENANCE, WETH_FOR_CARDINALITY, true);
    vm.expectRevert(abi.encodeWithSelector(IFeeManager.FeeManager_InitializedPoolDistribution.selector));
    vm.prank(address(otherMockFeeManager));
    feeManager.migrateFrom(mockPoolManager, _poolCardinality, _poolDeposits, _poolDistribution);
  }

  function testMigrateFromSetsTheCorrectCardinality() public {
    vm.prank(address(otherMockFeeManager));
    feeManager.migrateFrom(mockPoolManager, _poolCardinality, _poolDeposits, _poolDistribution);

    (uint256 _wethForCardinality, uint16 _currentMax, ) = feeManager.poolCardinality(mockPoolManager);
    assertEq(_wethForCardinality, _poolCardinality.weth);
    assertEq(_currentMax, _poolCardinality.currentMax);
  }

  function testMigrateFromSetsTheCorrectDeposits() public {
    vm.prank(address(otherMockFeeManager));
    feeManager.migrateFrom(mockPoolManager, _poolCardinality, _poolDeposits, _poolDistribution);

    (uint256 _wethForFullRange, uint256 _tokenForFullRange) = feeManager.poolManagerDeposits(mockPoolManager);
    assertEq(_wethForFullRange, _poolDeposits.wethForFullRange);
    assertEq(_tokenForFullRange, _poolDeposits.tokenForFullRange);
  }

  function testMigrateFromSetsTheCorrectDistributions() public {
    vm.prank(address(otherMockFeeManager));
    feeManager.migrateFrom(mockPoolManager, _poolCardinality, _poolDeposits, _poolDistribution);

    (uint256 _wethForMainteance, uint256 _wethForCardinality, bool _isInitialized) = feeManager.poolDistribution(mockPoolManager);
    assertEq(_wethForMainteance, _poolDistribution.wethForMaintenance);
    assertEq(_wethForCardinality, _poolDistribution.wethForCardinality);
    assertEq(_isInitialized, _poolDistribution.isInitialized);
  }

  function testMigrateDeletesCardinalityFromOldPoolManager() public {
    vm.prank(address(mockPoolManager));
    feeManager.migrateTo(otherMockFeeManager);

    (uint256 weth, uint16 currentMax, uint16 customMax) = feeManager.poolCardinality(mockPoolManager);
    assertEq(weth, 0);
    assertEq(currentMax, 0);
    assertEq(customMax, 0);
  }

  function testMigrateDeletesDepositsFromOldPoolManager() public {
    vm.prank(address(mockPoolManager));
    feeManager.migrateTo(otherMockFeeManager);

    (uint256 wethForFullRange, uint256 tokenForFullRange) = feeManager.poolManagerDeposits(mockPoolManager);
    assertEq(wethForFullRange, 0);
    assertEq(tokenForFullRange, 0);
  }

  function testMigrateDeletesFeesFromOldPoolManager() public {
    vm.prank(address(mockPoolManager));
    feeManager.migrateTo(otherMockFeeManager);

    (uint256 wethForMaintenance, uint256 wethForCardinality, bool isInitialized) = feeManager.poolDistribution(mockPoolManager);
    assertEq(wethForMaintenance, 0);
    assertEq(wethForCardinality, 0);
    assertFalse(isInitialized);
  }
}

contract UnitFeeManagerSetWethForMaintenance is Base {
  event WethForMaintenanceChanged(uint256 _wethForMaintenance);

  function testRevertIfNotGovernance(uint256 wethForMaintenance) public {
    vm.expectRevert(abi.encodeWithSelector(IRoles.Unauthorized.selector, address(this), feeManager.DEFAULT_ADMIN_ROLE()));

    feeManager.setWethForMaintenance(mockPoolManager, wethForMaintenance);
  }

  function testRevertIfWethForMaintenanceExceeded(uint256 wethForMaintenance) public {
    vm.assume(wethForMaintenance > MAX_WETH_MAINTENANCE_THRESHOLD);
    vm.expectRevert(abi.encodeWithSelector(IFeeManager.FeeManager_WethForMaintenanceExceeded.selector));

    vm.prank(governance);
    feeManager.setWethForMaintenance(mockPoolManager, wethForMaintenance);
  }

  function testSetWethForMaintenance(uint256 wethForMaintenance) public {
    vm.assume(wethForMaintenance < MAX_WETH_MAINTENANCE_THRESHOLD);
    vm.prank(governance);
    feeManager.setWethForMaintenance(mockPoolManager, wethForMaintenance);
    (uint256 _wethForMaintenance, , ) = feeManager.poolDistribution(mockPoolManager);

    assertEq(_wethForMaintenance, wethForMaintenance);
  }

  function testEmitEvent(uint256 wethForMaintenance) public {
    vm.assume(wethForMaintenance < MAX_WETH_MAINTENANCE_THRESHOLD);
    expectEmitNoIndex();
    emit WethForMaintenanceChanged(wethForMaintenance);

    vm.prank(governance);
    feeManager.setWethForMaintenance(mockPoolManager, wethForMaintenance);
  }
}

contract UnitFeeManagerGetMaxCardinalityForPool is Base {
  function testMaxCardinalityHigher(uint16 _customMax) public {
    uint16 _poolCardinalityMax = feeManager.poolCardinalityMax();
    vm.assume(_customMax <= _poolCardinalityMax);
    feeManager.setPoolCardinalityForTest(mockPoolManager, 0, 0, _customMax);
    assertEq(feeManager.getMaxCardinalityForPool(mockPoolManager), _poolCardinalityMax);
  }

  function testCustomCardinalityHigher(uint16 _customMax) public {
    uint16 _poolCardinalityMax = feeManager.poolCardinalityMax();
    vm.assume(_customMax >= _poolCardinalityMax);
    feeManager.setPoolCardinalityForTest(mockPoolManager, 0, 0, _customMax);
    assertEq(feeManager.getMaxCardinalityForPool(mockPoolManager), _customMax);
  }
}

contract UnitFeeManagerSetWethForCardinality is Base {
  event WethForCardinalityChanged(uint256 _wethForCardinality);

  function testRevertIfNotGovernance(uint256 wethForCardinality) public {
    vm.expectRevert(abi.encodeWithSelector(IRoles.Unauthorized.selector, address(this), feeManager.DEFAULT_ADMIN_ROLE()));

    feeManager.setWethForCardinality(mockPoolManager, wethForCardinality);
  }

  function testRevertIfWethForCardinalityExceeded(uint256 wethForCardinality) public {
    vm.assume(wethForCardinality > MAX_WETH_MAINTENANCE_THRESHOLD);
    vm.expectRevert(abi.encodeWithSelector(IFeeManager.FeeManager_WethForCardinalityExceeded.selector));

    vm.prank(governance);
    feeManager.setWethForCardinality(mockPoolManager, wethForCardinality);
  }

  function testSetWethForCardinality(uint256 wethForCardinality) public {
    vm.assume(wethForCardinality < MAX_WETH_MAINTENANCE_THRESHOLD);
    vm.prank(governance);
    feeManager.setWethForCardinality(mockPoolManager, wethForCardinality);
    (, uint256 _wethForCardinality, ) = feeManager.poolDistribution(mockPoolManager);

    assertEq(_wethForCardinality, wethForCardinality);
  }

  function testEmitEvent(uint256 wethForCardinality) public {
    vm.assume(wethForCardinality < MAX_WETH_MAINTENANCE_THRESHOLD);
    expectEmitNoIndex();
    emit WethForCardinalityChanged(wethForCardinality);

    vm.prank(governance);
    feeManager.setWethForCardinality(mockPoolManager, wethForCardinality);
  }
}
