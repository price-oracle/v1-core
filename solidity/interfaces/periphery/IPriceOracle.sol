// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.4 <0.9.0;

import 'isolmate/interfaces/tokens/IERC20.sol';
import 'uni-v3-core/interfaces/IUniswapV3Factory.sol';
import 'uni-v3-core/interfaces/IUniswapV3Pool.sol';
import '@interfaces/IPoolManagerFactory.sol';

/**
  @title PriceOracle contract
  @notice This contract allows you to get the price of different assets through WETH pools
 */
interface IPriceOracle {
  /*///////////////////////////////////////////////////////////////
                              STRUCTS
  //////////////////////////////////////////////////////////////*/
  /**
    @notice A quote saved in a particular timestamp to use as cache
    @param quote The quote given from tokenA to tokenB
    @param timestamp The timestamp for when the cache was saved
   */
  struct QuoteCache {
    uint256 quote;
    uint256 timestamp;
  }

  /**
    @notice The correction information
    @param amount The difference between the tick value before and after the correction
    @param beforeTimestamp
    @param afterTimestamp
  */
  struct Correction {
    int56 amount;
    uint32 beforeTimestamp;
    uint32 afterTimestamp;
  }
  /**
    @notice The observation information, copied from the Uniswap V3 oracle library
    @param blockTimestamp The block timestamp of the observation
    @param tickCumulative The tick accumulator, i.e. tick * time elapsed since the pool was first initialized
    @param secondsPerLiquidityCumulativeX128 The seconds per liquidity, i.e. seconds elapsed / max(1, liquidity) since the pool was first initialized
    @param initialized Whether or not the observation is initialized
   */
  struct Observation {
    uint32 blockTimestamp;
    int56 tickCumulative;
    uint160 secondsPerLiquidityCumulativeX128;
    bool initialized;
  }

  /**
    @notice Keeps the list of the applied corrections
    @param manipulated The array of the manipulated observations
    @param beforeManipulation The observation that was right before the manipulation
    @param afterManipulation The observation that was right after the manipulation
    @param postAfterManipulation The observation succeeding the one after the manipulation
  */
  struct CorrectionObservations {
    Observation[] manipulated;
    Observation beforeManipulation;
    Observation afterManipulation;
    Observation postAfterManipulation;
  }

  /*///////////////////////////////////////////////////////////////
                              ERRORS
  //////////////////////////////////////////////////////////////*/
  /**
    @notice Thrown when volatility in period is higher than accepted
   */
  error PriceOracle_ExceededVolatility();

  /**
    @notice Throws if the token is not supported
   */
  error PriceOracleBase_TokenNotSupported();

  /**
    @notice Throws if the seconds ago order should be reversed
   */
  error PriceOracleCorrections_InvalidSecondsAgosOrder();

  /**
    @notice Throws if base amount overflows uint128
   */
  error PriceOracleCorrections_BaseAmountOverflow();

  /**
    @notice Throws when edge ticks are not similar enough
   */
  error PriceOracleCorrections_EdgeTicksTooDifferent();

  /**
    @notice Throws when observations either before or after the manipulation were also manipulated
   */
  error PriceOracleCorrections_EdgeTicksAverageTooDifferent();

  /**
   @notice Throws when the difference between the tick before manipulation and the tick at the start of manipulation is not big enough
   */
  error PriceOracleCorrections_TicksBeforeAndAtManipulationStartAreTooSimilar();

  /**
    @notice Throws when the difference between the tick after manipulation and the tick at the start of manipulation is not big enough
   */
  error PriceOracleCorrections_TicksAfterAndAtManipulationStartAreTooSimilar();

  /**
    @notice Throws when the difference between the tick after manipulation and the tick at the end of manipulation is not big enough
   */
  error PriceOracleCorrections_TicksAfterAndAtManipulationEndAreTooSimilar();

  /**
    @notice Throws when trying to apply the correction to a pool we didn't deploy
   */
  error PriceOracleCorrections_PoolNotSupported();

  /**
    @notice Throws when trying to correct a manipulation that was already corrected
   */
  error PriceOracleCorrections_ManipulationAlreadyProcessed();

  /**
    @notice Throws when the observation after the manipulation observation has not yet happened
   */
  error PriceOracleCorrections_AfterObservationIsNotNewer();

  /**
    @notice Throws when there are no corrections for removal
   */
  error PriceOracleCorrections_NoCorrectionsToRemove();

  /**
    @notice Throws when an invalid period was supplied
   */
  error PriceOracleCorrections_PeriodTooShort();

  /**
    @notice Throws when the supplied period exceeds the maximum correction age
    @dev    The danger of using a long period lies in the fact that obsolete corrections will eventually be removed.
            Thus the oracle would return un-corrected, possibly manipulated data.
   */
  error PriceOracleCorrections_PeriodTooLong();

  /**
    @notice Throws when it's not possible to calculate the after observation, nor force it with burn1, just wait 1 block and retry
   */
  error PriceOracleCorrections_AfterObservationCannotBeCalculatedOnSameBlock();

  /*///////////////////////////////////////////////////////////////
                            VARIABLES
  //////////////////////////////////////////////////////////////*/
  /**
    @notice Returns the correction delay
    @dev The delay should be big enough for the attack to not be arbitraged and hence detected by the contract
    @return The the correction delay
   */
  function CORRECTION_DELAY() external view returns (uint32);

  /**
    @notice Returns the minumum correction period
    @return The minumum correction period
   */
  function MIN_CORRECTION_PERIOD() external view returns (uint32);

  /**
    @notice Returns the maximum correction age
    @return The maximum correction age
   */
  function MAX_CORRECTION_AGE() external view returns (uint32);

  /**
    @notice Returns the upper tick difference for the 10% price change
    @return The upper tick difference for the 10% price change
   */
  function UPPER_TICK_DIFF_10() external view returns (int24);

  /**
    @notice Returns the lower tick difference for the 10% price change
    @return The lower tick difference for the 10% price change
   */
  function LOWER_TICK_DIFF_10() external view returns (int24);

  /**
    @notice Returns the upper tick difference for the 20% price change
    @return The upper tick difference for the 20% price change
   */
  function UPPER_TICK_DIFF_20() external view returns (int24);

  /**
    @notice Returns the lower tick difference for the 20% price change
    @return The lower tick difference for the 20% price change
   */
  function LOWER_TICK_DIFF_20() external view returns (int24);

  /**
    @notice Returns the upper tick difference for the 23.5% price change
    @return The upper tick difference for the 23.5% price change
   */
  function UPPER_TICK_DIFF_23_5() external view returns (int24);

  /**
    @notice Returns the lower tick difference for the 23.5% price change
    @return The lower tick difference for the 23.5% price change
   */
  function LOWER_TICK_DIFF_23_5() external view returns (int24);

  /**
    @notice Returns the upper tick difference for the 30% price change
    @return The upper tick difference for the 30% price change
   */
  function UPPER_TICK_DIFF_30() external view returns (int24);

  /**
    @notice Returns the lower tick difference for the 30% price change
    @return The lower tick difference for the 30% price change
   */
  function LOWER_TICK_DIFF_30() external view returns (int24);

  /**
    @notice Returns the UniswapV3 factory contract
    @return _uniswapV3Factory The UniswapV3 factory contract
   */
  function UNISWAP_V3_FACTORY() external view returns (IUniswapV3Factory _uniswapV3Factory);

  /**
    @notice Returns the UniswapV3 pool bytecode hash
    @return _poolBytecodeHash The UniswapV3 pool bytecode hash
   */
  function POOL_BYTECODE_HASH() external view returns (bytes32 _poolBytecodeHash);

  /**
    @notice Returns the WETH token
    @return _weth The WETH token
   */
  function WETH() external view returns (IERC20 _weth);

  /**
    @notice Returns the pool manager factory
    @return _poolManagerFactory The pool manager factory
   */
  function POOL_MANAGER_FACTORY() external view returns (IPoolManagerFactory _poolManagerFactory);

  /*///////////////////////////////////////////////////////////////
                              LOGIC
  //////////////////////////////////////////////////////////////*/
  /**
    @notice Returns true if a pair is supported on the oracle
    @param  _tokenA TokenA for the pair
    @param  _tokenB TokenB for the pair
    @return _isSupported True if the pair is supported on the oracle
   */
  function isPairSupported(IERC20 _tokenA, IERC20 _tokenB) external view returns (bool _isSupported);

  /**
    @notice Returns the price of a given amount of tokenA quoted in tokenB using the cache if available
    @param  _baseAmount The amount of tokenA to quote
    @param  _tokenA Token to quote in tokenB
    @param  _tokenB The quote token
    @param  _period The period to quote
    @param  _maxCacheAge Ignore the cached quote if it's older than the max age, in seconds
    @return _quoteAmount The quoted amount of tokenA in tokenB
   */
  function quoteCache(
    uint256 _baseAmount,
    IERC20 _tokenA,
    IERC20 _tokenB,
    uint32 _period,
    uint24 _maxCacheAge
  ) external returns (uint256 _quoteAmount);

  /**
    @notice Applies a price correction to the pool
    @param _pool The Uniswap V3 pool address
    @param _manipulatedIndex The index of the observation that will be corrected
    @param _period How many observations the manipulation affected
   */
  function applyCorrection(
    IUniswapV3Pool _pool,
    uint16 _manipulatedIndex,
    uint16 _period
  ) external;

  /**
    @notice Removes old corrections to potentially increase gas efficiency on quote)
    @param _pool The Uniswap V3 pool address
   */
  function removeOldCorrections(IUniswapV3Pool _pool) external;

  /**
    @notice Returns the number of the corrections for a pool
    @param _pool The Uniswap V3 pool address
    @return _correctionsCount The number of the corrections for a pool
  */
  function poolCorrectionsCount(IUniswapV3Pool _pool) external view returns (uint256 _correctionsCount);

  /**
    @notice Returns the timestamp of the oldest correction for a given pool
    @dev Returns 0 if there is no corrections for the pool
    @param _pool The Uniswap V3 pool address
    @return _timestamp The timestamp of the oldest correction for a given pool
   */
  function getOldestCorrectionTimestamp(IUniswapV3Pool _pool) external view returns (uint256 _timestamp);

  /**
    @notice Lists all corrections for a pool
    @param _pool The Uniswap V3 pool address
    @param _startFrom Index from where to start the pagination
    @param _amount Maximum amount of corrections to retrieve
    @return _poolCorrections Paginated corrections of the pool
  */
  function listPoolCorrections(
    IUniswapV3Pool _pool,
    uint256 _startFrom,
    uint256 _amount
  ) external view returns (Correction[] memory _poolCorrections);

  /**
    @notice Provides the quote taking into account any corrections happened during the provided period
    @param _baseAmount The amount of base token
    @param _baseToken The base token address
    @param _quoteToken The quote token address
    @param _period The TWAP period
    @return _quoteAmount The quote amount
   */
  function quote(
    uint256 _baseAmount,
    IERC20 _baseToken,
    IERC20 _quoteToken,
    uint32 _period
  ) external view returns (uint256 _quoteAmount);

  /**
    @notice Return true if the pool was manipulated
    @param _pool The Uniswap V3 pool address
    @return _manipulated Whether the pool is manipulated or not
   */
  function isManipulated(IUniswapV3Pool _pool) external view returns (bool _manipulated);

  /**
    @notice Return true if the pool has been manipulated
    @param _pool The Uniswap V3 pool address
    @param _lowerTickDifference The maximum difference between the lower ticks before and after the correction
    @param _upperTickDifference The maximum difference between the upper ticks before and after the correction
    @param _correctionPeriod The correction period
    @return _manipulated Whether the pool is manipulated or not
   */
  function isManipulated(
    IUniswapV3Pool _pool,
    int24 _lowerTickDifference,
    int24 _upperTickDifference,
    uint32 _correctionPeriod
  ) external view returns (bool _manipulated);

  /**
    @notice Returns the TWAP for the given period taking into account any corrections happened during the period
    @param _pool The Uniswap V3 pool address
    @param _period The TWAP period, in seconds
    @return _arithmeticMeanTick The TWAP
   */
  function getPoolTickWithCorrections(IUniswapV3Pool _pool, uint32 _period) external view returns (int24 _arithmeticMeanTick);
}
