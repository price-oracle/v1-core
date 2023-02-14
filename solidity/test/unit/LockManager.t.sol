// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4 <0.9.0;

import 'isolmate/interfaces/tokens/IERC20.sol';
import 'solidity-utils/test/DSTestPlus.sol';

import '@interfaces/ILockManager.sol';

import '@contracts/PoolManager.sol';
import '@contracts/LockManager.sol';
import '@contracts/strategies/Strategy.sol';
import '@contracts/utils/LiquidityAmounts08.sol';

import '@test/utils/TestConstants.sol';

contract LockManagerForTest is LockManager {
  IStrategy.LiquidityPosition public _liquidityPositionForTest;
  IStrategy.Position public _positionForTest;
  bool public overrideGetNeededPosition = false;

  constructor(IPoolManager _poolManager, IPoolManager.LockManagerParams memory _lockManagerParams)
    LockManager(_poolManager, _lockManagerParams)
  {}

  function addPositionForTest(
    int24 lowerTick,
    int24 upperTick,
    uint128 liquidity
  ) external {
    _positionsList.push(IStrategy.LiquidityPosition(lowerTick, upperTick, liquidity));
    _positionsLiquidity[lowerTick][upperTick] = liquidity;
  }

  function setRewardRatesForTest(uint256 wethPerLockedWeth, uint256 tokenPerLockedWeth) external {
    poolRewards = PoolRewards({wethPerLockedWeth: wethPerLockedWeth, tokenPerLockedWeth: tokenPerLockedWeth});
  }

  function setUserRewardsForTest(
    address owner,
    uint256 wethAvailable,
    uint256 tokenAvailable
  ) external {
    userRewards[owner] = UserRewards(0, 0, wethAvailable, tokenAvailable);
  }

  function setBalanceForTest(address owner, uint256 balance) external {
    balanceOf[owner] = balance;
  }

  function setTotalLockForTest(uint256 balance) external {
    totalSupply = balance;
  }

  function setDeprecatedForTest(bool _deprecated) external {
    deprecated = _deprecated;
  }

  function getPositionLiquidityForTest(int24 lowerTick, int24 upperTick) external view returns (uint128 _liquidity) {
    _liquidity = _positionsLiquidity[lowerTick][upperTick];
  }

  function cancelVotes(address _voter, uint256 _votes) external {}

  function _cancelVotes(address _voter, uint256 _votes) internal override {
    LockManagerForTest(address(this)).cancelVotes(_voter, _votes);
  }

  function setWithdrawalsEnabled(bool _withdrawalsEnabled) external {
    withdrawalData.withdrawalsEnabled = _withdrawalsEnabled;
  }

  function setTotalToWithdraw(uint256 _totalWeth, uint256 _totalToken) external {
    withdrawalData.totalWeth = _totalWeth;
    withdrawalData.totalToken = _totalToken;
  }

  function calculateTaxesForTest(uint256 amount0Fees, uint256 amount1Fees) external pure returns (uint256 amount0Tax, uint256 amount1Tax) {
    amount0Tax = PRBMath.mulDiv(amount0Fees, _TAX_PERCENTAGE, _DISTRIBUTION_BASE);
    amount1Tax = PRBMath.mulDiv(amount1Fees, _TAX_PERCENTAGE, _DISTRIBUTION_BASE);
  }

  function liquidityAmountsForTest(
    int24 _lowerTick,
    int24 _upperTick,
    uint128 _liquidity
  )
    external
    view
    returns (
      uint256 wethMint,
      uint256 tokenMint,
      uint256 wethBurn,
      uint256 tokenBurn,
      uint256 wethFees,
      uint256 tokenFees
    )
  {
    tokenMint = 0; // We always mint 100% WETH positions, no token needed

    // Fees should be greater than burn amounts
    if (IS_WETH_TOKEN0) {
      (wethFees, tokenFees) = _getAmountsForLiquidity(_lowerTick, _upperTick, _liquidity);
    } else {
      (tokenFees, wethFees) = _getAmountsForLiquidity(_lowerTick, _upperTick, _liquidity);
    }

    wethMint = wethFees;
    wethBurn = wethFees / 2;
    tokenBurn = tokenFees / 2;
  }

  function _getAmountsForLiquidity(
    int24 _lowerTick,
    int24 _upperTick,
    uint128 _liquidity
  ) internal view returns (uint256 _amount0, uint256 _amount1) {
    uint160 _sqrtRatioX96 = TickMath.getSqrtRatioAtTick((_lowerTick + _upperTick) / 2);
    uint160 _minSqrtRatioX96 = TickMath.getSqrtRatioAtTick(_lowerTick);
    uint160 _maxSqrtRatioX96 = TickMath.getSqrtRatioAtTick(_upperTick);

    // We need to use LiquidityAmounts08 as FullMath is not compatible with solidity 0.8 and should be able to under/overflow.
    // getAmount0ForLiquidity relies on going into overflow and then coming back to a normal range to work.
    _amount0 = LiquidityAmounts08.getAmount0ForLiquidity(_sqrtRatioX96, _maxSqrtRatioX96, _liquidity);
    _amount1 = LiquidityAmounts08.getAmount1ForLiquidity(_minSqrtRatioX96, _sqrtRatioX96, _liquidity);
  }
}

contract RevertableStrategyForTest is Strategy {
  error SomethingTerrible();

  function getPositionToMint(
    IStrategy.LockManagerState calldata /* _lockManagerState */
  ) external pure override returns (IStrategy.LiquidityPosition memory) {
    revert SomethingTerrible();
  }

  function getPositionToBurn(
    Position calldata, /* _position */
    uint128, /* _positionLiquidity */
    IStrategy.LockManagerState calldata /* _lockManagerState */
  ) external pure override returns (IStrategy.LiquidityPosition memory) {
    revert SomethingTerrible();
  }
}

abstract contract Base is DSTestPlus, TestConstants {
  LockManagerForTest mockLockManager;

  address rewardReceiver = label(address(100), 'rewardReceiver');
  address governance = label(address(200), 'governance');

  IERC20 mockWeth = IERC20(mockContract(WETH_ADDRESS, 'mockWeth'));
  IERC20 mockToken = IERC20(mockContract('mockToken'));
  IUniswapV3Pool mockPool = IUniswapV3Pool(mockContract('mockPool'));

  IPoolManagerFactory mockPoolManagerFactory = IPoolManagerFactory(mockContract('mockPoolManagerFactory'));
  IStrategy mockStrategy = IStrategy(mockContract('mockStrategy'));
  IFeeManager mockFeeManager = IFeeManager(mockContract('mockFeeManager'));
  IPriceOracle mockPriceOracle = IPriceOracle(mockContract('mockPriceOracle'));
  IFeeCollectorJob mockFeeCollectorJob = IFeeCollectorJob(mockContract('mockFeeCollectorJob'));
  IPoolManager mockPoolManager;

  IStrategy.LiquidityPosition[] positions;
  int24 tickSpacing = 6;
  string mockTokenSymbol = 'TEST';
  uint24 mockFee = 500;
  uint256 initialBalance = 5 ether;
  uint256 constant BASE = 1 ether;
  uint256 constant _REWARDS_PERCENTAGE_FEEMANAGER = 20_000;
  uint256 constant _DISTRIBUTION_BASE = 100_000;

  function setUp() public virtual {
    mockPoolManager = IPoolManager(
      computeDeterministicAddress(address(mockPoolManagerFactory), abi.encode(address(mockPool)), type(PoolManager).creationCode)
    );
    mockContract(address(mockPoolManager), 'mockPoolManager');

    vm.mockCall(address(mockPool), abi.encodeWithSelector(IUniswapV3PoolImmutables.tickSpacing.selector), abi.encode(tickSpacing));
    vm.mockCall(address(mockPoolManager), abi.encodeWithSelector(IPoolManager.POOL.selector), abi.encode(mockPool));
    vm.mockCall(address(mockPoolManager), abi.encodeWithSelector(IPoolManager.TOKEN.selector), abi.encode(mockToken));
    vm.mockCall(address(mockPoolManager), abi.encodeWithSelector(IPoolManagerGovernor.feeManager.selector), abi.encode(mockFeeManager));
    vm.mockCall(address(mockPoolManager), abi.encodeWithSelector(IPoolManager.FEE.selector), abi.encode(mockFee));
    vm.mockCall(
      address(mockPoolManager),
      abi.encodeWithSelector(IPoolManagerGovernor.POOL_MANAGER_FACTORY.selector),
      abi.encode(mockPoolManagerFactory)
    );
    vm.mockCall(address(mockPoolManagerFactory), abi.encodeWithSelector(IPoolManagerFactory.strategy.selector), abi.encode(mockStrategy));
    vm.mockCall(address(mockPoolManagerFactory), abi.encodeWithSelector(IPoolManagerFactory.priceOracle.selector), abi.encode(mockPriceOracle));
    vm.mockCall(
      address(mockPoolManagerFactory),
      abi.encodeWithSelector(IPoolManagerFactory.feeCollectorJob.selector),
      abi.encode(mockFeeCollectorJob)
    );
    vm.mockCall(address(mockFeeCollectorJob), abi.encodeWithSelector(IFeeCollectorJob.collectMultiplier.selector), abi.encode(0));
    vm.mockCall(address(mockPriceOracle), abi.encodeWithSignature('isManipulated(address)'), abi.encode(false));
    vm.mockCall(address(mockToken), abi.encodeWithSelector(IERC20.symbol.selector), abi.encode(mockTokenSymbol));
    vm.mockCall(address(mockToken), abi.encodeWithSelector(IERC20.transfer.selector), abi.encode(true));
    vm.mockCall(address(mockWeth), abi.encodeWithSelector(IERC20.transfer.selector), abi.encode(true));

    mockLockManager = new LockManagerForTest(
      mockPoolManager,
      IPoolManager.LockManagerParams({
        factory: mockPoolManagerFactory,
        strategy: mockStrategy,
        pool: mockPool,
        fee: mockFee,
        token: mockToken,
        weth: mockWeth,
        isWethToken0: false,
        governance: governance,
        index: 0
      })
    );

    mockLockManager.setBalanceForTest(address(this), initialBalance);
    mockLockManager.setTotalLockForTest(initialBalance);
  }

  modifier assumeLiquidityPosition(IStrategy.LiquidityPosition memory _position) {
    _assumeValidTicks(_position.lowerTick, _position.upperTick);
    _;
  }

  modifier assumePosition(IStrategy.Position memory _position) {
    _assumeValidTicks(_position.lowerTick, _position.upperTick);
    _;
  }

  function _assumeValidTicks(int24 lowerTick, int24 upperTick) internal {
    vm.assume(upperTick > MIN_TICK && upperTick < MAX_TICK);
    vm.assume(lowerTick > MIN_TICK);
    vm.assume(upperTick - 11 > lowerTick); // Make sure the ticks are far enough from each other
  }

  function _mockPosition(
    int24 _lowerTick,
    int24 _upperTick,
    uint128 _liquidity,
    LockManagerForTest _lockManager
  ) internal {
    IStrategy.LiquidityPosition memory _position = IStrategy.LiquidityPosition({
      lowerTick: _lowerTick,
      upperTick: _upperTick,
      liquidity: _liquidity
    });

    _lockManager.addPositionForTest(_lowerTick, _upperTick, _liquidity);

    uint256 amount0Mint;
    uint256 amount1Mint;
    uint256 amount0Burn;
    uint256 amount1Burn;
    uint256 amount0Fees;
    uint256 amount1Fees;

    if (_lockManager.IS_WETH_TOKEN0()) {
      (amount0Mint, amount1Mint, amount0Burn, amount1Burn, amount0Fees, amount1Fees) = mockLockManager.liquidityAmountsForTest(
        _lowerTick,
        _upperTick,
        _liquidity
      );
    } else {
      (amount1Mint, amount0Mint, amount1Burn, amount0Burn, amount1Fees, amount0Fees) = mockLockManager.liquidityAmountsForTest(
        _lowerTick,
        _upperTick,
        _liquidity
      );
    }

    // Mock pool.collect()
    vm.mockCall(
      address(mockPool),
      abi.encodeWithSelector(
        IUniswapV3PoolActions.collect.selector,
        address(_lockManager),
        _lowerTick,
        _upperTick,
        type(uint128).max,
        type(uint128).max
      ),
      abi.encode(amount0Fees, amount1Fees)
    );

    // Mock pool.mint()
    vm.mockCall(
      address(mockPool),
      abi.encodeWithSelector(IUniswapV3PoolActions.mint.selector, address(_lockManager), _lowerTick, _upperTick, _liquidity, abi.encode()),
      abi.encode(amount0Mint, amount1Mint)
    );

    // Mock pool.burn()
    vm.mockCall(
      address(mockPool),
      abi.encodeWithSelector(IUniswapV3PoolActions.burn.selector, _lowerTick, _upperTick),
      abi.encode(amount0Burn, amount1Burn)
    );

    // Mock strategy.getPositionToBurn()
    vm.mockCall(address(mockStrategy), abi.encodeWithSelector(IStrategy.getPositionToBurn.selector), abi.encode(_position));

    // Mock strategy.getPositionToMint()
    vm.mockCall(address(mockStrategy), abi.encodeWithSelector(IStrategy.getPositionToMint.selector), abi.encode(_position));
  }

  function _mockPosition(
    int24 _lowerTick,
    int24 _upperTick,
    LockManagerForTest _lockManager
  ) internal {
    _mockPosition(_lowerTick, _upperTick, 0, _lockManager);
  }

  function _addAndMockPositions(
    uint256 _positionsCount,
    uint128 _liquidity,
    LockManagerForTest _lockManager
  ) public {
    for (uint256 positionIndex; positionIndex < _positionsCount; positionIndex++) {
      (int24 lowerTick, int24 upperTick) = _getLowerAndUpperTickForPosition(positionIndex);
      _mockPosition(lowerTick, upperTick, _liquidity, _lockManager);
    }
  }

  function _getLowerAndUpperTickForPosition(uint256 positionIndex) public pure returns (int24 lowerTick, int24 upperTick) {
    (lowerTick, upperTick) = (int24(int256(positionIndex + 1)) * 2, int24(int256(positionIndex + 1)) * 5);
  }

  function setIsWethToken0ForTest(bool isWethToken0) public {
    vm.mockCall(address(mockLockManager), abi.encodeWithSelector(ILockManager.IS_WETH_TOKEN0.selector), abi.encode(isWethToken0));
  }
}

contract UnitLockManagerClaimable is Base {
  function testClaimable(uint128 wethPerLockedWeth, uint128 tokenPerLockedWeth) public {
    mockLockManager.setRewardRatesForTest(wethPerLockedWeth, tokenPerLockedWeth);
    mockLockManager.setUserRewardsForTest(address(this), wethPerLockedWeth, tokenPerLockedWeth);

    uint256 _userBalance = mockLockManager.balanceOf(address(this));
    (uint256 _wethPaid, uint256 _tokenPaid, uint256 _wethAvailable, uint256 _tokenAvailable) = mockLockManager.userRewards(address(this));

    uint256 _claimWethShare = PRBMath.mulDiv(_userBalance, wethPerLockedWeth - _wethPaid, BASE);
    uint256 _claimTokenShare = PRBMath.mulDiv(_userBalance, tokenPerLockedWeth - _tokenPaid, BASE);

    (uint256 _wethClaimable, uint256 _tokenClaimable) = mockLockManager.claimable(address(this));

    assertEq(_wethClaimable, _claimWethShare + _wethAvailable);
    assertEq(_tokenClaimable, _claimTokenShare + _tokenAvailable);
  }
}

contract UnitLockManagerLock is Base {
  uint256 amountToLock = initialBalance - 2 ether;

  event Locked(uint256 _wethAmount);

  function setUp() public virtual override {
    super.setUp();

    vm.mockCall(
      address(mockWeth),
      abi.encodeWithSelector(IERC20.transferFrom.selector, address(this), address(mockLockManager), amountToLock),
      abi.encode(true)
    );
  }

  function testRevertIfZeroAmount() public {
    vm.expectRevert(ILockManager.LockManager_ZeroAmount.selector);
    mockLockManager.lock(0);
  }

  function testRevertIfDeprecated() public {
    mockLockManager.setDeprecatedForTest(true);

    vm.expectRevert(ILockManagerGovernor.LockManager_Deprecated.selector);
    mockLockManager.lock(amountToLock);
  }

  function testMintLockedWeth() public {
    uint256 supplyBefore = mockLockManager.totalSupply();
    mockLockManager.lock(amountToLock);
    assertEq(supplyBefore + amountToLock, mockLockManager.totalSupply());
  }

  function testTransferFrom() public virtual {
    vm.expectCall(
      address(mockWeth),
      abi.encodeWithSelector(IERC20.transferFrom.selector, address(this), address(mockLockManager), amountToLock)
    );

    mockLockManager.lock(amountToLock);
  }

  function testEmitEvent() public {
    expectEmitNoIndex();
    emit Locked(amountToLock);

    mockLockManager.lock(amountToLock);
  }

  function testAddToWethBalance() public {
    mockLockManager.lock(amountToLock);
    (, uint256 totalWeth, uint256 totalToken) = mockLockManager.withdrawalData();

    assertEq(totalWeth, amountToLock);
    assertEq(totalToken, 0);
  }
}

contract UnitLockManagerClaimRewards is Base {
  uint192 mockWethPerLockedWeth = 100;
  uint192 mockTokenPerLockedWeth = 100;
  uint256 availableRewards = 10;
  uint256 expectedClaimableWeth = PRBMath.mulDiv(userBalance, mockWethPerLockedWeth, BASE) + availableRewards;
  uint256 expectedClaimableToken = PRBMath.mulDiv(userBalance, mockTokenPerLockedWeth, BASE) + availableRewards;
  uint256 userBalance = 150;

  event ClaimedRewards(address _owner, address _to, uint256 _wethAmount, uint256 _tokenAmount);

  function setUp() public virtual override {
    super.setUp();

    mockLockManager.setBalanceForTest(address(this), userBalance);
    mockLockManager.setRewardRatesForTest(mockWethPerLockedWeth, mockTokenPerLockedWeth);
    mockLockManager.setUserRewardsForTest(address(this), availableRewards, availableRewards);

    vm.mockCall(address(mockWeth), abi.encodeWithSelector(IERC20.transfer.selector, rewardReceiver), abi.encode(true));
    vm.mockCall(address(mockToken), abi.encodeWithSelector(IERC20.transfer.selector, rewardReceiver), abi.encode(true));
  }

  function testRevertIfZeroAddress() public {
    vm.expectRevert(ILockManager.LockManager_ZeroAddress.selector);
    mockLockManager.claimRewards(address(0));
  }

  function testRevertIfNoReward() public {
    mockLockManager.setUserRewardsForTest(address(this), 0, 0);
    mockLockManager.setRewardRatesForTest(0, 0);

    vm.expectRevert(ILockManager.LockManager_NoRewardsToClaim.selector);
    mockLockManager.claimRewards(rewardReceiver);
  }

  function testSetRewardsToZero() public {
    mockLockManager.claimRewards(rewardReceiver);

    (, , uint256 _wethAvailable, uint256 _tokenAvailable) = mockLockManager.userRewards(address(this));

    assertEq(_wethAvailable, 0);
    assertEq(_tokenAvailable, 0);
  }

  function testReturnClaimReward(uint256 wethAvailable, uint256 tokenAvailable) public {
    vm.assume(wethAvailable > 0 && tokenAvailable > 0);
    mockLockManager.setUserRewardsForTest(address(this), wethAvailable, tokenAvailable);
    (uint256 _wethReward, uint256 _tokenReward) = mockLockManager.claimRewards(rewardReceiver);

    assertEq(_wethReward, wethAvailable);
    assertEq(_tokenReward, tokenAvailable);
  }

  function testTransfer() public {
    vm.expectCall(address(mockWeth), abi.encodeWithSelector(IERC20.transfer.selector, rewardReceiver, expectedClaimableWeth));
    vm.expectCall(address(mockToken), abi.encodeWithSelector(IERC20.transfer.selector, rewardReceiver, expectedClaimableToken));

    mockLockManager.claimRewards(rewardReceiver);
  }

  function testEmitEvent() public {
    expectEmitNoIndex();
    emit ClaimedRewards(address(this), rewardReceiver, expectedClaimableWeth, expectedClaimableToken);

    mockLockManager.claimRewards(rewardReceiver);
  }
}

contract UnitLockManagerAddRewards is Base {
  uint256 wethToAdd = 4 ether;
  uint256 tokenToAdd = 5 ether;
  uint256 totalLocked = 6 ether;

  event RewardsAdded(uint256 _wethAmount, uint256 _tokenAmount);

  function setUp() public virtual override {
    super.setUp();

    vm.mockCall(
      address(mockWeth),
      abi.encodeWithSelector(IERC20.transferFrom.selector, address(this), address(mockLockManager), wethToAdd),
      abi.encode(true)
    );

    vm.mockCall(
      address(mockWeth),
      abi.encodeWithSelector(IERC20.transferFrom.selector, address(this), address(mockLockManager), initialBalance),
      abi.encode(true)
    );

    vm.mockCall(
      address(mockToken),
      abi.encodeWithSelector(IERC20.transferFrom.selector, address(this), address(mockLockManager), tokenToAdd),
      abi.encode(true)
    );

    mockLockManager.lock(initialBalance);
  }

  function testRevertIfInvalidAmount() public {
    vm.expectRevert(ILockManager.LockManager_ZeroAmount.selector);
    mockLockManager.addRewards(0, 0);
  }

  function testRevertIfDeprecated() public {
    mockLockManager.setDeprecatedForTest(true);

    vm.expectRevert(ILockManagerGovernor.LockManager_Deprecated.selector);
    mockLockManager.addRewards(wethToAdd, tokenToAdd);
  }

  function testTransferFrom() public {
    vm.expectCall(address(mockWeth), abi.encodeWithSelector(IERC20.transferFrom.selector, address(this), address(mockLockManager), wethToAdd));
    vm.expectCall(address(mockToken), abi.encodeWithSelector(IERC20.transferFrom.selector, address(this), address(mockLockManager), tokenToAdd));

    mockLockManager.addRewards(wethToAdd, tokenToAdd);
  }

  function testEmitEvent() public {
    expectEmitNoIndex();
    emit RewardsAdded(wethToAdd, tokenToAdd);

    mockLockManager.addRewards(wethToAdd, tokenToAdd);
  }
}

contract UnitLockManagerCollectFees is Base {
  event FeesCollected(uint256 wethFees, uint256 tokenFees);

  function setUp() public virtual override {
    super.setUp();
    vm.mockCall(address(mockPool), abi.encodeWithSelector(IUniswapV3PoolActions.mint.selector), abi.encode(0, 0));
    vm.mockCall(address(mockPool), abi.encodeWithSelector(IUniswapV3PoolState.slot0.selector), abi.encode(MAX_SQRT_RATIO, 0, 0, 0, 0, 0, 0));
    vm.mockCall(
      address(mockPoolManager),
      abi.encodeWithSelector(IPoolManagerGovernor.POOL_MANAGER_FACTORY.selector),
      abi.encode(mockPoolManagerFactory)
    );
    vm.mockCall(address(mockPoolManagerFactory), abi.encodeWithSelector(IPoolManagerFactory.feeManager.selector), abi.encode(mockFeeManager));
  }

  function testWithConcentratedPositions(uint64 liquidity, bool asFeeCollectorJob) public {
    vm.assume(liquidity > 0);

    uint256 positionsCount = 5;
    uint256 totalTokenFees;
    uint256 totalWethFees;

    _addAndMockPositions(positionsCount, liquidity, mockLockManager);
    IStrategy.LiquidityPosition[] memory _liquidityPositions = mockLockManager.positionsList(0, positionsCount);
    IStrategy.Position[] memory _memoryPositions = new IStrategy.Position[](positionsCount);

    for (uint256 positionIndex; positionIndex < positionsCount; positionIndex++) {
      _memoryPositions[positionIndex] = IStrategy.Position(
        _liquidityPositions[positionIndex].lowerTick,
        _liquidityPositions[positionIndex].upperTick
      );

      (, , , , uint256 wethFees, uint256 tokenFees) = mockLockManager.liquidityAmountsForTest(
        _liquidityPositions[positionIndex].lowerTick,
        _liquidityPositions[positionIndex].upperTick,
        _liquidityPositions[positionIndex].liquidity
      );

      totalWethFees += wethFees;
      totalTokenFees += tokenFees;
    }

    vm.assume(totalWethFees > 0 && totalTokenFees > 0);

    (uint256 _wethTax, uint256 _tokenTax) = mockLockManager.calculateTaxesForTest(totalWethFees, totalTokenFees);

    vm.expectCall(address(mockFeeManager), abi.encodeWithSelector(IFeeManager.depositFromLockManager.selector, _wethTax, _tokenTax));

    expectEmitNoIndex();
    emit FeesCollected(totalWethFees, totalTokenFees);

    if (asFeeCollectorJob) {
      vm.prank(address(mockFeeCollectorJob));
    }

    mockLockManager.collectFees(_memoryPositions);
  }

  function testRevertIfSmallCollect(uint128 wethFees, uint128 tokenFees) public {
    vm.assume(wethFees > 0 && tokenFees > 0);
    vm.assume(wethFees < 1e21 && tokenFees < 1e21);

    // Ensure that the multiplier is big enough to outweigh the total amount of fees
    uint256 collectMultiplier = wethFees > tokenFees ? wethFees : tokenFees;
    uint256 positionsCount = 1;
    uint128 liquidity = 0;

    vm.mockCall(
      address(mockFeeCollectorJob),
      abi.encodeWithSelector(IFeeCollectorJob.collectMultiplier.selector),
      abi.encode(collectMultiplier)
    );

    _addAndMockPositions(positionsCount, liquidity, mockLockManager);

    IStrategy.LiquidityPosition[] memory _liquidityPositions = mockLockManager.positionsList(0, positionsCount);
    IStrategy.Position[] memory _memoryPositions = new IStrategy.Position[](positionsCount);

    for (uint256 positionIndex; positionIndex < positionsCount; positionIndex++) {
      _memoryPositions[positionIndex] = IStrategy.Position(
        _liquidityPositions[positionIndex].lowerTick,
        _liquidityPositions[positionIndex].upperTick
      );
    }

    vm.startPrank(address(mockFeeCollectorJob));
    vm.expectRevert(GasCheckLib.GasCheckLib_InsufficientFees.selector);
    mockLockManager.collectFees(_memoryPositions);
  }

  function testRevertIfPoolManipulated() public {
    uint256 positionsCount = 50;

    IStrategy.Position[] memory positions = new IStrategy.Position[](positionsCount);

    vm.mockCall(
      address(mockPoolManagerFactory),
      abi.encodeWithSelector(IPoolManagerFactory.priceOracle.selector),
      abi.encode(address(mockPriceOracle))
    );

    vm.mockCall(address(mockPriceOracle), abi.encodeWithSignature('isManipulated(address)', mockPool), abi.encode(true));

    vm.expectRevert(ILockManager.LockManager_PoolManipulated.selector);
    vm.prank(address(mockFeeCollectorJob));
    mockLockManager.collectFees(positions);
  }
}

contract UnitLockManagerBurn is Base {
  uint256 balance;
  uint256 burnAmount;

  function setUp() public virtual override {
    super.setUp();

    vm.mockCall(
      address(mockWeth),
      abi.encodeWithSelector(IERC20.transferFrom.selector, address(this), address(mockLockManager), initialBalance),
      abi.encode(true)
    );
    mockLockManager.approve(address(mockLockManager), initialBalance);
    mockLockManager.lock(initialBalance);
    balance = mockLockManager.balanceOf(address(this));
    burnAmount = balance / 2;
  }

  function testBurnLockWethTokens() public {
    mockLockManager.burn(burnAmount);
    assertEq(mockLockManager.balanceOf(address(this)), burnAmount);
  }

  function testRevertIfDeprecated() public {
    mockLockManager.setDeprecatedForTest(true);

    vm.expectRevert(ILockManagerGovernor.LockManager_Deprecated.selector);
    mockLockManager.burn(burnAmount);
  }

  function testBurnUpdatesRewards() public {
    address rewardsAdder = newAddress();

    vm.startPrank(rewardsAdder);

    uint256 wethToAdd = 4 ether;
    uint256 tokenToAdd = 5 ether;

    vm.mockCall(
      address(mockWeth),
      abi.encodeWithSelector(IERC20.transferFrom.selector, rewardsAdder, address(mockLockManager), wethToAdd),
      abi.encode(true)
    );

    vm.mockCall(
      address(mockWeth),
      abi.encodeWithSelector(IERC20.transferFrom.selector, rewardsAdder, address(mockLockManager), initialBalance),
      abi.encode(true)
    );

    vm.mockCall(
      address(mockToken),
      abi.encodeWithSelector(IERC20.transferFrom.selector, rewardsAdder, address(mockLockManager), tokenToAdd),
      abi.encode(true)
    );

    mockLockManager.addRewards(wethToAdd, tokenToAdd);

    vm.stopPrank();

    (uint256 _wethRewardsBefore, uint256 _tokenRewardsBefore) = mockLockManager.claimable(address(this));

    mockLockManager.burn(burnAmount);
    (uint256 _wethRewardsAfter, uint256 _tokenRewardsAfter) = mockLockManager.claimable(address(this));

    assertEq(_wethRewardsBefore, _wethRewardsAfter);
    assertEq(_tokenRewardsBefore, _tokenRewardsAfter);
  }

  function testBurnCancelsVotes() public {
    vm.expectCall(address(mockLockManager), abi.encodeWithSelector(LockManagerForTest.cancelVotes.selector, address(this), burnAmount));
    mockLockManager.burn(burnAmount);
  }
}

contract UnitLockManagerPositionsList is Base {
  uint256 _positionsCount = 12;
  IStrategy.LiquidityPosition[] _positions;

  function setUp() public override {
    super.setUp();
    for (uint256 i; i < _positionsCount; i++) {
      IStrategy.LiquidityPosition memory _position = IStrategy.LiquidityPosition({
        lowerTick: int24(int256(i * 2)),
        upperTick: int24(int256(i * 3)),
        liquidity: uint128(i * 4)
      });

      _positions.push(_position);
      mockLockManager.addPositionForTest(_position.lowerTick, _position.upperTick, _position.liquidity);
    }
  }

  function testReturnWholeList() public {
    IStrategy.LiquidityPosition[] memory _list = mockLockManager.positionsList(0, _positionsCount);
    assertPositions(expectedPositions(0, _positionsCount), _list);
  }

  function testReturnBeginningPart() public {
    IStrategy.LiquidityPosition[] memory _list = mockLockManager.positionsList(0, _positionsCount - 4);
    assertPositions(expectedPositions(0, _positionsCount - 4), _list);
  }

  function testReturnEndingPart() public {
    IStrategy.LiquidityPosition[] memory _list = mockLockManager.positionsList(4, _positionsCount);
    assertPositions(expectedPositions(4, _positionsCount), _list);
  }

  function testReturnMiddlePart() public {
    IStrategy.LiquidityPosition[] memory _list = mockLockManager.positionsList(4, _positionsCount - 6);
    assertPositions(expectedPositions(4, _positionsCount - 2), _list);
  }

  function testOutOfBoundaries() public {
    IStrategy.LiquidityPosition[] memory _list = mockLockManager.positionsList(4, _positionsCount + 5);
    assertPositions(expectedPositions(4, _positionsCount), _list);
  }

  function assertPositions(IStrategy.LiquidityPosition[] memory a, IStrategy.LiquidityPosition[] memory b) internal {
    assertEq(a.length, b.length, 'LENGTH_MISMATCH');

    for (uint256 i = 0; i < a.length; i++) {
      assertEq(a[i].lowerTick, b[i].lowerTick);
      assertEq(a[i].upperTick, b[i].upperTick);
      assertEq(a[i].liquidity, b[i].liquidity);
    }
  }

  function expectedPositions(uint256 startIndex, uint256 lastIndex)
    internal
    view
    returns (IStrategy.LiquidityPosition[] memory _expectedPositions)
  {
    uint256 length = lastIndex - startIndex;
    _expectedPositions = new IStrategy.LiquidityPosition[](length);
    for (uint256 i; i < length; i++) {
      _expectedPositions[i] = _positions[i + startIndex];
    }
  }
}

contract UnitLockManagerMintPosition is Base {
  event PositionMinted(IStrategy.LiquidityPosition _position, uint256 _amount0, uint256 _amount1);

  function testRevertIfPoolManipulated(bool _isWethToken0) public {
    setIsWethToken0ForTest(_isWethToken0);
    vm.mockCall(address(mockPriceOracle), abi.encodeWithSignature('isManipulated(address)'), abi.encode(true));
    vm.expectRevert(abi.encodeWithSelector(ILockManager.LockManager_PoolManipulated.selector));
    mockLockManager.mintPosition();
  }

  function testMint(
    IStrategy.LiquidityPosition memory _position,
    uint256 totalWethBefore,
    uint256 totalTokenBefore,
    bool _isWethToken0
  ) public assumeLiquidityPosition(_position) {
    vm.assume(_position.liquidity > 0 && _position.liquidity < type(uint64).max);
    setIsWethToken0ForTest(_isWethToken0);

    mockLockManager.setTotalToWithdraw(totalWethBefore, totalTokenBefore);
    _mockPosition(_position.lowerTick, _position.upperTick, _position.liquidity, mockLockManager);

    (uint256 wethMint, uint256 tokenMint, , , , ) = mockLockManager.liquidityAmountsForTest(
      _position.lowerTick,
      _position.upperTick,
      _position.liquidity
    );

    vm.assume(totalWethBefore > wethMint && totalTokenBefore > tokenMint);

    vm.expectCall(
      address(mockPool),
      abi.encodeWithSelector(
        IUniswapV3PoolActions.mint.selector,
        address(mockLockManager),
        _position.lowerTick,
        _position.upperTick,
        _position.liquidity,
        abi.encode()
      )
    );

    mockLockManager.mintPosition();
  }

  function testSubToTotalWethAndToken(
    IStrategy.Position memory _position,
    uint64 _liquidity,
    uint128 _totalWethBefore
  ) public assumePosition(_position) {
    (uint256 wethMint, , , , , ) = mockLockManager.liquidityAmountsForTest(_position.lowerTick, _position.upperTick, _liquidity);
    vm.assume(_liquidity > 0 && _totalWethBefore > wethMint);

    mockLockManager.setTotalToWithdraw(_totalWethBefore, 0);
    _mockPosition(_position.lowerTick, _position.upperTick, _liquidity, mockLockManager);

    mockLockManager.mintPosition();

    (, uint256 _totalWethAfter, ) = mockLockManager.withdrawalData();

    assertEq(_totalWethAfter, _totalWethBefore - wethMint);
  }

  function testPositionIsPushed(IStrategy.Position memory _position, bool isWethToken0) public assumePosition(_position) {
    mockLockManager.setTotalToWithdraw(30, 30);
    setIsWethToken0ForTest(isWethToken0);
    _mockPosition(_position.lowerTick, _position.upperTick, mockLockManager);
    uint256 index = mockLockManager.getPositionsCount();
    mockLockManager.mintPosition();
    assertEq(mockLockManager.getPositionsCount(), index + 1);
  }

  function testEmitEvent(
    IStrategy.LiquidityPosition memory _position,
    uint256 totalWethBefore,
    uint256 totalTokenBefore,
    bool _isWethToken0
  ) public assumeLiquidityPosition(_position) {
    vm.assume(_position.liquidity > 0 && _position.liquidity < type(uint64).max);
    setIsWethToken0ForTest(_isWethToken0);

    (uint256 wethMint, uint256 tokenMint, , , , ) = mockLockManager.liquidityAmountsForTest(
      _position.lowerTick,
      _position.upperTick,
      _position.liquidity
    );
    (uint256 amount0Mint, uint256 amount1Mint) = mockLockManager.IS_WETH_TOKEN0() ? (wethMint, tokenMint) : (tokenMint, wethMint);

    vm.assume(totalWethBefore > wethMint && totalTokenBefore > tokenMint);

    mockLockManager.setTotalToWithdraw(totalWethBefore, totalTokenBefore);
    _mockPosition(_position.lowerTick, _position.upperTick, _position.liquidity, mockLockManager);

    expectEmitNoIndex();
    emit PositionMinted(_position, amount0Mint, amount1Mint);

    mockLockManager.mintPosition();
  }
}

contract UnitLockManagerBurnPosition is Base {
  event PositionBurned(IStrategy.LiquidityPosition _position, uint256 _amount0, uint256 _amount1);

  function testRevertIfPoolManipulated(IStrategy.Position memory _position) public assumePosition(_position) {
    vm.mockCall(address(mockPriceOracle), abi.encodeWithSignature('isManipulated(address)'), abi.encode(true));
    vm.expectRevert(abi.encodeWithSelector(ILockManager.LockManager_PoolManipulated.selector));
    mockLockManager.burnPosition(_position);
  }

  function testBurnPosition(IStrategy.Position memory _position, uint64 _liquidity) public assumePosition(_position) {
    _mockPosition(_position.lowerTick, _position.upperTick, _liquidity, mockLockManager);
    vm.expectCall(
      address(mockPool),
      abi.encodeWithSelector(IUniswapV3PoolActions.burn.selector, _position.lowerTick, _position.upperTick, _liquidity)
    );
    mockLockManager.burnPosition(_position);
  }

  function testUpdateWithdrawalData(
    IStrategy.Position memory _position,
    uint64 _liquidity,
    uint256 totalWethBefore,
    uint256 totalTokenBefore
  ) public assumePosition(_position) {
    _mockPosition(_position.lowerTick, _position.upperTick, _liquidity, mockLockManager);
    (, , uint256 wethBurn, uint256 tokenBurn, , ) = mockLockManager.liquidityAmountsForTest(
      _position.lowerTick,
      _position.upperTick,
      _liquidity
    );

    vm.assume(type(uint256).max - wethBurn > totalWethBefore);
    vm.assume(type(uint256).max - tokenBurn > totalTokenBefore);

    mockLockManager.setTotalToWithdraw(totalWethBefore, totalTokenBefore);
    mockLockManager.burnPosition(_position);

    (, uint256 totalWeth, uint256 totalToken) = mockLockManager.withdrawalData();
    assertEq(totalWeth, totalWethBefore + wethBurn);
    assertEq(totalToken, totalTokenBefore + tokenBurn);
  }

  function testAddToTotalWethAndToken(
    IStrategy.Position memory _position,
    uint64 _liquidity,
    uint128 totalWethBefore,
    uint128 totalTokenBefore
  ) public assumePosition(_position) {
    vm.assume(_liquidity > 0);

    _mockPosition(_position.lowerTick, _position.upperTick, _liquidity, mockLockManager);
    (, , uint256 wethBurn, uint256 tokenBurn, , ) = mockLockManager.liquidityAmountsForTest(
      _position.lowerTick,
      _position.upperTick,
      _liquidity
    );

    vm.assume(totalWethBefore > wethBurn && totalTokenBefore > tokenBurn);

    mockLockManager.setTotalToWithdraw(totalWethBefore, totalTokenBefore);
    mockLockManager.burnPosition(_position);

    (, uint256 _totalWethAfter, uint256 _totalTokenAfter) = mockLockManager.withdrawalData();

    assertEq(_totalWethAfter, totalWethBefore + wethBurn);
    assertEq(_totalTokenAfter, totalTokenBefore + tokenBurn);
  }

  function testCollectFees(IStrategy.Position memory _position) public assumePosition(_position) {
    _mockPosition(_position.lowerTick, _position.upperTick, mockLockManager);

    vm.expectCall(
      address(mockPool),
      abi.encodeWithSelector(
        IUniswapV3PoolActions.collect.selector,
        address(mockLockManager),
        _position.lowerTick,
        _position.upperTick,
        type(uint128).max,
        type(uint128).max
      )
    );

    mockLockManager.burnPosition(_position);
  }

  function testDistributeFees(IStrategy.Position memory _position, uint64 _liquidity) public assumePosition(_position) {
    vm.assume(_liquidity > 0);

    _mockPosition(_position.lowerTick, _position.upperTick, _liquidity, mockLockManager);
    (, , uint256 wethBurn, uint256 tokenBurn, uint256 wethFees, uint256 tokenFees) = mockLockManager.liquidityAmountsForTest(
      _position.lowerTick,
      _position.upperTick,
      _liquidity
    );
    vm.assume(wethFees > wethBurn && tokenFees > tokenBurn);

    (uint256 taxWeth, uint256 taxToken) = mockLockManager.calculateTaxesForTest(wethFees - wethBurn, tokenFees - tokenBurn);

    vm.expectCall(address(mockFeeManager), abi.encodeWithSelector(IFeeManager.depositFromLockManager.selector, taxWeth, taxToken));
    mockLockManager.burnPosition(_position);
  }

  function testEmitEvent(IStrategy.LiquidityPosition memory _position) public assumeLiquidityPosition(_position) {
    vm.assume(_position.liquidity < type(uint64).max);
    _mockPosition(_position.lowerTick, _position.upperTick, _position.liquidity, mockLockManager);
    (, , uint256 wethBurn, uint256 tokenBurn, , ) = mockLockManager.liquidityAmountsForTest(
      _position.lowerTick,
      _position.upperTick,
      _position.liquidity
    );
    (uint256 amount0Burn, uint256 amount1Burn) = mockLockManager.IS_WETH_TOKEN0() ? (wethBurn, tokenBurn) : (tokenBurn, wethBurn);

    expectEmitNoIndex();
    emit PositionBurned(_position, amount0Burn, amount1Burn);

    mockLockManager.burnPosition(IStrategy.Position({lowerTick: _position.lowerTick, upperTick: _position.upperTick}));
  }
}

contract UnitLockManagerUniswapV3MintCallback is Base {
  using stdStorage for StdStorage;
  bytes _data = '';

  function setUp() public virtual override {
    super.setUp();
    stdstore.target(address(mockLockManager)).sig(mockLockManager.totalSupply.selector).checked_write(type(uint256).max);
    vm.mockCall(address(mockWeth), abi.encodeWithSelector(IERC20.transfer.selector), abi.encode(true));
  }

  function testRevertIfInvalidPool(uint256 amount0Owed, uint256 amount1Owed) public {
    vm.expectRevert(abi.encodeWithSelector(ILockManager.LockManager_OnlyPool.selector));

    vm.prank(newAddress());
    mockLockManager.uniswapV3MintCallback(amount0Owed, amount1Owed, _data);
  }

  function testRevertIfOverLimitMint(uint256 amount0Owed, uint256 amount1Owed) public {
    vm.assume(amount1Owed > 1);

    uint256 totalSupply = amount1Owed - 1;
    stdstore.target(address(mockLockManager)).sig(mockLockManager.totalSupply.selector).checked_write(totalSupply);

    vm.expectRevert(abi.encodeWithSelector(ILockManager.LockManager_OverLimitMint.selector, totalSupply, amount1Owed));

    vm.prank(address(mockPool));
    mockLockManager.uniswapV3MintCallback(amount0Owed, amount1Owed, _data);
  }

  function testRevertIfDeprecated(uint256 amount0Owed, uint256 amount1Owed) public {
    mockLockManager.setDeprecatedForTest(true);

    vm.expectRevert(ILockManagerGovernor.LockManager_Deprecated.selector);
    mockLockManager.uniswapV3MintCallback(amount0Owed, amount1Owed, _data);
  }

  function testIncreaseConcentratedWeth(uint256 amount0Owed, uint256 amount1Owed) public {
    uint256 concentratedWeth = mockLockManager.concentratedWeth();

    vm.prank(address(mockPool));
    mockLockManager.uniswapV3MintCallback(amount0Owed, amount1Owed, _data);

    assertEq(mockLockManager.concentratedWeth(), concentratedWeth + amount1Owed);
  }

  function testTransfer(uint256 amount0Owed, uint256 amount1Owed) public {
    vm.expectCall(address(mockWeth), abi.encodeWithSelector(IERC20.transfer.selector, address(mockPool), amount1Owed));

    vm.prank(address(mockPool));
    mockLockManager.uniswapV3MintCallback(amount0Owed, amount1Owed, _data);
  }
}

contract UnitLockManagerWithdraw is Base {
  uint256 wethBalance = initialBalance * 2;
  uint256 tokenBalance = initialBalance / 2;
  uint256 wethToAdd = 4 ether;
  uint256 tokenToAdd = 5 ether;
  address receiver = newAddress();

  function setUp() public virtual override {
    super.setUp();

    mockLockManager.setTotalLockForTest(initialBalance * 2);
    mockLockManager.setTotalToWithdraw(wethBalance, tokenBalance);

    vm.mockCall(address(mockWeth), abi.encodeWithSelector(IERC20.transfer.selector), abi.encode(true));
    vm.mockCall(address(mockToken), abi.encodeWithSelector(IERC20.transfer.selector), abi.encode(true));

    vm.mockCall(
      address(mockWeth),
      abi.encodeWithSelector(IERC20.transferFrom.selector, address(this), address(mockLockManager), wethToAdd),
      abi.encode(true)
    );

    vm.mockCall(
      address(mockToken),
      abi.encodeWithSelector(IERC20.transferFrom.selector, address(this), address(mockLockManager), tokenToAdd),
      abi.encode(true)
    );

    mockLockManager.approve(address(mockLockManager), initialBalance);
  }

  function testBurnTheCorrectAmountOfLockedWeth() public {
    mockLockManager.setWithdrawalsEnabled(true);
    mockLockManager.withdraw(receiver);
    assertEq(mockLockManager.balanceOf(address(this)), 0);
  }

  function testSendTheCorrectAmountOfTokensWithRewards() public {
    mockLockManager.addRewards(wethToAdd, tokenToAdd);

    mockLockManager.setWithdrawalsEnabled(true);

    uint256 totalWethToReceive = (wethBalance + wethToAdd) / 2;
    uint256 totalTokenToReceive = (tokenBalance + tokenToAdd) / 2;

    vm.expectCall(address(mockWeth), abi.encodeWithSelector(IERC20.transfer.selector, address(this), totalWethToReceive));
    vm.expectCall(address(mockToken), abi.encodeWithSelector(IERC20.transfer.selector, address(this), totalTokenToReceive));

    mockLockManager.withdraw(address(this));
  }

  function testSubtractCorrectlyFromTotalAndRewards() public {
    vm.expectCall(address(mockWeth), abi.encodeWithSelector(IERC20.transferFrom.selector, address(this), address(mockLockManager), wethToAdd));
    vm.expectCall(address(mockToken), abi.encodeWithSelector(IERC20.transferFrom.selector, address(this), address(mockLockManager), tokenToAdd));

    mockLockManager.addRewards(wethToAdd, tokenToAdd);
    mockLockManager.setWithdrawalsEnabled(true);
    mockLockManager.withdraw(receiver);

    (, uint256 _totalWeth, uint256 _totalToken) = mockLockManager.withdrawalData();

    assertEq(_totalWeth, wethBalance / 2);
    assertEq(_totalToken, tokenBalance / 2);

    (uint256 _wethClaimable, uint256 _tokenClaimable) = mockLockManager.claimable(address(this));
    assertEq(_wethClaimable, 0);
    assertEq(_tokenClaimable, 0);
  }

  function testSendTheCorrectAmountOfTokens() public {
    mockLockManager.setWithdrawalsEnabled(true);

    vm.expectCall(address(mockWeth), abi.encodeWithSelector(IERC20.transfer.selector, address(this), wethBalance / 2));
    vm.expectCall(address(mockToken), abi.encodeWithSelector(IERC20.transfer.selector, address(this), tokenBalance / 2));

    mockLockManager.withdraw(address(this));
  }

  function testRevertIfUserHasZeroLockedTokens() public {
    address _randomUser = newAddress();
    mockLockManager.setWithdrawalsEnabled(true);
    vm.expectRevert(ILockManager.LockManager_ZeroBalance.selector);
    vm.prank(_randomUser);
    mockLockManager.withdraw(receiver);
  }

  function testRevertIfWithdrawalsNotEnabled() public {
    vm.expectRevert(ILockManager.LockManager_WithdrawalsNotEnabled.selector);
    mockLockManager.withdraw(receiver);
  }
}

contract UnitLockManagerUnwind is Base {
  uint256 positionsCount = 5;
  uint256 positionsToUnwind = 2;

  function setUp() public virtual override {
    super.setUp();
    mockLockManager.setDeprecatedForTest(true);
  }

  function testRevertIfNotDeprecated() public {
    mockLockManager.setDeprecatedForTest(false);

    vm.expectRevert(abi.encodeWithSelector(ILockManager.LockManager_DeprecationRequired.selector));
    mockLockManager.unwind(10);
  }

  function testRevertIfPoolManipulated() public {
    _addAndMockPositions(positionsCount, 0, mockLockManager);

    vm.mockCall(address(mockPriceOracle), abi.encodeWithSignature('isManipulated(address)'), abi.encode(true));
    vm.expectRevert(abi.encodeWithSelector(ILockManager.LockManager_PoolManipulated.selector));
    mockLockManager.unwind(positionsToUnwind);
  }

  function testRevertIfNoPositions() public {
    vm.expectRevert(abi.encodeWithSelector(ILockManager.LockManager_NoPositions.selector));
    mockLockManager.unwind(10);
  }

  function testRevertIfNotEnoughPositions() public {
    vm.expectRevert(abi.encodeWithSelector(ILockManager.LockManager_NoPositions.selector));
    mockLockManager.unwind(100);
  }

  function testCallCollectIfHasLiquidity(bool _isWethToken0) public {
    setIsWethToken0ForTest(_isWethToken0);
    _addAndMockPositions(positionsCount, 10, mockLockManager);
    (int24 lowerTick3, int24 upperTick3) = _getLowerAndUpperTickForPosition(3);
    (int24 lowerTick4, int24 upperTick4) = _getLowerAndUpperTickForPosition(4);

    vm.expectCall(
      address(mockPool),
      abi.encodeWithSelector(
        IUniswapV3PoolActions.collect.selector,
        address(mockLockManager),
        lowerTick3,
        upperTick3,
        type(uint128).max,
        type(uint128).max
      )
    );

    vm.expectCall(
      address(mockPool),
      abi.encodeWithSelector(
        IUniswapV3PoolActions.collect.selector,
        address(mockLockManager),
        lowerTick4,
        upperTick4,
        type(uint128).max,
        type(uint128).max
      )
    );

    mockLockManager.unwind(positionsToUnwind);
  }

  function testCallBurnIfHasLiquidity(uint64 _liquidity, bool _isWethToken0) public {
    vm.assume(_liquidity > 0);
    setIsWethToken0ForTest(_isWethToken0);
    _addAndMockPositions(positionsCount, _liquidity, mockLockManager);

    (int24 lowerTick3, int24 upperTick3) = _getLowerAndUpperTickForPosition(3);
    (int24 lowerTick4, int24 upperTick4) = _getLowerAndUpperTickForPosition(4);

    vm.expectCall(address(mockPool), abi.encodeWithSelector(IUniswapV3PoolActions.burn.selector, lowerTick4, upperTick4, _liquidity));
    vm.expectCall(address(mockPool), abi.encodeWithSelector(IUniswapV3PoolActions.burn.selector, lowerTick3, upperTick3, _liquidity));

    mockLockManager.unwind(positionsToUnwind);
  }

  function testAddToTotalWethAndToken(uint64 _liquidity) public {
    _addAndMockPositions(positionsCount, _liquidity, mockLockManager);
    mockLockManager.unwind(positionsToUnwind);
    uint256 totalWethBurn;
    uint256 totalTokenBurn;

    for (uint256 positionIndex = 1; positionIndex <= positionsToUnwind; positionIndex++) {
      (int24 lowerTick, int24 upperTick) = _getLowerAndUpperTickForPosition(positionsCount - positionIndex);
      (, , uint256 wethBurn, uint256 tokenBurn, , ) = mockLockManager.liquidityAmountsForTest(lowerTick, upperTick, _liquidity);
      totalWethBurn += wethBurn;
      totalTokenBurn += tokenBurn;
    }

    (bool withdrawalsEnabled, uint256 totalWeth, uint256 totalToken) = mockLockManager.withdrawalData();
    assertFalse(withdrawalsEnabled);
    assertEq(totalWeth, totalWethBurn);
    assertEq(totalToken, totalTokenBurn);
  }

  function testNoLiquidityOnPositions(bool _isWethToken0) public {
    setIsWethToken0ForTest(_isWethToken0);
    uint128 _liquidity = 0;
    _addAndMockPositions(positionsCount, _liquidity, mockLockManager);
    mockLockManager.unwind(positionsToUnwind);
    (bool withdrawalsEnabled, uint256 totalWeth, uint256 totalToken) = mockLockManager.withdrawalData();
    assertFalse(withdrawalsEnabled);
    assertEq(totalWeth, 0);
    assertEq(totalToken, 0);
  }

  function testDeletePositions(uint64 _liquidity, bool _isWethToken0) public {
    setIsWethToken0ForTest(_isWethToken0);
    _addAndMockPositions(positionsCount, _liquidity, mockLockManager);
    mockLockManager.unwind(positionsToUnwind);
    assertEq(mockLockManager.getPositionsCount(), positionsCount - positionsToUnwind);
  }

  function testRemovePositionLiquidity(uint64 _liquidity, bool _isWethToken0) public {
    setIsWethToken0ForTest(_isWethToken0);
    _addAndMockPositions(positionsCount, _liquidity, mockLockManager);
    mockLockManager.unwind(positionsToUnwind);

    (int24 lowerTick, int24 upperTick) = _getLowerAndUpperTickForPosition(4);
    uint128 liquidityOnPosition = mockLockManager.getPositionLiquidityForTest(lowerTick, upperTick);
    assertEq(liquidityOnPosition, 0);
  }

  function testAllPositionsSetWithdrawalsEnabled(uint64 _liquidity, bool _isWethToken0) public {
    setIsWethToken0ForTest(_isWethToken0);
    _addAndMockPositions(positionsCount, _liquidity, mockLockManager);
    mockLockManager.unwind(positionsCount);

    (bool withdrawalsEnabled, , ) = mockLockManager.withdrawalData();

    assertEq(mockLockManager.getPositionsCount(), 0);
    assertTrue(withdrawalsEnabled);
  }
}

contract UnitLockManagerTransfer is Base {
  function testRevertIfTransferToSameAddress(uint256 _amount) public {
    vm.expectRevert(ILockManager.LockManager_InvalidAddress.selector);
    mockLockManager.transfer(address(this), _amount);
  }
}

contract UnitLockManagerTransferFrom is Base {
  function testRevertIfTransferToSameAddress(uint256 _amount) public {
    vm.expectRevert(ILockManager.LockManager_InvalidAddress.selector);
    mockLockManager.transferFrom(address(this), address(this), _amount);
  }
}
