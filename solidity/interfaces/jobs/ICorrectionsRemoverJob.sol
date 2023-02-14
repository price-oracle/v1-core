// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.4 <0.9.0;

import '@interfaces/jobs/IKeep3rJob.sol';
import '@interfaces/IPoolManagerFactory.sol';

/**
  @notice Removes the old corrections for a given pool
 */
interface ICorrectionsRemoverJob is IKeep3rJob {
  /*///////////////////////////////////////////////////////////////
                              EVENTS
  //////////////////////////////////////////////////////////////*/

  /**
    @notice Emitted when then job is worked
    @param _pool The Uniswap V3 pool
   */
  event Worked(IUniswapV3Pool _pool);

  /*///////////////////////////////////////////////////////////////
                              ERRORS
  //////////////////////////////////////////////////////////////*/

  /**
    @notice Throws if we can't verify the pool
    @param _pool The invalid pool
   */
  error CorrectionsRemoverJob_InvalidPool(IUniswapV3Pool _pool);

  /*///////////////////////////////////////////////////////////////
                            VARIABLES
  //////////////////////////////////////////////////////////////*/

  /**
    @notice Returns the pool manager factory
    @return _poolManagerFactory The pool manager factory
   */
  function POOL_MANAGER_FACTORY() external view returns (IPoolManagerFactory _poolManagerFactory);

  /**
    @notice Returns the price oracle
    @return _priceOracle The price oracle
   */
  function PRICE_ORACLE() external view returns (IPriceOracle _priceOracle);

  /*///////////////////////////////////////////////////////////////
                              LOGIC
  //////////////////////////////////////////////////////////////*/

  /**
    @notice Removes the old corrections for a given pool
    @param _pool The Uniswap V3 pool
   */
  function work(IUniswapV3Pool _pool) external;

  /**
    @notice Returns true if the oracle has old corrections for the specified pool
    @param _pool The Uniswap V3 pool
    @return _workable True if the pool can be worked
   */
  function isWorkable(IUniswapV3Pool _pool) external view returns (bool _workable);

  /**
    @notice Returns true if the oracle has old corrections for the specified pool
    @param _pool The Uniswap V3 pool
    @param _keeper The address of the keeper
    @return _workable True if the pool can be worked
   */
  function isWorkable(IUniswapV3Pool _pool, address _keeper) external returns (bool _workable);
}
