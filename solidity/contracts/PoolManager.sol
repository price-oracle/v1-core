// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.4 <0.9.0;

import 'uni-v3-core/libraries/TickMath.sol';
import 'uni-v3-core/interfaces/IUniswapV3Factory.sol';
import 'uni-v3-periphery/libraries/LiquidityAmounts.sol';
import '@contracts/utils/PRBMath.sol';
import 'isolmate/utils/SafeTransferLib.sol';

import '@interfaces/IPoolManager.sol';
import '@interfaces/jobs/IFeeCollectorJob.sol';

import '@contracts/PoolManagerGovernor.sol';
import '@contracts/utils/GasCheckLib.sol';
import '@contracts/utils/PriceLib.sol';

contract PoolManager is IPoolManager, PoolManagerGovernor {
  using SafeTransferLib for IERC20;

  /**
    @notice UniswapV3's maximum tick
    @dev    Due to tick spacing, pools with different fees may have differences between _MAX_TICK and tickUpper.
            Use tickUpper to find the max tick of the pool
   */
  int24 internal constant _MAX_TICK = 887272;

  /// @inheritdoc IPoolManager
  mapping(address => SeederRewards) public seederRewards;

  /// @inheritdoc IPoolManager
  PoolRewards public poolRewards;

  /// @inheritdoc IPoolManager
  ILockManager public lockManager;

  /// @inheritdoc IPoolManager
  ILockManager[] public deprecatedLockManagers;

  /// @inheritdoc IPoolManager
  IERC20 public immutable WETH;

  /// @inheritdoc IPoolManager
  IUniswapV3Factory public immutable UNISWAP_V3_FACTORY;

  /// @inheritdoc IPoolManager
  bytes32 public immutable POOL_BYTECODE_HASH;

  /// @inheritdoc IPoolManager
  IERC20 public immutable TOKEN;

  /// @inheritdoc IPoolManager
  IUniswapV3Pool public immutable POOL;

  /// @inheritdoc IPoolManager
  uint24 public immutable FEE;

  /// @inheritdoc IPoolManager
  bool public immutable IS_WETH_TOKEN0;

  /**
    @notice The sorted token0
   */
  address internal immutable _TOKEN0;

  /**
    @notice The sorted token1
   */
  address internal immutable _TOKEN1;

  /**
    @notice The max tick of the pool
   */
  int24 internal immutable _TICK_UPPER;

  /**
    @notice The min tick of the pool
   */
  int24 internal immutable _TICK_LOWER;

  /**
    @notice The amount of WETH added to the full range
   */
  uint256 internal _amountWeth;

  /**
    @notice The amount of non-WETH tokens added to the full-range position
   */
  uint256 internal _amountToken;

  /**
    @notice The total amount of liquidity burned by seeders
   */
  uint256 internal _burnedBalance;

  /**
    @notice The starting cardinality with which a pool begins
   */
  uint16 internal constant _STARTING_CARDINALITY = 64;

  /**
    @notice The percentage of the slippage allowed when increasing full-range
   */
  uint256 internal constant _SLIPPAGE_PERCENTAGE = 2_000;

  /**
    @notice The percentage of the fees to be distributed to maintain the pool
   */
  uint256 internal constant _TAX_PERCENTAGE = 50_000;

  /**
    @notice The fixed point precision of the distribution ratios
   */
  uint256 internal constant _DISTRIBUTION_BASE = 100_000;

  /**
    @notice Base to avoid over/underflow
   */
  uint256 internal constant _BASE = 1 ether;

  /**
    @dev payable constructor does not waste gas on checking msg.value
   */
  constructor() payable PoolManagerGovernor() {
    IPoolManagerFactory _factory = POOL_MANAGER_FACTORY;
    uint160 _sqrtPriceX96;
    address _owner;

    (UNISWAP_V3_FACTORY, POOL_BYTECODE_HASH, WETH, TOKEN, , , _owner, FEE, _sqrtPriceX96) = _factory.constructorArguments();
    IS_WETH_TOKEN0 = address(WETH) < address(TOKEN);
    (_TOKEN0, _TOKEN1) = IS_WETH_TOKEN0 ? (address(TOKEN), address(WETH)) : (address(WETH), address(TOKEN));
    (POOL, ) = PriceLib._calculateTheoreticalAddress(WETH, TOKEN, FEE, UNISWAP_V3_FACTORY, POOL_BYTECODE_HASH);

    // initialize the pool if not yet done
    address _existingPool = address(UNISWAP_V3_FACTORY.getPool(address(WETH), address(TOKEN), FEE));
    if (_existingPool == address(0)) {
      _createAndInitializePool(_sqrtPriceX96);
    } else {
      _initializePoolIfNeeded(_sqrtPriceX96);
    }

    _TICK_UPPER = _MAX_TICK - (_MAX_TICK % POOL.tickSpacing());
    _TICK_LOWER = -_TICK_UPPER;

    LockManagerParams memory _lockManagerParams = LockManagerParams({
      factory: _factory,
      strategy: _factory.strategy(),
      pool: POOL,
      fee: FEE,
      token: TOKEN,
      weth: WETH,
      isWethToken0: IS_WETH_TOKEN0,
      governance: _owner,
      index: 0
    });
    lockManager = _factory.lockManagerFactory().createLockManager(_lockManagerParams);
  }

  /// @inheritdoc IPoolManager
  function claimable(address _account) external view returns (uint256 _wethClaimable, uint256 _tokenClaimable) {
    (_wethClaimable, _tokenClaimable) = _claimable(_account);
  }

  /// @inheritdoc IPoolManager
  function claimRewards(address _to) external returns (uint256 _rewardWeth, uint256 _rewardToken) {
    if (_to == address(0)) revert PoolManager_ZeroAddress();

    address _account = msg.sender;
    (_rewardWeth, _rewardToken) = _claimable(_account);

    if (_rewardWeth == 0 && _rewardToken == 0) revert PoolManager_NoRewardsToClaim();

    (uint256 _wethPerSeededLiquidity, uint256 _tokenPerSeededLiquidity) = (
      poolRewards.wethPerSeededLiquidity,
      poolRewards.tokenPerSeededLiquidity
    );

    seederRewards[_account] = SeederRewards({
      wethAvailable: 0,
      tokenAvailable: 0,
      wethPaid: _wethPerSeededLiquidity,
      tokenPaid: _tokenPerSeededLiquidity
    });

    if (_rewardWeth > 0) {
      WETH.safeTransfer(_to, _rewardWeth);
    }

    if (_rewardToken > 0) {
      TOKEN.safeTransfer(_to, _rewardToken);
    }
    emit ClaimedRewards(msg.sender, _to, _rewardWeth, _rewardToken);
  }

  /// @inheritdoc IPoolManager
  function burn(uint256 _liquidity) external {
    if (_liquidity == 0) revert PoolManager_ZeroAmount();
    _updateReward(msg.sender);
    seederBalance[msg.sender] -= _liquidity;
    seederBurned[msg.sender] += _liquidity;
    _burnedBalance += _liquidity;
    emit SeederLiquidityBurned(_liquidity);
  }

  /// @inheritdoc IPoolManager
  function deprecateLockManager() external {
    ILockManager _oldLockManager = lockManager;
    (bool _withdrawalsEnabled, , ) = _oldLockManager.withdrawalData();

    if (!_withdrawalsEnabled) revert PoolManager_ActiveLockManager();

    deprecatedLockManagers.push(_oldLockManager);

    LockManagerParams memory _lockManagerParams = LockManagerParams({
      factory: POOL_MANAGER_FACTORY,
      strategy: POOL_MANAGER_FACTORY.strategy(),
      pool: POOL,
      fee: FEE,
      token: TOKEN,
      weth: WETH,
      isWethToken0: IS_WETH_TOKEN0,
      governance: POOL_MANAGER_FACTORY.owner(),
      index: deprecatedLockManagers.length
    });

    ILockManager _newLockManager = POOL_MANAGER_FACTORY.lockManagerFactory().createLockManager(_lockManagerParams);
    lockManager = _newLockManager;

    emit LockManagerDeprecated(_oldLockManager, _newLockManager);
  }

  /// @inheritdoc IPoolManager
  function increaseFullRangePosition(
    address _donor,
    uint128 _liquidity,
    uint160 _sqrtPriceX96
  ) public {
    IPoolManagerFactory _factory = POOL_MANAGER_FACTORY;
    if (IPoolManagerFactory(msg.sender) != _factory && _donor != msg.sender) revert PoolManager_OnlyFactory();

    (uint256 _sqrtPriceX96Pool, , , , , , ) = POOL.slot0();
    uint256 _currentSlippage = PRBMath.mulDiv(_sqrtPriceX96Pool, _SLIPPAGE_PERCENTAGE, _DISTRIBUTION_BASE);
    if (_sqrtPriceX96 > _sqrtPriceX96Pool + _currentSlippage || _sqrtPriceX96 < _sqrtPriceX96Pool - _currentSlippage)
      revert PoolManager_PoolManipulated();

    _mintLiquidityForFullRange(_donor, _liquidity);
    _updateReward(_donor);
    seederBalance[_donor] += _liquidity;
    delete _amountWeth;
    delete _amountToken;
  }

  /// @inheritdoc IPoolManager
  function increaseFullRangePosition(uint256 _wethAmount, uint256 _tokenAmount) external returns (uint256 __amountWeth, uint256 __amountToken) {
    if (priceOracle.isManipulated(POOL)) revert PoolManager_PoolManipulated();
    feeManager.increaseFullRangePosition(POOL, TOKEN, _wethAmount, _tokenAmount, IS_WETH_TOKEN0);
    __amountWeth = _amountWeth;
    __amountToken = _amountToken;
    delete _amountWeth;
    delete _amountToken;
  }

  /// @inheritdoc IPoolManager
  function mintLiquidityForFullRange(uint256 _wethAmount, uint256 _tokenAmount) external {
    IFeeManager _feeManager = IFeeManager(msg.sender);
    if (_feeManager != feeManager) revert PoolManager_InvalidFeeManager();

    (uint160 _sqrtPriceX96, , , , , , ) = POOL.slot0();
    uint128 _liquidity = LiquidityAmounts.getLiquidityForAmounts(
      _sqrtPriceX96,
      TickMath.getSqrtRatioAtTick(_TICK_LOWER),
      TickMath.getSqrtRatioAtTick(_TICK_UPPER),
      IS_WETH_TOKEN0 ? _wethAmount : _tokenAmount,
      IS_WETH_TOKEN0 ? _tokenAmount : _wethAmount
    );

    _mintLiquidityForFullRange(msg.sender, _liquidity);
  }

  /// @inheritdoc IPoolManager
  function uniswapV3MintCallback(
    uint256 _amount0Owed,
    uint256 _amount1Owed,
    bytes calldata _data
  ) external {
    if (msg.sender != address(POOL)) revert PoolManager_OnlyPool();
    address _donor = abi.decode(_data, (address));

    (_amountWeth, _amountToken) = IS_WETH_TOKEN0 ? (_amount0Owed, _amount1Owed) : (_amount1Owed, _amount0Owed);

    if (_donor == address(feeManager)) {
      // increaseFullRangePosition triggered by LiquidityIncreaserJob
      feeManager.fullRangeCallback(POOL, TOKEN, _amountWeth, _amountToken);
    } else {
      // increaseFullRangePosition triggered by the factory, should transferFrom WETH and non-WETH token from the donor
      if (_amountWeth > 0) WETH.safeTransferFrom(_donor, address(POOL), _amountWeth);
      if (_amountToken > 0) TOKEN.safeTransferFrom(_donor, address(POOL), _amountToken);
    }
  }

  /**
    @notice Creates a new pool and then initializes and increases the cardinality
    @param  _sqrtPriceX96 The initial square root price of the pool as a Q64.96 value
   */
  function _createAndInitializePool(uint160 _sqrtPriceX96) internal {
    IUniswapV3Pool _pool = IUniswapV3Pool(UNISWAP_V3_FACTORY.createPool(_TOKEN0, _TOKEN1, FEE));
    _pool.initialize(_sqrtPriceX96);
    _pool.increaseObservationCardinalityNext(_STARTING_CARDINALITY);
  }

  /**
    @notice Initializes the pool if it hasn't been initialized before
    @param  _sqrtPriceX96 The initial square root price of the pool as a Q64.96 value
   */
  function _initializePoolIfNeeded(uint160 _sqrtPriceX96) internal {
    (uint160 _sqrtPriceX96Existing, , , , uint16 _observationCardinalityNext, , ) = POOL.slot0();
    if (_sqrtPriceX96Existing == 0) {
      POOL.initialize(_sqrtPriceX96);
    }
    if (_STARTING_CARDINALITY > _observationCardinalityNext) {
      POOL.increaseObservationCardinalityNext(_STARTING_CARDINALITY);
    }
  }

  /**
    @notice Adds liquidity to the full-range position
    @dev    Will trigger UniswapV3MintCallback on the PoolManager
    @param  _donor The address of the liquidity provider
    @param  _liquidity The amount of liquidity to add
   */
  function _mintLiquidityForFullRange(address _donor, uint128 _liquidity) internal {
    POOL.mint(address(this), _TICK_LOWER, _TICK_UPPER, _liquidity, abi.encode(_donor));
    poolLiquidity = poolLiquidity + _liquidity;
  }

  // ********** FEES ***********
  /// @inheritdoc IPoolManager
  function burn1() external {
    if (msg.sender != address(priceOracle)) revert PoolManager_InvalidPriceOracle();
    POOL.burn(_TICK_LOWER, _TICK_UPPER, 1);
  }

  /// @inheritdoc IPoolManager
  function collectFees() external {
    IUniswapV3Pool _pool = POOL;
    IFeeCollectorJob _feeCollectorJob = POOL_MANAGER_FACTORY.feeCollectorJob();
    uint256 _amount0;
    uint256 _amount1;

    if (address(_feeCollectorJob) == msg.sender) {
      (_amount0, _amount1) = GasCheckLib.collectFromFullRangePosition(
        _pool,
        priceOracle,
        _feeCollectorJob.collectMultiplier(),
        _TICK_LOWER,
        _TICK_UPPER,
        IS_WETH_TOKEN0
      );
    } else {
      _pool.burn(_TICK_LOWER, _TICK_UPPER, 0);
      (_amount0, _amount1) = _pool.collect(address(this), _TICK_LOWER, _TICK_UPPER, type(uint128).max, type(uint128).max);
    }
    if (_amount0 > 0 || _amount1 > 0) {
      _feesDistribution(_amount0, _amount1);
    }
  }

  /**
    @notice Calculates the amount of token and WETH to be allocated to the fee manager
    @param  _totalToken0 The amount of token0 fees
    @param  _totalToken1 The amount of token1 fees
   */
  function _feesDistribution(uint256 _totalToken0, uint256 _totalToken1) internal {
    IFeeManager _feeManager = feeManager;
    // Calculates the tax amounts
    (uint256 _totalWeth, uint256 _totalToken) = IS_WETH_TOKEN0 ? (_totalToken0, _totalToken1) : (_totalToken1, _totalToken0);

    uint256 _donatedWeth = PRBMath.mulDiv(_totalWeth, _burnedBalance, poolLiquidity);
    uint256 _donatedToken = PRBMath.mulDiv(_totalToken, _burnedBalance, poolLiquidity);

    uint256 _taxWeth = PRBMath.mulDiv(_totalWeth - _donatedWeth, _TAX_PERCENTAGE, _DISTRIBUTION_BASE);
    uint256 _taxToken = PRBMath.mulDiv(_totalToken - _donatedToken, _TAX_PERCENTAGE, _DISTRIBUTION_BASE);

    _addRewards(_totalWeth - _taxWeth - _donatedWeth, _totalToken - _taxToken - _donatedToken);

    /*
      Transfers the taxes to the fee manager. Important to transfer first and then call `depositFromPoolManager`.
      Otherwise, there won't be enough balance in FeeManager to pay for maintenance and cardinality
     */
    uint256 _wethFees = _taxWeth + _donatedWeth;
    uint256 _tokenFees = _taxToken + _donatedToken;

    WETH.safeTransfer(address(_feeManager), _wethFees);
    IERC20(TOKEN).safeTransfer(address(_feeManager), _tokenFees);
    _feeManager.depositFromPoolManager(_wethFees, _tokenFees);

    emit FeesCollected(_totalWeth, _totalToken);
  }

  /**
    @notice Accounts for rewards to seeders
    @param  _wethAmount The amount of WETH added as rewards
    @param  _tokenAmount The amount of non-WETH token added as rewards
   */
  function _addRewards(uint256 _wethAmount, uint256 _tokenAmount) internal {
    if (_wethAmount == 0 && _tokenAmount == 0) revert PoolManager_ZeroAmount();

    poolRewards = PoolRewards({
      wethPerSeededLiquidity: poolRewards.wethPerSeededLiquidity + PRBMath.mulDiv(_wethAmount, _BASE, poolLiquidity),
      tokenPerSeededLiquidity: poolRewards.tokenPerSeededLiquidity + PRBMath.mulDiv(_tokenAmount, _BASE, poolLiquidity)
    });

    emit RewardsAdded(_wethAmount, _tokenAmount);
  }

  /**
    @notice Updates the pool manager rewards for a given seeder
    @param  _account The address of the seeder
   */
  function _updateReward(address _account) internal {
    (uint256 _wethPerSeededLiquidity, uint256 _tokenPerSeededLiquidity) = (
      poolRewards.wethPerSeededLiquidity,
      poolRewards.tokenPerSeededLiquidity
    );
    uint256 _userBalance = seederBalance[_account];

    SeederRewards memory _seederRewards = seederRewards[_account];

    _seederRewards.wethAvailable += PRBMath.mulDiv(_userBalance, _wethPerSeededLiquidity - _seederRewards.wethPaid, _BASE);
    _seederRewards.tokenAvailable += PRBMath.mulDiv(_userBalance, _tokenPerSeededLiquidity - _seederRewards.tokenPaid, _BASE);
    _seederRewards.wethPaid = _wethPerSeededLiquidity;
    _seederRewards.tokenPaid = _tokenPerSeededLiquidity;

    seederRewards[_account] = _seederRewards;
  }

  /**
    @notice Returns the amounts of WETH and non-WETH token rewards that the user can claim from a pool manager
    @param  _account The address of the user
    @return _wethClaimable The amount of WETH rewards the user can claim
    @return _tokenClaimable The amount of non-WETH token rewards the user can claim
   */
  function _claimable(address _account) internal view returns (uint256 _wethClaimable, uint256 _tokenClaimable) {
    (uint256 _wethPerSeededLiquidity, uint256 _tokenPerSeededLiquidity) = (
      poolRewards.wethPerSeededLiquidity,
      poolRewards.tokenPerSeededLiquidity
    );
    uint256 _userBalance = seederBalance[_account];

    SeederRewards memory _seederRewards = seederRewards[_account];

    uint256 _claimWethShare = PRBMath.mulDiv(_userBalance, _wethPerSeededLiquidity - _seederRewards.wethPaid, _BASE);
    uint256 _claimTokenShare = PRBMath.mulDiv(_userBalance, _tokenPerSeededLiquidity - _seederRewards.tokenPaid, _BASE);

    _wethClaimable = _claimWethShare + _seederRewards.wethAvailable;
    _tokenClaimable = _claimTokenShare + _seederRewards.tokenAvailable;
  }
}
