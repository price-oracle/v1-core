// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.4 <0.9.0;

import '@interfaces/IPoolManagerFactory.sol';
import '@interfaces/IPoolManager.sol';
import '@interfaces/periphery/IGovernorMiniBravo.sol';
import '@interfaces/IFeeManager.sol';

/**
  @title  LockManager governance storage contract
  @notice This contract contains the data necessary for governance
 */
interface ILockManagerGovernor is IGovernorMiniBravo {
  /*///////////////////////////////////////////////////////////////
                            ENUMS
  //////////////////////////////////////////////////////////////*/
  /**
    @notice The methods that are available for governance
    @dev    Always add new methods before LatestMethod
   */
  enum Methods {
    Deprecate,
    LatestMethod
  }
  /*///////////////////////////////////////////////////////////////
                            ERRORS
  //////////////////////////////////////////////////////////////*/

  /**
    @notice Thrown when arithmetic underflow happens
   */
  error LockManager_ArithmeticUnderflow();

  /**
    @notice Thrown when certain functions are called on a deprecated lock manager
   */
  error LockManager_Deprecated();

  /*///////////////////////////////////////////////////////////////
                            VARIABLES
  //////////////////////////////////////////////////////////////*/

  /**
    @notice Returns the pool manager factory contract
    @return _poolManagerFactory The pool manager factory
   */
  function POOL_MANAGER_FACTORY() external view returns (IPoolManagerFactory _poolManagerFactory);

  /**
    @notice Returns true if the lock manager is deprecated
    @return _deprecated True if the lock manager is deprecated
   */
  function deprecated() external view returns (bool _deprecated);

  /*///////////////////////////////////////////////////////////////
                            LOGIC
  //////////////////////////////////////////////////////////////*/

  /**
    @notice Votes yes on the proposal to deprecate the lockManager
   */
  function acceptDeprecate() external;
}
