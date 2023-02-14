// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.4 <0.9.0;

import 'uni-v3-core/interfaces/IUniswapV3Pool.sol';
import '@interfaces/IPoolManager.sol';
import '@interfaces/IPoolManagerFactory.sol';

/**
  @notice Deployer of pool managers
  @dev    This contract is needed to reduce the size of the pool manager factory contract
 */
interface IPoolManagerDeployer {
  /*///////////////////////////////////////////////////////////////
                              ERRORS
  //////////////////////////////////////////////////////////////*/

  /**
    @notice Thrown when someone other than the pool manager factory tries to call the method
   */
  error PoolManagerDeployer_OnlyPoolManagerFactory();

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
    @notice Deploys a new pool manager for a given UniswapV3 pool
    @param  _pool The UniswapV3 pool
    @return _poolManager The newly deployed pool manager
   */
  function deployPoolManager(IUniswapV3Pool _pool) external returns (IPoolManager _poolManager);
}
