// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4 <0.9.0;

import 'uni-v3-core/interfaces/IUniswapV3Pool.sol';
import 'uni-v3-periphery/libraries/LiquidityAmounts.sol';
import 'solidity-utils/test/DSTestPlus.sol';

import '@interfaces/ILockManagerFactory.sol';

import '@contracts/PoolManager.sol';
import '@contracts/strategies/Strategy.sol';

import '@test/utils/TestConstants.sol';
import '@test/utils/ContractDeploymentAddress.sol';

contract PoolManagerForTest is PoolManager {
  constructor(address _admin) payable PoolManager() {
    _grantRole(DEFAULT_ADMIN_ROLE, _admin);
  }

  function setPoolLiquidityForTest(uint256 _poolLiquidity) public {
    poolLiquidity = _poolLiquidity;
  }

  function setAmountAdded(uint256 _amountInWeth, uint256 _amountInToken) public {
    _amountWeth = _amountInWeth;
    _amountToken = _amountInToken;
  }

  function createAndInitializePoolForTest(uint160 _sqrtPriceX96) external {
    _createAndInitializePool(_sqrtPriceX96);
  }

  function mintLiquidityForFullRange(address donor, uint128 liquidity) external {
    _mintLiquidityForFullRange(donor, liquidity);
  }

  function getTicksForTest() public view returns (int24 __tickLower, int24 __tickUpper) {
    __tickUpper = _TICK_UPPER;
    __tickLower = _TICK_LOWER;
  }

  function feesDistribution(uint256 _totalToken0, uint256 _totalToken1) public {
    _feesDistribution(_totalToken0, _totalToken1);
  }

  function setSeededBalanceForTest(address owner, uint256 balance) external {
    seederBalance[owner] = balance;
  }

  function setRewardRatesForTest(uint256 wethPerSeededLiquidity, uint256 tokenPerSeededLiquidity) external {
    poolRewards = PoolRewards({wethPerSeededLiquidity: wethPerSeededLiquidity, tokenPerSeededLiquidity: tokenPerSeededLiquidity});
  }

  function setSeederRewardsForTest(
    address owner,
    uint256 wethAvailable,
    uint256 tokenAvailable
  ) external {
    seederRewards[owner] = SeederRewards(0, 0, wethAvailable, tokenAvailable);
  }

  function addRewards(uint256 _totalWeth, uint256 _totalToken) external {
    _addRewards(_totalWeth, _totalToken);
  }
}

abstract contract Base is DSTestPlus, TestConstants {
  address donor = label(newAddress(), 'donor');
  address admin = label(newAddress(), 'admin');

  IERC20 mockToken = IERC20(mockContract('mockToken'));
  IERC20 mockWeth = IERC20(mockContract(WETH_ADDRESS, 'mockWeth'));
  IPoolManagerFactory mockPoolManagerFactory = IPoolManagerFactory(mockContract('mockPoolManagerFactory'));
  IPoolManagerDeployer mockPoolManagerDeployer = IPoolManagerDeployer(mockContract('mockPoolManagerDeployer'));
  ILockManager mockLockManager = ILockManager(mockContract('mockLockManager'));
  IFeeManager mockFeeManager = IFeeManager(mockContract('mockFeeManager'));
  IStrategy mockStrategy = IStrategy(mockContract('mockStrategy'));
  ILockManagerFactory mockLockManagerFactory = ILockManagerFactory(mockContract('mockLockManagerFactory'));
  IPriceOracle mockPriceOracle = IPriceOracle(mockContract('mockPriceOracle'));
  IUniswapV3Pool mockPool;
  PoolManagerForTest mockPoolManager;
  PoolManager poolManager;
  IStrategy.LiquidityPosition[] positions;

  uint24 fee = 1;
  uint160 sqrtPriceX96 = 5;
  int24 tickSpacing = 6;
  uint256 constant BASE = 1 ether;
  uint256 constant _REWARDS_PERCENTAGE_FEE_MANAGER = 50_000;
  uint256 constant _DISTRIBUTION_BASE = 100_000;

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
    vm.mockCall(address(mockPoolManagerFactory), abi.encodeWithSelector(IPoolManagerFactory.priceOracle.selector), abi.encode(mockPriceOracle));
    vm.mockCall(address(mockPriceOracle), abi.encodeWithSignature('isManipulated(address)'), abi.encode(false));
    vm.mockCall(address(mockPool), abi.encodeWithSelector(IUniswapV3PoolImmutables.tickSpacing.selector), abi.encode(tickSpacing));
    vm.mockCall(
      address(mockPoolManagerFactory),
      abi.encodeWithSelector(IPoolManagerFactory.lockManagerFactory.selector),
      abi.encode(mockLockManagerFactory)
    );
    vm.mockCall(address(mockPoolManagerFactory), abi.encodeWithSelector(IPoolManagerFactory.strategy.selector), abi.encode(mockStrategy));
    vm.mockCall(
      address(mockLockManagerFactory),
      abi.encodeWithSelector(ILockManagerFactory.createLockManager.selector),
      abi.encode(mockLockManager)
    );

    // mock needed calls of _createAndInitializePool and _initializePoolIfNeeded functions
    vm.mockCall(address(UNISWAP_V3_FACTORY), abi.encodeWithSelector(IUniswapV3Factory.getPool.selector), abi.encode(mockPool));
    vm.mockCall(address(UNISWAP_V3_FACTORY), abi.encodeWithSelector(IUniswapV3Factory.createPool.selector), abi.encode(mockPool));
    vm.mockCall(address(mockPool), abi.encodeWithSelector(IUniswapV3PoolState.slot0.selector), abi.encode(sqrtPriceX96, 0, 0, 0, 0, 0, false));

    vm.mockCall(
      address(mockPoolManagerDeployer),
      abi.encodeWithSelector(IPoolManagerDeployer.POOL_MANAGER_FACTORY.selector),
      abi.encode(mockPoolManagerFactory)
    );

    vm.startPrank(address(mockPoolManagerDeployer));
    mockPoolManager = new PoolManagerForTest(admin);
    poolManager = new PoolManager();
    vm.stopPrank();
  }
}

contract UnitPoolManagerConstructor is Base {
  function testFactorySendParams() public {
    assertEq(mockPoolManager.FEE(), fee);
    assertEq(address(mockPoolManager.POOL_MANAGER_FACTORY()), address(mockPoolManagerFactory));
    assertEq(address(mockPoolManager.TOKEN()), address(mockToken));
    assertEq(address(mockPoolManager.lockManager()), address(mockLockManager));
    assertEq(address(mockPoolManager.WETH()), address(mockWeth));
  }

  function testCreateAndInitUniPoolIfNecessary(int24 tickSpacing) public {
    vm.assume(tickSpacing != 0);

    // force the factory to return that the pool hasn't been created
    vm.mockCall(address(UNISWAP_V3_FACTORY), abi.encodeWithSelector(IUniswapV3Factory.getPool.selector), abi.encode(address(0)));
    vm.mockCall(address(UNISWAP_V3_FACTORY), abi.encodeWithSelector(IUniswapV3Factory.createPool.selector), abi.encode(mockPool));
    vm.mockCall(address(mockPool), abi.encodeWithSelector(IUniswapV3PoolImmutables.tickSpacing.selector), abi.encode(tickSpacing));

    // expect pool creation and initialization
    if (address(mockToken) > address(mockWeth)) {
      vm.expectCall(address(UNISWAP_V3_FACTORY), abi.encodeWithSelector(IUniswapV3Factory.createPool.selector, mockToken, mockWeth, fee));
    } else {
      vm.expectCall(address(UNISWAP_V3_FACTORY), abi.encodeWithSelector(IUniswapV3Factory.createPool.selector, mockWeth, mockToken, fee));
    }

    vm.expectCall(address(mockPool), abi.encodeWithSelector(IUniswapV3PoolActions.initialize.selector, sqrtPriceX96));

    vm.prank(address(mockPoolManagerDeployer));
    mockPoolManager = new PoolManagerForTest(admin);
  }

  function testInitUniPoolIfNecessary(int24 tickSpacing) public {
    vm.assume(tickSpacing != 0);

    // Set sqrt price to 0
    vm.mockCall(address(mockPool), abi.encodeWithSelector(IUniswapV3PoolState.slot0.selector), abi.encode(0, 0, 0, 0, 0, 0, false));
    vm.mockCall(address(mockPool), abi.encodeWithSelector(IUniswapV3PoolImmutables.tickSpacing.selector), abi.encode(tickSpacing));

    // expect pool creation and initialization
    vm.expectCall(address(mockPool), abi.encodeWithSelector(IUniswapV3PoolActions.initialize.selector, sqrtPriceX96));

    vm.prank(address(mockPoolManagerDeployer));
    mockPoolManager = new PoolManagerForTest(admin);
  }

  function testPassIfInitialized(int24 tickSpacing, uint160 sqrtPriceX96) public {
    vm.assume(sqrtPriceX96 > 0);
    vm.assume(tickSpacing != 0);

    vm.mockCall(address(mockPool), abi.encodeWithSelector(IUniswapV3PoolImmutables.tickSpacing.selector), abi.encode(tickSpacing));

    vm.prank(address(mockPoolManagerDeployer));
    mockPoolManager = new PoolManagerForTest(admin);
  }
}

contract UnitPoolManagerIncreaseFullRangePositionAsFactoryOrDonor is Base {
  function setUp() public virtual override {
    super.setUp();
    vm.mockCall(address(mockPool), abi.encodeWithSelector(IUniswapV3PoolActions.mint.selector), abi.encode(2, 2));
  }

  function testRevertIfInvalidPoolManagerFactory(uint32 liquidity) public {
    address notFactory = newAddress();

    vm.expectRevert(IPoolManager.PoolManager_OnlyFactory.selector);

    vm.prank(notFactory);
    mockPoolManager.increaseFullRangePosition(donor, liquidity, sqrtPriceX96);
  }

  function testAllowsCallingByDonor(uint32 liquidity) public virtual {
    vm.assume(liquidity > 0);

    vm.prank(donor);
    mockPoolManager.increaseFullRangePosition(donor, liquidity, sqrtPriceX96);

    assertEq(mockPoolManager.seederBalance(donor), liquidity);
  }

  function testExpectCallMint(uint32 liquidity) public {
    vm.assume(liquidity > 0);

    vm.expectCall(address(mockPool), abi.encodeWithSelector(IUniswapV3PoolActions.mint.selector, address(mockPoolManager)));

    vm.prank(address(mockPoolManagerFactory));
    mockPoolManager.increaseFullRangePosition(donor, liquidity, sqrtPriceX96);
  }

  function testIncreaseSeededAmounts(uint32 liquidity) public {
    vm.assume(liquidity > 100);
    uint256 _mintedWethAmount = uint256(liquidity / 2);
    uint256 _mintedTokenAmount = uint256(liquidity / 2);

    vm.mockCall(
      address(mockPool),
      abi.encodeWithSelector(IUniswapV3PoolActions.mint.selector, address(mockPoolManager)),
      abi.encode(_mintedTokenAmount, _mintedWethAmount)
    );

    vm.prank(address(mockPoolManagerFactory));
    mockPoolManager.increaseFullRangePosition(donor, liquidity, sqrtPriceX96);
    assertEq(mockPoolManager.poolLiquidity(), liquidity);
    assertEq(mockPoolManager.seederBalance(donor), liquidity);
  }

  uint256 internal constant _SLIPPAGE_PERCENTAGE = 2_000;

  function testRevertIfPoolManipulated(uint32 liquidity) public {
    vm.assume(liquidity > 100);

    (uint160 _sqrtPriceX96Pool, , , , , , ) = mockPoolManager.POOL().slot0();
    uint160 _currentSlippage = uint160(PRBMath.mulDiv(_sqrtPriceX96Pool, _SLIPPAGE_PERCENTAGE, _DISTRIBUTION_BASE));
    uint160 sqrPriceManipulated = _sqrtPriceX96Pool + _currentSlippage + 1;

    vm.prank(address(mockPoolManagerFactory));

    vm.expectRevert(abi.encodeWithSelector(IPoolManager.PoolManager_PoolManipulated.selector));
    mockPoolManager.increaseFullRangePosition(donor, liquidity, sqrPriceManipulated);
  }

  function testUpdatePoolLiquidity(uint32 liquidity) public {
    uint256 initialLiquidity = liquidity / 2;
    mockPoolManager.setPoolLiquidityForTest(initialLiquidity);

    vm.prank(address(mockPoolManagerFactory));
    mockPoolManager.increaseFullRangePosition(donor, liquidity, sqrtPriceX96);

    assertEq(mockPoolManager.poolLiquidity(), initialLiquidity + liquidity);
  }

  function testDonorHasNoRewardsAfterIncreasingTheFullRangeIfThereAreRewards(uint32 liquidity, uint128 seededBalance) public virtual {
    vm.assume(seededBalance > 0);
    vm.assume(liquidity > 100);
    mockPoolManager.setPoolLiquidityForTest(seededBalance);

    mockPoolManager.addRewards(100 ether, 100 ether);

    vm.prank(donor);
    mockPoolManager.increaseFullRangePosition(donor, liquidity, sqrtPriceX96);

    (uint256 _wethClaimable, uint256 _tokenClaimable) = mockPoolManager.claimable(donor);

    assertEq(_wethClaimable, 0);
    assertEq(_tokenClaimable, 0);
  }
}

contract UnitPoolManagerIncreaseFullRangePositionAsJob is Base {
  uint160 _sqrtPriceX96;

  function setUp() public virtual override {
    super.setUp();

    (_sqrtPriceX96, , , , , , ) = mockPoolManager.POOL().slot0();
    vm.mockCall(address(mockPool), abi.encodeWithSelector(IUniswapV3PoolActions.mint.selector), abi.encode(2, 2));
    mockPoolManager.setAmountAdded(1 ether, 1 ether);
  }

  function testIncreasesFullRangePosition(uint256 _wethAmount, uint256 _tokenAmount) public {
    vm.expectCall(
      address(mockFeeManager),
      abi.encodeWithSelector(
        IFeeManager.increaseFullRangePosition.selector,
        mockPool,
        mockToken,
        _wethAmount,
        _tokenAmount,
        address(mockWeth) <= address(mockToken)
      )
    );

    (uint256 _amountWeth, uint256 _amountToken) = mockPoolManager.increaseFullRangePosition(_wethAmount, _tokenAmount);
    assertFalse(_amountWeth == 0);
    assertFalse(_amountToken == 0);
  }
}

contract UnitPoolManagerMintLiquidityForFullRange is Base {
  function setUp() public virtual override {
    super.setUp();
    vm.mockCall(address(mockPool), abi.encodeWithSelector(IUniswapV3PoolActions.mint.selector), abi.encode(2, 2));
    vm.mockCall(address(poolManager), abi.encodeWithSelector(IPoolManagerGovernor.feeManager.selector), abi.encode(mockFeeManager));
  }

  function testRevertIfInvalidFeeManager(uint64 wethAmount, uint64 tokenAmount) public {
    vm.expectRevert(abi.encodeWithSelector(IPoolManager.PoolManager_InvalidFeeManager.selector));

    vm.prank(newAddress());
    poolManager.mintLiquidityForFullRange(wethAmount, tokenAmount);
  }

  function testMintCallbackFullRange(uint64 wethAmount, uint64 tokenAmount) public {
    vm.assume(wethAmount > 0 && tokenAmount > 0);
    vm.expectCall(address(mockPool), abi.encodeWithSelector(IUniswapV3PoolActions.mint.selector));
    vm.prank(address(mockFeeManager));
    poolManager.mintLiquidityForFullRange(wethAmount, tokenAmount);
  }

  function testStoredLiquidityFullRangeIsIncreased(address donor, uint128 liquidity) public {
    vm.assume(liquidity < type(uint128).max / 2);
    mockPoolManager.mintLiquidityForFullRange(donor, liquidity);
    uint256 _liquidityPositionBefore = mockPoolManager.poolLiquidity();
    assertEq(_liquidityPositionBefore, liquidity);

    mockPoolManager.mintLiquidityForFullRange(donor, liquidity);
    uint256 _liquidityPositionAfter = mockPoolManager.poolLiquidity();
    assertEq(_liquidityPositionAfter, _liquidityPositionBefore + liquidity);
  }
}

contract UnitPoolManagerUniswapV3MintCallback is Base {
  bytes public data = abi.encode(address(mockFeeManager));

  function setUp() public virtual override {
    super.setUp();
    vm.mockCall(address(mockPoolManager), abi.encodeWithSelector(IPoolManager.POOL.selector), abi.encode(mockPool));
    vm.mockCall(address(mockToken), abi.encodeWithSelector(IERC20.transferFrom.selector), abi.encode(true));
    vm.mockCall(address(mockWeth), abi.encodeWithSelector(IERC20.transferFrom.selector), abi.encode(true));
  }

  function testRevertIfInvalidPool(uint256 amount0Owed, uint256 amount1Owed) public {
    vm.expectRevert(abi.encodeWithSelector(IPoolManager.PoolManager_OnlyPool.selector));

    vm.prank(newAddress());
    mockPoolManager.uniswapV3MintCallback(amount0Owed, amount1Owed, data);
  }

  function testWithFeeManager(uint256 amount0Owed, uint256 amount1Owed) public {
    vm.expectCall(
      address(mockFeeManager),
      abi.encodeWithSelector(IFeeManager.fullRangeCallback.selector, mockPool, mockToken, amount1Owed, amount0Owed)
    );

    vm.prank(address(mockPool));
    mockPoolManager.uniswapV3MintCallback(amount0Owed, amount1Owed, data);
  }

  function testWithDonor(uint256 amount0Owed, uint256 amount1Owed) public {
    vm.assume(amount0Owed > 0 && amount1Owed > 0);

    address donor = newAddress();
    data = abi.encode(donor);

    vm.expectCall(address(mockToken), abi.encodeWithSelector(IERC20.transferFrom.selector, donor, address(mockPool), amount0Owed));
    vm.expectCall(address(mockWeth), abi.encodeWithSelector(IERC20.transferFrom.selector, donor, address(mockPool), amount1Owed));

    vm.prank(address(mockPool));
    mockPoolManager.uniswapV3MintCallback(amount0Owed, amount1Owed, data);
  }
}

contract UnitPoolManagerDeprecateLockManager is Base {
  event LockManagerDeprecated(ILockManager _oldLockManager, ILockManager _newLockManager);
  ILockManager newLockManager = ILockManager(mockContract('newLockManager'));

  function setUp() public virtual override {
    super.setUp();
    vm.mockCall(address(mockLockManager), abi.encodeWithSelector(ILockManager.withdrawalData.selector), abi.encode(true, 0, 0));
    vm.mockCall(
      address(mockLockManagerFactory),
      abi.encodeWithSelector(ILockManagerFactory.createLockManager.selector),
      abi.encode(newLockManager)
    );

    vm.mockCall(address(mockPoolManagerFactory), abi.encodeWithSelector(IPoolManagerFactory.owner.selector), abi.encode(admin));
  }

  function testRevertIfNotDeprecated() public {
    vm.mockCall(address(mockLockManager), abi.encodeWithSelector(ILockManager.withdrawalData.selector), abi.encode(false, 0, 0));

    vm.expectRevert(IPoolManager.PoolManager_ActiveLockManager.selector);
    mockPoolManager.deprecateLockManager();
  }

  function testCreatesLockManager() public {
    mockPoolManager.deprecateLockManager();

    assertEq(address(mockPoolManager.lockManager()), address(newLockManager));
  }

  function testMarksLockManagerAsDeprecated() public {
    mockPoolManager.deprecateLockManager();

    assertEq(address(mockPoolManager.deprecatedLockManagers(0)), address(mockLockManager));
  }

  function testEmitEvent() public {
    expectEmitNoIndex();

    emit LockManagerDeprecated(mockLockManager, newLockManager);

    mockPoolManager.deprecateLockManager();
  }
}

contract UnitPoolManagerFeesDistribution is Base {
  uint256 _totalToken0 = 10 ether;
  uint256 _totalToken1 = 20 ether;
  uint256 _poolLiquidity = 100 ether;

  function setUp() public virtual override {
    super.setUp();

    mockPoolManager.setPoolLiquidityForTest(_poolLiquidity);

    vm.mockCall(address(mockWeth), abi.encodeWithSelector(IERC20.transfer.selector), abi.encode(true));
    vm.mockCall(address(mockToken), abi.encodeWithSelector(IERC20.transfer.selector), abi.encode(true));
  }

  function testCallsFeeManagerDeposit() public {
    vm.expectCall(
      address(mockFeeManager),
      abi.encodeWithSelector(IFeeManager.depositFromPoolManager.selector, _totalToken1 / 2, _totalToken0 / 2)
    );
    mockPoolManager.feesDistribution(_totalToken0, _totalToken1);
  }

  function testCallsTransfer() public {
    vm.expectCall(address(mockToken), abi.encodeWithSelector(IERC20.transfer.selector, address(mockFeeManager), _totalToken0 / 2));
    vm.expectCall(address(mockWeth), abi.encodeWithSelector(IERC20.transfer.selector, address(mockFeeManager), _totalToken1 / 2));
    mockPoolManager.feesDistribution(_totalToken0, _totalToken1);
  }
}

contract UnitPoolManagerFeesDistributionWithBurnedBalance is Base {
  uint256 _totalToken0 = 10 ether;
  uint256 _totalToken1 = 20 ether;
  uint256 _poolLiquidity = 100 ether;

  function setUp() public virtual override {
    super.setUp();

    mockPoolManager.setSeededBalanceForTest(donor, _poolLiquidity / 2);

    mockPoolManager.setPoolLiquidityForTest(_poolLiquidity);

    vm.prank(donor);
    mockPoolManager.burn(_poolLiquidity / 2);

    vm.mockCall(address(mockWeth), abi.encodeWithSelector(IERC20.transfer.selector), abi.encode(true));
    vm.mockCall(address(mockToken), abi.encodeWithSelector(IERC20.transfer.selector), abi.encode(true));
  }

  function testCallsFeeManagerDeposit() public {
    vm.expectCall(
      address(mockFeeManager),
      abi.encodeWithSelector(IFeeManager.depositFromPoolManager.selector, (_totalToken1 * 3) / 4, (_totalToken0 * 3) / 4)
    );
    mockPoolManager.feesDistribution(_totalToken0, _totalToken1);
  }

  function testCallsTransfer() public {
    vm.expectCall(address(mockToken), abi.encodeWithSelector(IERC20.transfer.selector, address(mockFeeManager), (_totalToken0 * 3) / 4));
    vm.expectCall(address(mockWeth), abi.encodeWithSelector(IERC20.transfer.selector, address(mockFeeManager), (_totalToken1 * 3) / 4));
    mockPoolManager.feesDistribution(_totalToken0, _totalToken1);
  }
}

contract UnitPoolManagerBurn is Base {
  event SeederLiquidityBurned(uint256 liquidity);
  uint256 balance = 10 ether;
  uint256 seededLiquidity = balance * 100;

  function setUp() public virtual override {
    super.setUp();
    mockPoolManager.setPoolLiquidityForTest(seededLiquidity);
    mockPoolManager.setSeededBalanceForTest(admin, balance);
  }

  function testRevertIfZeroAmount() public {
    vm.expectRevert(IPoolManager.PoolManager_ZeroAmount.selector);
    mockPoolManager.burn(0);
  }

  function testEmitEvent(uint256 liquidity) public {
    vm.assume(liquidity > 0 && liquidity < balance);
    expectEmitNoIndex();
    emit SeederLiquidityBurned(liquidity);

    vm.prank(admin);
    mockPoolManager.burn(liquidity);
  }

  function testBurnSeederLiquidity(uint256 liquidity) public {
    vm.assume(liquidity > 0 && liquidity < balance);

    vm.prank(admin);
    mockPoolManager.burn(liquidity);

    assertEq(mockPoolManager.seederBalance(admin), balance - liquidity);
    assertEq(mockPoolManager.seederBurned(admin), liquidity);
    assertEq(mockPoolManager.poolLiquidity(), seededLiquidity);
  }

  function testBurnSeederLiquidityVotingPowerRemains(uint256 liquidity) public {
    vm.assume(liquidity > 0 && liquidity < balance);

    vm.prank(admin);
    mockPoolManager.burn(liquidity);
    assertEq(mockPoolManager.votingPower(admin), balance);
  }
}

contract UnitPoolManagerBurn1 is Base {
  int24 _tickLower;
  int24 _tickUpper;

  function setUp() public override {
    super.setUp();

    (_tickLower, _tickUpper) = mockPoolManager.getTicksForTest();
    vm.mockCall(address(mockPool), abi.encodeWithSelector(IUniswapV3PoolActions.burn.selector, _tickLower, _tickUpper, 1), abi.encode(''));
  }

  function testRevertIfNotOracle() public {
    vm.expectRevert(IPoolManager.PoolManager_InvalidPriceOracle.selector);
    mockPoolManager.burn1();
  }

  function testBurnLiquidity() public {
    vm.expectCall(address(mockPool), abi.encodeWithSelector(IUniswapV3PoolActions.burn.selector, _tickLower, _tickUpper, 1));
    vm.prank(address(mockPriceOracle));
    mockPoolManager.burn1();
  }
}

contract UnitPoolManagerCollectFees is Base {
  event FeesCollected(uint256 wethFees, uint256 tokenFees);

  uint256 amount = 100 ether;
  int24 _tickLower;
  int24 _tickUpper;

  function setUp() public virtual override {
    super.setUp();
    vm.mockCall(address(mockWeth), abi.encodeWithSelector(IERC20.transfer.selector), abi.encode(true));
    vm.mockCall(address(mockToken), abi.encodeWithSelector(IERC20.transfer.selector), abi.encode(true));

    (_tickLower, _tickUpper) = mockPoolManager.getTicksForTest();
    mockPoolManager.setPoolLiquidityForTest(1);

    vm.mockCall(address(mockPool), abi.encodeWithSelector(IUniswapV3PoolActions.burn.selector, _tickLower, _tickUpper, 0), abi.encode(''));

    vm.mockCall(
      address(mockPool),
      abi.encodeWithSelector(
        IUniswapV3PoolActions.collect.selector,
        address(mockPoolManager),
        _tickLower,
        _tickUpper,
        type(uint128).max,
        type(uint128).max
      ),
      abi.encode(amount, amount)
    );
  }

  function testCollectWithCorrectParameters() public {
    vm.mockCall(address(mockPoolManagerFactory), abi.encodeWithSelector(IPoolManagerFactory.feeCollectorJob.selector), abi.encode(address(0)));

    uint256 _totalFeeToken0 = (amount * _REWARDS_PERCENTAGE_FEE_MANAGER) / _DISTRIBUTION_BASE;
    uint256 _totalFeeToken1 = (amount * _REWARDS_PERCENTAGE_FEE_MANAGER) / _DISTRIBUTION_BASE;

    vm.expectCall(address(mockPool), abi.encodeWithSelector(IUniswapV3PoolActions.burn.selector, _tickLower, _tickUpper, 0));

    vm.expectCall(
      address(mockFeeManager),
      abi.encodeWithSelector(mockFeeManager.depositFromPoolManager.selector, _totalFeeToken0, _totalFeeToken1)
    );

    vm.expectEmit(false, false, false, true);
    emit FeesCollected(amount, amount);

    mockPoolManager.collectFees();
  }

  function testCollectJobWithCorrectParameters() public {
    vm.mockCall(address(this), abi.encodeWithSelector(IFeeCollectorJob.collectMultiplier.selector), abi.encode(0));
    vm.mockCall(address(mockPool), abi.encodeWithSelector(IUniswapV3PoolState.slot0.selector), abi.encode(1000, 0, 0, 0, 0, 0, 0));
    vm.mockCall(
      address(mockPoolManagerFactory),
      abi.encodeWithSelector(IPoolManagerFactory.feeCollectorJob.selector),
      abi.encode(address(this))
    );

    uint256 _totalFeeToken0 = (amount * _REWARDS_PERCENTAGE_FEE_MANAGER) / _DISTRIBUTION_BASE;
    uint256 _totalFeeToken1 = (amount * _REWARDS_PERCENTAGE_FEE_MANAGER) / _DISTRIBUTION_BASE;

    vm.expectCall(address(mockPool), abi.encodeWithSelector(IUniswapV3PoolActions.burn.selector, _tickLower, _tickUpper, 0));

    vm.expectCall(
      address(mockFeeManager),
      abi.encodeWithSelector(mockFeeManager.depositFromPoolManager.selector, _totalFeeToken0, _totalFeeToken1)
    );

    vm.expectEmit(false, false, false, true);
    emit FeesCollected(amount, amount);

    mockPoolManager.collectFees();
  }
}

contract UnitPoolManagerClaimRewards is Base {
  uint192 mockWethPerSeededLiquidity = 100;
  uint192 mockTokenPerSeededLiquidity = 100;
  uint256 availableRewards = 10;
  uint256 expectedClaimableWeth = PRBMath.mulDiv(userBalance, mockWethPerSeededLiquidity, BASE) + availableRewards;
  uint256 expectedClaimableToken = PRBMath.mulDiv(userBalance, mockTokenPerSeededLiquidity, BASE) + availableRewards;
  uint256 userBalance = 150;
  address rewardReceiver = label(newAddress(), 'rewardReceiver');

  event ClaimedRewards(address _user, address _to, uint256 _wethAmount, uint256 _tokenAmount);

  function setUp() public virtual override {
    super.setUp();

    mockPoolManager.setSeededBalanceForTest(address(this), userBalance);
    mockPoolManager.setRewardRatesForTest(mockWethPerSeededLiquidity, mockTokenPerSeededLiquidity);
    mockPoolManager.setSeederRewardsForTest(address(this), availableRewards, availableRewards);

    vm.mockCall(address(mockWeth), abi.encodeWithSelector(IERC20.transfer.selector, rewardReceiver), abi.encode(true));
    vm.mockCall(address(mockToken), abi.encodeWithSelector(IERC20.transfer.selector, rewardReceiver), abi.encode(true));
  }

  function testRevertIfZeroAddress() public {
    vm.expectRevert(IPoolManager.PoolManager_ZeroAddress.selector);
    mockPoolManager.claimRewards(address(0));
  }

  function testRevertIfNoReward() public {
    mockPoolManager.setSeederRewardsForTest(address(this), 0, 0);

    mockPoolManager.setRewardRatesForTest(0, 0);

    vm.expectRevert(IPoolManager.PoolManager_NoRewardsToClaim.selector);
    mockPoolManager.claimRewards(rewardReceiver);
  }

  function testSetRewardsToZero() public {
    mockPoolManager.claimRewards(rewardReceiver);

    (, , uint256 _wethAvailable, uint256 _tokenAvailable) = mockPoolManager.seederRewards(address(this));

    assertEq(_wethAvailable, 0);
    assertEq(_tokenAvailable, 0);
  }

  function testReturnClaimReward(uint256 wethAvailable, uint256 tokenAvailable) public {
    vm.assume(wethAvailable > 0 && tokenAvailable > 0);
    mockPoolManager.setSeederRewardsForTest(address(this), wethAvailable, tokenAvailable);
    (uint256 _wethReward, uint256 _tokenReward) = mockPoolManager.claimRewards(rewardReceiver);

    assertEq(_wethReward, wethAvailable);
    assertEq(_tokenReward, tokenAvailable);
  }

  function testTransfer() public {
    vm.expectCall(address(mockWeth), abi.encodeWithSelector(IERC20.transfer.selector, rewardReceiver, expectedClaimableWeth));
    vm.expectCall(address(mockToken), abi.encodeWithSelector(IERC20.transfer.selector, rewardReceiver, expectedClaimableToken));

    mockPoolManager.claimRewards(rewardReceiver);
  }

  function testEmitEvent() public {
    vm.expectEmit(false, false, false, true);
    emit ClaimedRewards(address(this), rewardReceiver, expectedClaimableWeth, expectedClaimableToken);

    mockPoolManager.claimRewards(rewardReceiver);
  }
}

contract UnitPoolManagerAddRewards is Base {
  uint256 seededBalance = 150;
  uint192 mockWethPerLockedLiquidity = 100;
  uint192 mockTokenPerLockedLiquidity = 100;

  function setUp() public virtual override {
    super.setUp();

    mockPoolManager.setPoolLiquidityForTest(seededBalance);
    mockPoolManager.setRewardRatesForTest(mockWethPerLockedLiquidity, mockTokenPerLockedLiquidity);
  }

  function testRevertIfZeroRewards() public {
    vm.expectRevert(abi.encodeWithSelector(IPoolManager.PoolManager_ZeroAmount.selector));
    mockPoolManager.addRewards(0, 0);
  }

  function testAddsToRewards(uint128 _wethRewards, uint128 _tokenRewards) public {
    vm.assume(_wethRewards > 0 || _tokenRewards > 0);
    mockPoolManager.addRewards(_wethRewards, _tokenRewards);
    (uint256 wethPerSeededLiquidity, uint256 tokenPerSeededLiquidity) = mockPoolManager.poolRewards();
    assertEq(wethPerSeededLiquidity, mockWethPerLockedLiquidity + (_wethRewards * BASE) / seededBalance);
    assertEq(tokenPerSeededLiquidity, mockTokenPerLockedLiquidity + (_tokenRewards * BASE) / seededBalance);
  }
}

contract UnitPoolManagerCreateAndInitializePool is Base {
  function setUp() public virtual override {
    super.setUp();
    vm.mockCall(address(mockPool), abi.encodeWithSelector(IUniswapV3PoolActions.initialize.selector, sqrtPriceX96), abi.encode(''));
    vm.mockCall(
      address(mockPool),
      abi.encodeWithSelector(IUniswapV3PoolActions.increaseObservationCardinalityNext.selector, STARTING_CARDINALITY),
      abi.encode('')
    );
    vm.mockCall(
      address(UNISWAP_V3_FACTORY),
      abi.encodeWithSelector(IUniswapV3Factory.createPool.selector, mockWeth, mockToken, fee),
      abi.encode(mockPool)
    );
  }

  function testCreateAndInitializePool() public {
    vm.expectCall(address(mockPool), abi.encodeWithSelector(IUniswapV3PoolActions.initialize.selector, sqrtPriceX96));
    vm.expectCall(
      address(mockPool),
      abi.encodeWithSelector(IUniswapV3PoolActions.increaseObservationCardinalityNext.selector, STARTING_CARDINALITY)
    );
    mockPoolManager.createAndInitializePoolForTest(sqrtPriceX96);
  }
}

contract UnitPoolManagerInitializePoolIfNeeded is Base {
  function setUp() public virtual override {
    super.setUp();
    vm.mockCall(address(mockPool), abi.encodeWithSelector(IUniswapV3PoolActions.initialize.selector, sqrtPriceX96), abi.encode(''));
    vm.mockCall(
      address(mockPool),
      abi.encodeWithSelector(IUniswapV3PoolActions.increaseObservationCardinalityNext.selector, STARTING_CARDINALITY),
      abi.encode('')
    );
  }

  function testNeedsInitializeAndIncreaseCardinality(uint16 observationCardinalityNextExisting) public {
    vm.assume(STARTING_CARDINALITY > observationCardinalityNextExisting);
    vm.mockCall(
      address(mockPool),
      abi.encodeWithSelector(IUniswapV3PoolState.slot0.selector),
      abi.encode(0, 0, 0, 0, observationCardinalityNextExisting, 0, 0)
    );
    vm.expectCall(address(mockPool), abi.encodeWithSelector(IUniswapV3PoolActions.initialize.selector, sqrtPriceX96));
    vm.expectCall(
      address(mockPool),
      abi.encodeWithSelector(IUniswapV3PoolActions.increaseObservationCardinalityNext.selector, STARTING_CARDINALITY)
    );
    mockPoolManager.createAndInitializePoolForTest(sqrtPriceX96);
  }

  function testNoNeedsInitialize(uint160 sqrtPriceX96Existing, uint16 observationCardinalityNextExisting) public {
    vm.assume(STARTING_CARDINALITY > observationCardinalityNextExisting);
    vm.assume(sqrtPriceX96Existing > 0 && sqrtPriceX96Existing != sqrtPriceX96);
    vm.mockCall(
      address(mockPool),
      abi.encodeWithSelector(IUniswapV3PoolState.slot0.selector),
      abi.encode(sqrtPriceX96Existing, 0, 0, 0, observationCardinalityNextExisting, 0, 0)
    );
    vm.expectCall(address(mockPool), abi.encodeWithSelector(IUniswapV3PoolActions.initialize.selector, sqrtPriceX96));
    vm.expectCall(
      address(mockPool),
      abi.encodeWithSelector(IUniswapV3PoolActions.increaseObservationCardinalityNext.selector, STARTING_CARDINALITY)
    );
    mockPoolManager.createAndInitializePoolForTest(sqrtPriceX96);
  }
}
