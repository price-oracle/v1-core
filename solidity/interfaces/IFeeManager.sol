// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.4 <0.9.0;

import 'isolmate/interfaces/tokens/IERC20.sol';
import 'uni-v3-core/interfaces/IUniswapV3Pool.sol';

import '@interfaces/IPoolManagerFactory.sol';
import '@interfaces/IPoolManager.sol';
import '@interfaces/ILockManager.sol';
import '@interfaces/jobs/ICardinalityJob.sol';

/**
  @title FeeManager contract
  @notice This contract accumulates the fees collected from UniswapV3 pools for later use
 */
interface IFeeManager {
  /*///////////////////////////////////////////////////////////////
                              STRUCTS
  //////////////////////////////////////////////////////////////*/

  /**
    @notice Total fees deposited by a pool manager
    @param  wethForFullRange The amount of WETH dedicated to increasing the full-range position
    @param  tokenForFullRange The amount of non-WETH token dedicated to increasing the full-range position
   */
  struct FeeStore {
    uint256 wethForFullRange;
    uint256 tokenForFullRange;
  }

  /**
    @notice The values intended for cardinality incrementation
    @param  weth The amount of WETH for increasing the cardinality
    @param  currentMax The maximum value of the cardinality
    @param  customMax The maximum value of the cardinality set by the governance
   */
  struct PoolCardinality {
    uint256 weth;
    uint16 currentMax;
    uint16 customMax;
  }

  /**
    @notice The percentages of the fees directed to the maintenance and increasing cardinality
    @param  wethForMaintenance The WETH for maintenance fees percentage
    @param  wethForCardinality The WETH for cardinality fees percentage
    @param  isInitialized True if the pool is initialized
   */
  struct PoolDistributionFees {
    uint256 wethForMaintenance;
    uint256 wethForCardinality;
    bool isInitialized;
  }

  /*///////////////////////////////////////////////////////////////
                              ERRORS
  //////////////////////////////////////////////////////////////*/

  /**
    @notice Thrown when we can't verify the pool manager
   */

  error FeeManager_InvalidPoolManager(IPoolManager _poolManager);

  /**
    @notice Thrown when we can't verify the lock manager
   */
  error FeeManager_InvalidLockManager(ILockManager _lockManager);

  /**
    @notice Thrown when we can't verify the old fee manager
   */
  error FeeManager_InvalidOldFeeManager(IFeeManager _feeManager);

  /**
    @notice Thrown when we can't verify the pool manager factory
   */
  error FeeManager_InvalidPoolManagerFactory();

  /**
    @notice Thrown when we can't verify the UniswapV3 pool
    @param _sender The sender that is not a valid UniswapV3Pool
   */
  error FeeManager_InvalidUniswapPool(address _sender);

  /**
      @notice Thrown when excess liquidity for the full range has been left over
   */
  error FeeManager_ExcessiveLiquidityLeft();

  /**
    @notice Thrown when the liquidity provided of the token is incorrect
   */
  error FeeManager_InvalidTokenLiquidity();

  /**
    @notice Thrown when the amount of ETH to get is less than the fees spent on the swap
   */
  error FeeManager_SmallSwap();

  /**
      @notice Thrown when the sender is not the cardinality job
   */
  error FeeManager_NotCardinalityJob();

  /**
    @notice Thrown when the cardinality is greater than the maximum
   */
  error FeeManager_CardinalityExceeded();

  /**
    @notice Thrown when trying to migrate fee managers, but cardinality of the pool was already initialized
   */
  error FeeManager_NonZeroCardinality();

  /**
    @notice Thrown when trying to migrate fee managers, but the pool manager deposits were already initialized
   */
  error FeeManager_NonZeroPoolDeposits();

  /**
    @notice Thrown when trying to migrate fee managers, but pool manager distribution was already initialized
   */
  error FeeManager_InitializedPoolDistribution();

  /**
      @notice Thrown when the WETH for maintenance is greater than the maximum
   */
  error FeeManager_WethForMaintenanceExceeded();

  /**
      @notice Thrown when the WETH for cardinality is greater than the maximum
   */
  error FeeManager_WethForCardinalityExceeded();

  /*///////////////////////////////////////////////////////////////
                              EVENTS
  //////////////////////////////////////////////////////////////*/

  /**
    @notice Emitted when the fees are deposited
    @param  _poolManager The pool manager providing the fees
    @param  _wethFees The total amount of WETH fees collected and dedicated to increasing the full-range position
    @param  _tokenFees The total amount of non-WETH token fees collected and dedicated to increasing the full-range position
    @param  _wethForMaintenance The total amount of WETH fees collected and destined for the maintenance
    @param  _wethForCardinality The total amount of WETH fees collected and destined to increase the cardinality of the pool
   */
  event FeesDeposited(
    IPoolManager _poolManager,
    uint256 _wethFees,
    uint256 _tokenFees,
    uint256 _wethForMaintenance,
    uint256 _wethForCardinality
  );

  /**
    @notice Emitted when the swap gas cost multiplier has been changed
    @param _swapGasCostMultiplier The swap gas cost multiplier to be set
   */
  event SwapGasCostMultiplierChanged(uint256 _swapGasCostMultiplier);

  /**
    @notice Emitted when the cardinality job is set
    @param _cardinalityJob The cardinality job to be set
   */
  event CardinalityJobSet(ICardinalityJob _cardinalityJob);

  /**
    @notice Emitted when the maintenance governance address has been changed
    @param _maintenanceGovernance The maintenance governance address
   */
  event MaintenanceGovernanceChanged(address _maintenanceGovernance);

  /**
    @notice Emitted when the fees percentage of WETH for maintenance has been changed
    @param _wethForMaintenance The fees percentage of WETH for maintenance
   */
  event WethForMaintenanceChanged(uint256 _wethForMaintenance);

  /**
    @notice Emitted when the fees percentage of WETH for cardinality has been changed
    @param _wethForCardinality The fees percentage of WETH for cardinality
   */
  event WethForCardinalityChanged(uint256 _wethForCardinality);

  /**
    @notice Emitted when an old fee manager migrates to a new fee manager
    @param  _poolManager The pool manager address
    @param  _oldFeeManager The old fee manager address
    @param  _newFeeManager The new fee manager address
   */
  event Migrated(address _poolManager, address _oldFeeManager, address _newFeeManager);

  /*///////////////////////////////////////////////////////////////
                            VARIABLES
  //////////////////////////////////////////////////////////////*/

  /**
    @notice Returns the WETH token contract
    @return _weth The WETH token
   */
  function WETH() external view returns (IERC20 _weth);

  /**
    @notice Returns the amount of fees collected by a pool manager
    @param  _poolManager The pool manager
    @return wethForFullRange The amount of WETH dedicated to increasing the full-range position
    @return tokenForFullRange The amount of non-WETH tokens dedicated to increasing the full-range position
   */
  // solhint-disable wonderland/non-state-vars-leading-underscore
  function poolManagerDeposits(IPoolManager _poolManager) external view returns (uint256 wethForFullRange, uint256 tokenForFullRange);

  /**
    @notice Returns information about the pool cardinality
    @param  _poolManager The pool manager
    @return weth The amount of WETH to increase the cardinality
    @return currentMax The maximum value of the cardinality in a pool
    @return customMax The maximum value of the cardinality in a pool set by the governance
   */
  // solhint-disable wonderland/non-state-vars-leading-underscore
  function poolCardinality(IPoolManager _poolManager)
    external
    view
    returns (
      uint256 weth,
      uint16 currentMax,
      uint16 customMax
    );

  /**
    @notice Returns the distribution percentages in a pool
    @param  _poolManager The pool manager
    @return wethForMaintenance The WETH for maintenance fees percentage
    @return wethForCardinality The WETH for cardinality fees percentage
    @return isInitialized True if the pool is initialized
   */
  // solhint-disable wonderland/non-state-vars-leading-underscore
  function poolDistribution(IPoolManager _poolManager)
    external
    view
    returns (
      uint256 wethForMaintenance,
      uint256 wethForCardinality,
      bool isInitialized
    );

  /**
    @notice Returns the pool manager factory
    @return _poolManagerFactory The pool manager factory
   */
  function POOL_MANAGER_FACTORY() external view returns (IPoolManagerFactory _poolManagerFactory);

  /**
    @notice Returns the cardinality job
    @return _cardinalityJob The cardinality job
   */
  function cardinalityJob() external view returns (ICardinalityJob _cardinalityJob);

  /**
    @notice Returns the address that receives the maintenance fee in WETH
    @return _maintenanceGovernance The address that receives the maintenance fee in WETH
   */
  function maintenanceGovernance() external view returns (address _maintenanceGovernance);

  /**
    @notice Returns the maximum value of cardinality
    @dev    655 max cardinality array length
    @return _poolCardinalityMax The maximum value of cardinality
   */
  function poolCardinalityMax() external view returns (uint16 _poolCardinalityMax);

  /**
    @notice Returns the gas multiplier used to calculate the cost of swapping non-WETH token to WETH
    @dev    This calculates whether the cost of the swap will be higher than the amount to be swapped
    @return _swapGasCostMultiplier The value to calculate whether the swap is profitable
   */
  function swapGasCostMultiplier() external view returns (uint256 _swapGasCostMultiplier);

  /*///////////////////////////////////////////////////////////////
                              LOGIC
  //////////////////////////////////////////////////////////////*/

  /**
    @notice Updates the record for fees collected from the pool manager
    @dev    Splits the deposited fees into parts for different purposes
    @dev    The fees from concentrated and full-range positions are handled differently
    @param  _wethFees The total amount of WETH fees collected from the pool
    @param  _tokenFees The total amount of non-WETH token fees collected from the pool
   */
  function depositFromPoolManager(uint256 _wethFees, uint256 _tokenFees) external;

  /**
    @notice Updates the record for fees collected from the lock manager
    @dev    Splits the deposited fees into parts for different purposes
    @dev    The fees from concentrated and full-range positions are handled differently
    @param  _wethFees The total amount of WETH fees collected from the pool
    @param  _tokenFees The total amount of non-WETH token fees collected from the pool
   */
  function depositFromLockManager(uint256 _wethFees, uint256 _tokenFees) external;

  /**
    @notice Transfers the necessary amount of WETH and token to increase the full range of a specific pool
    @dev    Update the balances of tokens intended to increase the full-range position
    @dev    If necessary, it will swap tokens for WETH.
    @param  _pool The pool that needs to increase the full range
    @param  _token The token that corresponds to the pool that needs to increase the full range
    @param  _neededWeth The amount of WETH needed for increase the full range
    @param  _neededToken The amount of token needed for increase the full range
    @param  _isWethToken0 True if WETH is token0 in the pool
   */
  function increaseFullRangePosition(
    IUniswapV3Pool _pool,
    IERC20 _token,
    uint256 _neededWeth,
    uint256 _neededToken,
    bool _isWethToken0
  ) external;

  /**
    @notice Transfers the necessary amount of WETH and token to increase the full range of a specific pool
    @dev    Callback that is called after uniswapV3MintCallback from PoolManager if the donor is the FeeManager
    @dev    Updates the balances of WETH and token intended to increase the full-range position
    @param  _pool The pool that need to increase the full range
    @param  _token The token that corresponds to the pool that needs to increase the full range
    @param  _neededWeth The amount of WETH needed to increase the full range
    @param  _neededToken The amount of token needed to increase the full range
   */
  function fullRangeCallback(
    IUniswapV3Pool _pool,
    IERC20 _token,
    uint256 _neededWeth,
    uint256 _neededToken
  ) external;

  /**
    @notice Callback that is called when calling the swap method in a UniswapV3 pool
    @dev    It is only called when you need to swap non-WETH tokens for WETH
    @param  _amount0Delta  The amount of token0
    @param  _amount1Delta The amount of token1
    @param  _data The data that differentiates through an address whether to mint or transferFrom for the full range
   */
  function uniswapV3SwapCallback(
    int256 _amount0Delta,
    int256 _amount1Delta,
    bytes calldata _data
  ) external;

  /**
    @notice Updates the cardinality in a pool
    @dev    This method only can be called by the cardinality job
    @param  _poolManager The pool manager
    @param  _weth The amount of WETH
    @param  _cardinality The custom cardinality value
   */
  function increaseCardinality(
    IPoolManager _poolManager,
    uint256 _weth,
    uint16 _cardinality
  ) external;

  /**
    @notice Migrates to a new fee manager
    @dev    Should be called from a valid lock manager
    @param  _newFeeManager The new fee manager
   */
  function migrateTo(IFeeManager _newFeeManager) external;

  /**
    @notice Migrates from an old fee manager
    @dev    Should be called from the old fee manager
    @dev    Receives WETH and non-WETH tokens from the old fee manager
    @param  _poolManager The pool manager that is migrating its fee manager
    @param  _poolCardinality The current pool cardinality
    @param  _poolManagerDeposits The liquidity to deploy for the full range
    @param  _poolManagerDeposits The distribution of percentages for cardinality and maintenance
    @param  _poolDistributionFees The distribution fees of the pool
   */
  function migrateFrom(
    IPoolManager _poolManager,
    PoolCardinality memory _poolCardinality,
    FeeStore memory _poolManagerDeposits,
    PoolDistributionFees memory _poolDistributionFees
  ) external;

  /**
    @notice Set the swap gas multiplier
    @dev    This method only can be called by governance
    @param  _swapGasCostMultiplier The value of the gas multiplier that will be set
   */
  function setSwapGasCostMultiplier(uint256 _swapGasCostMultiplier) external;

  /**
    @notice Sets the cardinality job
    @param  _cardinalityJob The cardinality job
   */
  function setCardinalityJob(ICardinalityJob _cardinalityJob) external;

  /**
    @notice Sets the maximum value to increase the cardinality
    @param  _poolCardinalityMax The maximum value
   */
  function setPoolCardinalityMax(uint16 _poolCardinalityMax) external;

  /**
    @notice Sets a custom maximum value to increase cardinality
    @param  _poolManager The pool manager
    @param  _cardinality The custom cardinality value
   */
  function setPoolCardinalityTarget(IPoolManager _poolManager, uint16 _cardinality) external;

  /**
    @notice Sets maintenance governance address
    @param  _maintenanceGovernance The address that has to receive the maintenance WETH
   */
  function setMaintenanceGovernance(address _maintenanceGovernance) external;

  /**
    @notice Sets the percentage of the WETH fees for maintenance
    @param  _poolManager The pool manager
    @param  _wethForMaintenance The percentage of the WETH fees for maintenance
   */
  function setWethForMaintenance(IPoolManager _poolManager, uint256 _wethForMaintenance) external;

  /**
    @notice Sets the percentage of the WETH fees for cardinality
    @param  _poolManager The pool manager
    @param  _wethForCardinality The percentage of the WETH fees for cardinality
   */
  function setWethForCardinality(IPoolManager _poolManager, uint256 _wethForCardinality) external;

  /**
    @notice Returns the max cardinality for a pool
    @param  _poolManager The pool manager
    @param  _maxCardinality The max cardinality for a pool
   */
  function getMaxCardinalityForPool(IPoolManager _poolManager) external view returns (uint256 _maxCardinality);
}
