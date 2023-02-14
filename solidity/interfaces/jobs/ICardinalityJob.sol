// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.4 <0.9.0;

import 'uni-v3-core/interfaces/IUniswapV3Pool.sol';

import '@interfaces/IFeeManager.sol';
import '@interfaces/IPoolManager.sol';
import '@interfaces/IPoolManagerFactory.sol';
import '@interfaces/periphery/IPriceOracle.sol';
import '@interfaces/jobs/IKeep3rJob.sol';

interface ICardinalityJob is IKeep3rJob {
  /*///////////////////////////////////////////////////////////////
                              EVENTS
  //////////////////////////////////////////////////////////////*/

  /**
    @notice Emitted when the minimum cardinality increase amount allowed is changed
    @param  _minCardinalityIncrease The new minimum amount
   */
  event MinCardinalityIncreaseChanged(uint16 _minCardinalityIncrease);

  /**
    @notice Emitted when the pool manager factory is changed
    @param  _poolManagerFactory The new pool manager factory
   */
  event PoolManagerFactoryChanged(IPoolManagerFactory _poolManagerFactory);

  /**
    @notice Emitted when the job is worked
    @param  _poolManager The address of the pool manager
    @param  _increaseAmount The amount of increase
   */
  event Worked(IPoolManager _poolManager, uint16 _increaseAmount);

  /*///////////////////////////////////////////////////////////////
                              ERRORS
  //////////////////////////////////////////////////////////////*/
  /**
    @notice Thrown when the proposed cardinality increase is too low
   */
  error CardinalityJob_MinCardinality();

  /**
    @notice Thrown when working with an invalid pool manager
   */
  error CardinalityJob_InvalidPoolManager();

  /*///////////////////////////////////////////////////////////////
                            VARIABLES
  //////////////////////////////////////////////////////////////*/

  /**
    @notice Returns the pool manager factory
    @return _poolManagerFactory The pool manager factory
   */
  function poolManagerFactory() external view returns (IPoolManagerFactory _poolManagerFactory);

  /**
    @notice Returns the minimum increase of cardinality allowed
    @return _minCardinalityIncrease The minimum number of slots increases allowed
   */
  function minCardinalityIncrease() external view returns (uint16 _minCardinalityIncrease);

  /*///////////////////////////////////////////////////////////////
                              LOGIC
  //////////////////////////////////////////////////////////////*/
  /**
    @notice The function worked by the keeper, which will increase the pool cardinality
    @dev    Requires enough WETH deposited for this pool to reimburse the gas consumption to the keeper
    @param  _poolManager The pool manager of the pool for which the cardinality will be increased
    @param  _increaseAmount The amount by which the cardinality will be increased
   */
  function work(IPoolManager _poolManager, uint16 _increaseAmount) external;

  /**
    @notice Checks if the job can be worked in the current block
    @param  _poolManager The pool manager of the pool for which the cardinality will be increased
    @param  _increaseAmount The increased amount of the pool cardinality
    @return _workable If the job is workable with the given inputs
   */
  function isWorkable(IPoolManager _poolManager, uint16 _increaseAmount) external view returns (bool _workable);

  /**
    @notice Checks if the job can be worked in the current block by a specific keeper
    @param  _poolManager The pool manager of the pool for which the cardinality will be increased
    @param  _increaseAmount The increased amount of the pool cardinality
    @param  _keeper The address of the keeper
    @return _workable If the job is workable with the given inputs
   */
  function isWorkable(
    IPoolManager _poolManager,
    uint16 _increaseAmount,
    address _keeper
  ) external returns (bool _workable);

  /**
    @notice Changes the min amount of cardinality increase per work
    @param  _minCardinalityIncrease The new minimum number of slots
   */
  function setMinCardinalityIncrease(uint16 _minCardinalityIncrease) external;

  /**
    @notice Changes the pool manager factory
    @param _poolManagerFactory The address of the new pool manager factory
   */
  function setPoolManagerFactory(IPoolManagerFactory _poolManagerFactory) external;

  /**
    @notice Calculates the minimum possible cardinality increase for a pool
    @param  _poolManager The pool manager of the pool for which the cardinality will be increased
    @return _minCardinalityIncrease The minimum possible cardinality increase for the pool
   */
  function getMinCardinalityIncreaseForPool(IPoolManager _poolManager) external view returns (uint256 _minCardinalityIncrease);
}
