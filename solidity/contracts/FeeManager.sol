// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.4 <0.9.0;

import 'uni-v3-core/libraries/TickMath.sol';
import 'isolmate/utils/FixedPointMathLib.sol';
import 'isolmate/utils/SafeTransferLib.sol';
import 'solidity-utils/contracts/Roles.sol';

import '@interfaces/IFeeManager.sol';

contract FeeManager is IFeeManager, Roles {
  using SafeTransferLib for IERC20;

  /// @inheritdoc IFeeManager
  IERC20 public immutable WETH;
  /// @inheritdoc IFeeManager
  IPoolManagerFactory public immutable POOL_MANAGER_FACTORY;
  /// @inheritdoc IFeeManager
  mapping(IPoolManager => FeeStore) public poolManagerDeposits;
  /// @inheritdoc IFeeManager
  mapping(IPoolManager => PoolCardinality) public poolCardinality;
  /// @inheritdoc IFeeManager
  mapping(IPoolManager => PoolDistributionFees) public poolDistribution;
  /// @inheritdoc IFeeManager
  ICardinalityJob public cardinalityJob;
  /// @inheritdoc IFeeManager
  uint256 public swapGasCostMultiplier;
  /// @inheritdoc IFeeManager
  uint16 public poolCardinalityMax = uint16(65535) / 100;
  /// @inheritdoc IFeeManager
  address public maintenanceGovernance;
  /**
    @notice The fixed point precision of the distribution ratios
   */
  uint256 internal constant _DISTRIBUTION_BASE = 100_000;
  /**
    @notice The percentage of the distribution for maintenance
   */
  uint256 internal constant _WETH_FOR_MAINTENANCE = 40_000;
  /**
    @notice The percentage of the distribution for cardinality
   */
  uint256 internal constant _WETH_FOR_CARDINALITY = 20_000;
  /**
    @notice The max percentage that has to be set for maintenance
   */
  uint256 internal constant _MAX_WETH_MAINTENANCE_THRESHOLD = 60_000;
  /**
    @notice The cost of gas when executing a swap
   */
  uint256 internal constant _SWAP_COST = 200_000;

  constructor(
    IPoolManagerFactory _poolManagerFactory,
    address _admin,
    IERC20 _weth
  ) payable {
    _grantRole(DEFAULT_ADMIN_ROLE, _admin);
    POOL_MANAGER_FACTORY = _poolManagerFactory;
    WETH = _weth;
    maintenanceGovernance = _admin;
    swapGasCostMultiplier = 1;
  }

  /// @inheritdoc IFeeManager
  function migrateTo(IFeeManager _newFeeManager) external {
    IPoolManager _poolManager = IPoolManager(msg.sender);
    if (!POOL_MANAGER_FACTORY.isChild(_poolManager)) revert FeeManager_InvalidPoolManager(_poolManager);

    PoolCardinality memory _poolCardinality = poolCardinality[_poolManager];
    delete poolCardinality[_poolManager];

    FeeStore memory _poolManagerDeposits = poolManagerDeposits[_poolManager];
    delete poolManagerDeposits[_poolManager];

    PoolDistributionFees memory _poolDistributionFees = poolDistribution[_poolManager];
    delete poolDistribution[_poolManager];

    _newFeeManager.migrateFrom(_poolManager, _poolCardinality, _poolManagerDeposits, _poolDistributionFees);
    WETH.safeTransfer(address(_newFeeManager), _poolManagerDeposits.wethForFullRange);
    _poolManager.TOKEN().safeTransfer(address(_newFeeManager), _poolManagerDeposits.tokenForFullRange);

    emit Migrated(msg.sender, address(this), address(_newFeeManager));
  }

  /// @inheritdoc IFeeManager
  function migrateFrom(
    IPoolManager _poolManager,
    PoolCardinality calldata _poolCardinality,
    FeeStore calldata _poolManagerDeposits,
    PoolDistributionFees calldata _poolDistributionFees
  ) external {
    IFeeManager _oldFeeManager = IFeeManager(msg.sender);

    if (!POOL_MANAGER_FACTORY.isChild(_poolManager)) revert FeeManager_InvalidPoolManager(_poolManager);
    if (_oldFeeManager != _poolManager.feeManager()) revert FeeManager_InvalidOldFeeManager(_oldFeeManager);

    if (poolCardinality[_poolManager].weth > 0) revert FeeManager_NonZeroCardinality();
    poolCardinality[_poolManager] = _poolCardinality;

    FeeStore memory _poolDeposits = poolManagerDeposits[_poolManager];

    if (_poolDeposits.wethForFullRange + _poolDeposits.tokenForFullRange > 0) revert FeeManager_NonZeroPoolDeposits();
    poolManagerDeposits[_poolManager] = _poolManagerDeposits;

    if (poolDistribution[_poolManager].isInitialized) revert FeeManager_InitializedPoolDistribution();
    poolDistribution[_poolManager] = _poolDistributionFees;
  }

  /// @inheritdoc IFeeManager
  function depositFromPoolManager(uint256 _wethFees, uint256 _tokenFees) external {
    IPoolManager _poolManager = IPoolManager(msg.sender);
    if (!POOL_MANAGER_FACTORY.isChild(_poolManager)) revert FeeManager_InvalidPoolManager(_poolManager);
    _deposit(_wethFees, _tokenFees, _poolManager);
  }

  /// @inheritdoc IFeeManager
  function depositFromLockManager(uint256 _wethFees, uint256 _tokenFees) external {
    IPoolManager _poolManager = _checkPoolManagerValidityFromLockManager(ILockManager(msg.sender));
    _deposit(_wethFees, _tokenFees, _poolManager);
  }

  /**
    @notice Updates the record for fees collected
    @dev    Splits the deposited fees into parts for different purposes
    @dev    The fees from concentrated and full-range positions are handled differently
    @param  _wethFees The total amount of WETH fees collected from the pool
    @param  _tokenFees The total amount of non-WETH token fees collected from the pool
   */
  function _deposit(
    uint256 _wethFees,
    uint256 _tokenFees,
    IPoolManager _poolManager
  ) internal {
    PoolDistributionFees memory _poolDistributionFees = poolDistribution[_poolManager];

    if (!_poolDistributionFees.isInitialized) {
      _poolDistributionFees = PoolDistributionFees({
        wethForMaintenance: _WETH_FOR_MAINTENANCE,
        wethForCardinality: _WETH_FOR_CARDINALITY,
        isInitialized: true
      });

      poolDistribution[_poolManager] = _poolDistributionFees;
    }

    uint256 _wethForMaintenance = (_wethFees * _poolDistributionFees.wethForMaintenance) / _DISTRIBUTION_BASE;
    uint256 _wethForCardinality;

    // Assigns _wethForMaintenance to pool cardinality job buffer
    PoolCardinality memory _poolCardinality = poolCardinality[_poolManager];
    if (
      (_poolCardinality.customMax > 0 && _poolCardinality.customMax > _poolCardinality.currentMax) ||
      poolCardinalityMax > _poolCardinality.currentMax
    ) {
      _wethForCardinality = (_wethFees * _poolDistributionFees.wethForCardinality) / _DISTRIBUTION_BASE;
      _poolCardinality.weth += _wethForCardinality;
      poolCardinality[_poolManager] = _poolCardinality;
      _wethFees -= _wethForCardinality;
    }

    _wethFees -= _wethForMaintenance;

    {
      FeeStore memory _feeStore = poolManagerDeposits[_poolManager];
      _feeStore.wethForFullRange += _wethFees;
      _feeStore.tokenForFullRange += _tokenFees;
      poolManagerDeposits[_poolManager] = _feeStore;
    }

    WETH.safeTransfer(maintenanceGovernance, _wethForMaintenance + _wethForCardinality);
    emit FeesDeposited(_poolManager, _wethFees, _tokenFees, _wethForMaintenance, _wethForCardinality);
  }

  /// @inheritdoc IFeeManager
  function increaseFullRangePosition(
    IUniswapV3Pool _pool,
    IERC20 _token,
    uint256 _neededWeth,
    uint256 _neededToken,
    bool _isWethToken0
  ) external {
    IPoolManager _poolManager = IPoolManager(msg.sender);
    if (!POOL_MANAGER_FACTORY.isChild(_poolManager)) revert FeeManager_InvalidPoolManager(_poolManager);

    FeeStore memory _poolManagerFee = poolManagerDeposits[_poolManager];

    // Sets initial balances of WETH and token
    uint256 _balanceWeth = _poolManagerFee.wethForFullRange;
    uint256 _balanceToken = _poolManagerFee.tokenForFullRange;

    if (_neededToken > _balanceToken) revert FeeManager_InvalidTokenLiquidity();

    // Sell non-WETH token to buy some WETH
    if (_neededWeth > _balanceWeth) {
      uint256 _wethToBuy = _neededWeth - _balanceWeth;

      // Check that the swapped amount is greater than the gas spent on the swap
      if (_wethToBuy < swapGasCostMultiplier * _SWAP_COST * block.basefee) revert FeeManager_SmallSwap();

      bytes memory _data = abi.encode(_pool, _isWethToken0, _token);

      uint160 _sqrtPriceLimitX96 = _isWethToken0 ? TickMath.MAX_SQRT_RATIO - 1 : TickMath.MIN_SQRT_RATIO + 1;

      // Swap non-WETH tokens to get WETH
      (int256 _amount0, int256 _amount1) = _pool.swap(address(this), !_isWethToken0, -int256(_wethToBuy), _sqrtPriceLimitX96, _data);

      _balanceWeth = _neededWeth;
      _balanceToken -= uint256(_isWethToken0 ? _amount1 : _amount0);
    }

    poolManagerDeposits[_poolManager] = FeeStore(_balanceWeth, _balanceToken);
    _poolManager.mintLiquidityForFullRange(_neededWeth, _neededToken);
  }

  /// @inheritdoc IFeeManager
  function fullRangeCallback(
    IUniswapV3Pool _pool,
    IERC20 _token,
    uint256 _neededWeth,
    uint256 _neededToken
  ) external {
    IPoolManager _poolManager = IPoolManager(msg.sender);
    if (!POOL_MANAGER_FACTORY.isChild(_poolManager)) revert FeeManager_InvalidPoolManager(_poolManager);

    FeeStore memory _poolManagerFee = poolManagerDeposits[_poolManager];
    uint256 _balanceWeth = _poolManagerFee.wethForFullRange;
    uint256 _balanceToken = _poolManagerFee.tokenForFullRange;

    // WETH and non-WETH token balances are updated
    _balanceWeth -= _neededWeth;
    _balanceToken -= _neededToken;

    if (_balanceWeth > _poolManagerFee.wethForFullRange / 100 || _balanceToken > _poolManagerFee.tokenForFullRange / 100)
      revert FeeManager_ExcessiveLiquidityLeft();

    poolManagerDeposits[_poolManager] = FeeStore(_balanceWeth, _balanceToken);

    WETH.safeTransfer(address(_pool), _neededWeth);
    _token.safeTransfer(address(_pool), _neededToken);
  }

  /// @inheritdoc IFeeManager
  function uniswapV3SwapCallback(
    int256 _amount0Delta,
    int256 _amount1Delta,
    bytes calldata _data
  ) external {
    (address _poolAddress, bool _isWethToken0, IERC20 _token) = abi.decode(_data, (address, bool, IERC20));
    if (!POOL_MANAGER_FACTORY.isSupportedPool(IUniswapV3Pool(_poolAddress))) revert FeeManager_InvalidUniswapPool(_poolAddress);
    _token.safeTransfer(_poolAddress, uint256(_isWethToken0 ? _amount1Delta : _amount0Delta));
  }

  /// @inheritdoc IFeeManager
  function increaseCardinality(
    IPoolManager _poolManager,
    uint256 _weth,
    uint16 _cardinality
  ) external {
    if (ICardinalityJob(msg.sender) != cardinalityJob) revert FeeManager_NotCardinalityJob();
    PoolCardinality memory _poolCardinality = poolCardinality[_poolManager];
    uint256 _maxCardinality = getMaxCardinalityForPool(_poolManager);
    if (_maxCardinality < _cardinality) revert FeeManager_CardinalityExceeded();
    if (_maxCardinality == _cardinality) _poolCardinality.currentMax = _cardinality;

    _poolCardinality.weth -= _weth;
    poolCardinality[_poolManager] = _poolCardinality;
  }

  /// @inheritdoc IFeeManager
  function getMaxCardinalityForPool(IPoolManager _poolManager) public view returns (uint256 _maxCardinality) {
    PoolCardinality memory _poolCardinality = poolCardinality[_poolManager];
    _maxCardinality = (poolCardinalityMax > _poolCardinality.customMax) ? poolCardinalityMax : _poolCardinality.customMax;
  }

  /// @inheritdoc IFeeManager
  function setSwapGasCostMultiplier(uint256 _swapGasCostMultiplier) external onlyRole(DEFAULT_ADMIN_ROLE) {
    swapGasCostMultiplier = _swapGasCostMultiplier;
    emit SwapGasCostMultiplierChanged(_swapGasCostMultiplier);
  }

  /// @inheritdoc IFeeManager
  function setPoolCardinalityMax(uint16 _poolCardinalityMax) external onlyRole(DEFAULT_ADMIN_ROLE) {
    poolCardinalityMax = _poolCardinalityMax;
  }

  /// @inheritdoc IFeeManager
  function setPoolCardinalityTarget(IPoolManager _poolManager, uint16 _cardinality) external onlyRole(DEFAULT_ADMIN_ROLE) {
    poolCardinality[_poolManager].customMax = _cardinality;
  }

  /// @inheritdoc IFeeManager
  function setCardinalityJob(ICardinalityJob _cardinalityJob) external onlyRole(DEFAULT_ADMIN_ROLE) {
    cardinalityJob = _cardinalityJob;

    emit CardinalityJobSet(_cardinalityJob);
  }

  /// @inheritdoc IFeeManager
  function setMaintenanceGovernance(address _maintenanceGovernance) external onlyRole(DEFAULT_ADMIN_ROLE) {
    maintenanceGovernance = _maintenanceGovernance;

    emit MaintenanceGovernanceChanged(_maintenanceGovernance);
  }

  /// @inheritdoc IFeeManager
  function setWethForMaintenance(IPoolManager _poolManager, uint256 _wethForMaintenance) external onlyRole(DEFAULT_ADMIN_ROLE) {
    PoolDistributionFees memory _poolDistributionFees = poolDistribution[_poolManager];
    if (_wethForMaintenance + _poolDistributionFees.wethForCardinality > _MAX_WETH_MAINTENANCE_THRESHOLD)
      revert FeeManager_WethForMaintenanceExceeded();
    _poolDistributionFees.wethForMaintenance = _wethForMaintenance;
    poolDistribution[_poolManager] = _poolDistributionFees;

    emit WethForMaintenanceChanged(_wethForMaintenance);
  }

  /// @inheritdoc IFeeManager
  function setWethForCardinality(IPoolManager _poolManager, uint256 _wethForCardinality) external onlyRole(DEFAULT_ADMIN_ROLE) {
    PoolDistributionFees memory _poolDistributionFees = poolDistribution[_poolManager];

    if (_poolDistributionFees.wethForMaintenance + _wethForCardinality > _MAX_WETH_MAINTENANCE_THRESHOLD)
      revert FeeManager_WethForCardinalityExceeded();
    _poolDistributionFees.wethForCardinality = _wethForCardinality;
    poolDistribution[_poolManager] = _poolDistributionFees;

    emit WethForCardinalityChanged(_wethForCardinality);
  }

  /**
    @notice Checks the validity of a pool manager and lock manager combo
    @dev    Fetching the lock manager from the pool manager is necessary to ensure the function
              wasn't called from a malicious contract returning a valid pool manager
    @param  _lockManager The lock manager to be checked
    @return _poolManager The valid poolManager for that lockManager
   */
  function _checkPoolManagerValidityFromLockManager(ILockManager _lockManager) internal view returns (IPoolManager _poolManager) {
    _poolManager = _lockManager.POOL_MANAGER();
    ILockManager _lockManagerFromPoolManager = _poolManager.lockManager();

    if (!POOL_MANAGER_FACTORY.isChild(_poolManager)) revert FeeManager_InvalidPoolManager(_poolManager);
    if (_lockManagerFromPoolManager != _lockManager) revert FeeManager_InvalidLockManager(_lockManager);
  }
}
