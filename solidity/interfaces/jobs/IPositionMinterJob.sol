// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.4 <0.9.0;

import '@interfaces/IPoolManager.sol';
import '@interfaces/IPoolManagerFactory.sol';
import '@interfaces/jobs/IKeep3rJob.sol';

/**
  @notice Runs the job handling the position creation in WETH/TOKEN pools
 */
interface IPositionMinterJob is IKeep3rJob {
  /*///////////////////////////////////////////////////////////////
                              EVENTS
  //////////////////////////////////////////////////////////////*/

  /**
    @notice Emitted when a pool manager is worked
    @param  _poolManager The address of the pool manager where positions were created
   */
  event Worked(IPoolManager _poolManager);

  /*///////////////////////////////////////////////////////////////
                              ERRORS
  //////////////////////////////////////////////////////////////*/

  /**
    @notice Thrown when the pool manager cannot be verified
    @param  _poolManager The pool manager that can't be verified
   */
  error PositionMinterJob_InvalidPoolManager(IPoolManager _poolManager);

  /*///////////////////////////////////////////////////////////////
                            VARIABLES
  //////////////////////////////////////////////////////////////*/
  /**
    @notice Returns the pool manager factory
    @return _poolManagerFactory The pool manager factory
   */
  function POOL_MANAGER_FACTORY() external view returns (IPoolManagerFactory _poolManagerFactory);

  /*///////////////////////////////////////////////////////////////
                              LOGIC
  //////////////////////////////////////////////////////////////*/

  /**
    @notice Creates the needed positions in the target pool manager and rewards the keeper for doing so
    @dev    Will revert if the job is paused or if the keeper is not valid
    @param  _poolManager The address of the target pool manager
   */
  function work(IPoolManager _poolManager) external;

  /**
    @notice Returns true if the specified pool manager can be worked
    @param  _poolManager The address of the target pool manager
    @return _workable True if the pool manager can be worked
   */
  function isWorkable(IPoolManager _poolManager) external returns (bool _workable);

  /**
    @notice Returns true if the specified keeper can work with the target pool manager
    @param  _poolManager The address of the target pool manager
    @param  _keeper The address of the keeper
    @return _workable True if the pool manager can be worked
   */
  function isWorkable(IPoolManager _poolManager, address _keeper) external returns (bool _workable);
}
