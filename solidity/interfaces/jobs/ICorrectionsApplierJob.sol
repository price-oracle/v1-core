// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.4 <0.9.0;

import '@interfaces/jobs/IKeep3rJob.sol';
import '@interfaces/IPoolManagerFactory.sol';

/**
  @notice Applies corrections to manipulated pools
 */
interface ICorrectionsApplierJob is IKeep3rJob {
  /*///////////////////////////////////////////////////////////////
                              EVENTS
  //////////////////////////////////////////////////////////////*/

  /**
    @notice Emitted when then job is worked
    @param _pool The Uniswap V3 pool
    @param _manipulatedIndex The index of the observation that will be corrected
    @param _period How many observations the manipulation affected
   */
  event Worked(IUniswapV3Pool _pool, uint16 _manipulatedIndex, uint16 _period);

  /*///////////////////////////////////////////////////////////////
                              ERRORS
  //////////////////////////////////////////////////////////////*/

  /**
    @notice Throws if we can't verify the pool
    @param _pool The invalid pool
   */
  error CorrectionsApplierJob_InvalidPool(IUniswapV3Pool _pool);

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
  function work(
    IUniswapV3Pool _pool,
    uint16 _manipulatedIndex,
    uint16 _period
  ) external;
}
