// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.4 <0.9.0;

import '@interfaces/IPoolManager.sol';
import '@interfaces/jobs/IKeep3rJob.sol';

interface ILiquidityIncreaserJob is IKeep3rJob {
  /*///////////////////////////////////////////////////////////////
                              ERRORS
  //////////////////////////////////////////////////////////////*/
  /**
    @notice Thrown when an invalid pool manager was passed to the job
   */
  error LiquidityIncreaserJob_InvalidPoolManager();

  /**
    @notice Thrown when the price oracle detects a manipulation
   */
  error LiquidityIncreaserJob_PoolManipulated();

  /**
    @notice Thrown when the job transfers less WETH and non-WETH token amounts to the pool than min WETH increase
   */
  error LiquidityIncreaserJob_InsufficientIncrease();

  /*///////////////////////////////////////////////////////////////
                              EVENTS
  //////////////////////////////////////////////////////////////*/
  /**
    @notice Emitted when a fee manager is worked
    @param  _poolManager The address of the pool manager where the full range was incremented
    @param  _amountWeth The WETH added to the full-range position
    @param  _amountToken The Token added to the full-range position
   */
  event Worked(IPoolManager _poolManager, uint256 _amountWeth, uint256 _amountToken);

  /**
    @notice Emitted when the min WETH increase is set
    @param  _minIncreaseWeth The min WETH increase that has to be added
   */
  event MinIncreaseWethSet(uint256 _minIncreaseWeth);

  /*///////////////////////////////////////////////////////////////
                              VARIABLES
  //////////////////////////////////////////////////////////////*/
  /**
    @notice Returns the WETH contract
    @return _weth The WETH token
   */
  function WETH() external view returns (IERC20 _weth);

  /**
    @notice Returns the pool manager factory
    @return _poolManagerFactory The pool manager factory
   */
  function POOL_MANAGER_FACTORY() external view returns (IPoolManagerFactory _poolManagerFactory);

  /**
    @notice Returns the WETH-denominated amount of liquidity that must be added to the full-range position
    @return _minIncreaseWeth The minimum WETH increase
   */
  function minIncreaseWeth() external view returns (uint256 _minIncreaseWeth);

  /*///////////////////////////////////////////////////////////////
                              LOGIC
  //////////////////////////////////////////////////////////////*/
  /**
    @notice Increases the full-range position of a given pool manager
    @dev    Will revert if the job is paused or if the keeper is not valid
    @param  _poolManager The address of the target pool manager
    @param  _wethAmount The amount of WETH to be inserted in the full-range position
    @param  _tokenAmount The amount of non-WETH token to be inserted in the full-range position
   */
  function work(
    IPoolManager _poolManager,
    uint256 _wethAmount,
    uint256 _tokenAmount
  ) external;

  /**
    @notice Returns true if the specified pool manager can be worked
    @param  _poolManager The address of the target pool manager
    @return _workable True if the pool manager can be worked
   */
  function isWorkable(IPoolManager _poolManager) external returns (bool _workable);

  /**
    @notice Returns true if the specified keeper can work with the selected pool manager
    @param  _poolManager The address of the target pool manager
    @param  _keeper The address of the keeper
    @return _workable True if the pool manager can be worked
   */
  function isWorkable(IPoolManager _poolManager, address _keeper) external returns (bool _workable);

  /**
    @notice Sets the new min WETH increase
    @param _minIncreaseWeth The min WETH increase
   */
  function setMinIncreaseWeth(uint256 _minIncreaseWeth) external;
}
