// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.4 <0.9.0;

import 'uni-v3-periphery/libraries/OracleLibrary.sol';
import 'solidity-utils/contracts/Roles.sol';

import '@interfaces/periphery/IPriceOracle.sol';
import '@contracts/utils/PriceLib.sol';

contract PriceOracle is IPriceOracle {
  /// @inheritdoc IPriceOracle
  uint32 public constant CORRECTION_DELAY = 2 minutes;
  /// @inheritdoc IPriceOracle
  uint32 public constant MIN_CORRECTION_PERIOD = 10 minutes;
  /// @inheritdoc IPriceOracle
  uint32 public constant MAX_CORRECTION_AGE = 4 weeks + CORRECTION_DELAY;
  /// @inheritdoc IPriceOracle
  int24 public constant UPPER_TICK_DIFF_10 = 953;
  /// @inheritdoc IPriceOracle
  int24 public constant LOWER_TICK_DIFF_10 = 1053;
  /// @inheritdoc IPriceOracle
  int24 public constant UPPER_TICK_DIFF_20 = 1823;
  /// @inheritdoc IPriceOracle
  int24 public constant LOWER_TICK_DIFF_20 = 2231;
  /// @inheritdoc IPriceOracle
  int24 public constant UPPER_TICK_DIFF_23_5 = 2110;
  /// @inheritdoc IPriceOracle
  int24 public constant LOWER_TICK_DIFF_23_5 = 2678;
  /// @inheritdoc IPriceOracle
  int24 public constant UPPER_TICK_DIFF_30 = 2623;
  /// @inheritdoc IPriceOracle
  int24 public constant LOWER_TICK_DIFF_30 = 3566;

  /// @inheritdoc IPriceOracle
  IPoolManagerFactory public immutable POOL_MANAGER_FACTORY;

  /// @inheritdoc IPriceOracle
  IUniswapV3Factory public immutable UNISWAP_V3_FACTORY;

  /// @inheritdoc IPriceOracle
  bytes32 public immutable POOL_BYTECODE_HASH;

  /// @inheritdoc IPriceOracle
  IERC20 public immutable WETH;

  /**
    @notice pool => timestamp => bool
   */
  mapping(IUniswapV3Pool => mapping(uint256 => bool)) internal _correctionTimestamp;
  /**
    @notice The timestamps of all corrections for all pools
   */
  mapping(IUniswapV3Pool => uint256[]) internal _correctionsTimestamps;
  /**
    @notice The corrections data for all pools
   */
  mapping(IUniswapV3Pool => Correction[]) internal _corrections;

  /**
    @notice tokenA => tokenB => period = QuoteCache
   */
  mapping(IERC20 => mapping(IERC20 => mapping(uint32 => QuoteCache))) internal _cache;

  /**
    @notice The base we use for increasing precision
   */
  uint256 internal constant _BASE = 1 ether;

  constructor(
    IPoolManagerFactory _poolManagerFactory,
    IUniswapV3Factory _uniswapV3Factory,
    bytes32 _poolBytecodeHash,
    IERC20 _weth
  ) {
    POOL_MANAGER_FACTORY = _poolManagerFactory;
    UNISWAP_V3_FACTORY = _uniswapV3Factory;
    POOL_BYTECODE_HASH = _poolBytecodeHash;
    WETH = _weth;
  }

  /// @inheritdoc IPriceOracle
  function isPairSupported(IERC20 _tokenA, IERC20 _tokenB) external view returns (bool) {
    if (_tokenB == WETH) {
      return POOL_MANAGER_FACTORY.isSupportedToken(_tokenA);
    }
    if (_tokenA == WETH) {
      return POOL_MANAGER_FACTORY.isSupportedToken(_tokenB);
    }
    return POOL_MANAGER_FACTORY.isSupportedTokenPair(_tokenA, _tokenB);
  }

  /**
    @notice  Returns the first available WETH pool for a token
    @param   _tokenA The token paired with WETH
    @return  _pool The WETH-tokenA pool
   */
  function _getDefaultWethPool(IERC20 _tokenA) internal view returns (IUniswapV3Pool _pool) {
    uint24[] memory _fees = POOL_MANAGER_FACTORY.tokenFees(_tokenA);
    if (_fees.length == 0) revert PriceOracleBase_TokenNotSupported();
    (_pool, ) = PriceLib._calculateTheoreticalAddress(WETH, _tokenA, _fees[0], UNISWAP_V3_FACTORY, POOL_BYTECODE_HASH);
  }

  /// @inheritdoc IPriceOracle
  function quote(
    uint256 _baseAmount,
    IERC20 _baseToken,
    IERC20 _quoteToken,
    uint32 _period
  ) external view returns (uint256 _quoteAmount) {
    _quoteAmount = _quoteWithCorrections(_baseAmount, _baseToken, _quoteToken, _period);
  }

  /// @inheritdoc IPriceOracle
  function quoteCache(
    uint256 _baseAmount,
    IERC20 _baseToken,
    IERC20 _quoteToken,
    uint32 _period,
    uint24 _maxCacheAge
  ) external returns (uint256 _quoteAmount) {
    _quoteAmount = _quoteCache(_baseAmount, _baseToken, _quoteToken, _period, _maxCacheAge);
  }

  /**
    @notice  Returns a quote from baseToken to quoteToken taking into consideration the cache
    @param   _baseAmount The amount of _baseToken to quote
    @param   _baseToken The base token to be quoted
    @param   _quoteToken The quote token
    @param   _period The period to quote
    @param   _maxCacheAge Ignore the cached quote if it's older than the max age, in seconds
    @return  _quoteAmount The quoted amount
   */
  function _quoteCache(
    uint256 _baseAmount,
    IERC20 _baseToken,
    IERC20 _quoteToken,
    uint32 _period,
    uint24 _maxCacheAge
  ) internal returns (uint256 _quoteAmount) {
    bool _baseTokenIsToken0 = _baseToken < _quoteToken;
    (IERC20 _token0, IERC20 _token1) = _baseTokenIsToken0 ? (_baseToken, _quoteToken) : (_quoteToken, _baseToken);
    QuoteCache memory _cachedQuote = _cache[_token0][_token1][_period];
    if (_cachedQuote.timestamp >= block.timestamp - _maxCacheAge) {
      return _baseTokenIsToken0 ? (_baseAmount * _cachedQuote.quote) / _BASE : (_baseAmount * _BASE) / (_cachedQuote.quote);
    }

    _quoteAmount = _quoteWithCorrections(_baseAmount, _baseToken, _quoteToken, _period);

    _cache[_token0][_token1][_period] = QuoteCache({
      quote: _baseTokenIsToken0 ? (_quoteAmount * _BASE) / _baseAmount : (_baseAmount * _BASE) / _quoteAmount,
      timestamp: block.timestamp
    });
  }

  /*///////////////////////////////////////////////////////////////
                            CORRECTIONS
  //////////////////////////////////////////////////////////////*/
  /* Notation explanation:
    You will see these type of examples below:
    ... C x| x C x x | x M x ...
    x = observation (not manipulated nor corrected)
    C = corrected observation
    M = manipulated observation
    x| = quote _startTime that is equal to x timestamp (this is used on Correction collision avoidance)
    | = quote _endTime (equal or between x & x)
  */

  /// @inheritdoc IPriceOracle
  function poolCorrectionsCount(IUniswapV3Pool _pool) external view returns (uint256 _correctionsCount) {
    _correctionsCount = _correctionsTimestamps[_pool].length;
  }

  /// @inheritdoc IPriceOracle
  function getOldestCorrectionTimestamp(IUniswapV3Pool _pool) external view returns (uint256 _timestamp) {
    uint256 _poolCorrectionsCount = _correctionsTimestamps[_pool].length;
    if (_poolCorrectionsCount > 0) {
      _timestamp = _correctionsTimestamps[_pool][_poolCorrectionsCount - 1];
    }
  }

  /// @inheritdoc IPriceOracle
  function listPoolCorrections(
    IUniswapV3Pool _pool,
    uint256 _startFrom,
    uint256 _amount
  ) external view returns (Correction[] memory _poolCorrections) {
    uint256 _length = _corrections[_pool].length;
    if (_amount > _length - _startFrom) {
      _amount = _length - _startFrom;
    }

    _poolCorrections = new Correction[](_amount);

    uint256 _index;
    while (_index < _amount) {
      _poolCorrections[_index] = _corrections[_pool][_startFrom + _index];

      unchecked {
        ++_index;
      }
    }
  }

  /**
    @notice Fetches an observation from the pool
    @param _pool The Uniswap V3 pool address
    @param _index The index of the observation
    @return _observation The observation
   */
  function _getObservation(IUniswapV3Pool _pool, uint16 _index) internal view virtual returns (Observation memory _observation) {
    (uint32 _blockTimestamp, int56 _tickCumulative, uint160 _secondsPerLiquidityCumulativeX128, bool _initialized) = _pool.observations(_index);
    _observation = Observation({
      blockTimestamp: _blockTimestamp,
      tickCumulative: _tickCumulative,
      secondsPerLiquidityCumulativeX128: _secondsPerLiquidityCumulativeX128,
      initialized: _initialized
    });
  }

  /**
    @notice Calculates the correction amount for a given manipulation
    @param _correctionObservations The list of the applied corrections
    @param _tickAfterManipulation The value of the tick after the manipulation
    @param _arithmeticMeanTick The corrected arithmetic mean tick
    @return _correction By how much the tick was corrected
   */
  function _getCorrection(
    CorrectionObservations memory _correctionObservations,
    int24 _tickAfterManipulation,
    int24 _arithmeticMeanTick
  ) internal pure returns (int56 _correction) {
    // calculate correction
    int56 _correctionA = _correctionObservations.afterManipulation.tickCumulative - _correctionObservations.manipulated[0].tickCumulative;

    // calculate fill correction
    int56 _beforeTickCumulativeDiff = _correctionObservations.manipulated[0].tickCumulative -
      _correctionObservations.beforeManipulation.tickCumulative;
    int24 _tickBeforeManipulation = int24(
      _beforeTickCumulativeDiff /
        int56(int32(_correctionObservations.manipulated[0].blockTimestamp - _correctionObservations.beforeManipulation.blockTimestamp))
    );

    uint32 _manipulationTimeDelta = _correctionObservations.afterManipulation.blockTimestamp -
      _correctionObservations.manipulated[0].blockTimestamp;
    int56 _correctionAF = (int56(_tickBeforeManipulation + _tickAfterManipulation) * int32(_manipulationTimeDelta)) / 2;

    _correction = _correctionA - _correctionAF;

    _validateCorrection(_correctionObservations, _arithmeticMeanTick, _tickBeforeManipulation, _tickAfterManipulation);
  }

  /**
    @notice Confirms the correction is valid
    @param _correctionObservations The array of the corrected observations
    @param _arithmeticMeanTick The corrected arithmetic mean tick
    @param _tickBeforeManipulation The tick before the manipulation
    @param _tickAfterManipulation The tick after the manipulation
   */
  function _validateCorrection(
    CorrectionObservations memory _correctionObservations,
    int24 _arithmeticMeanTick,
    int24 _tickBeforeManipulation,
    int24 _tickAfterManipulation
  ) internal pure {
    uint256 _lastManipulatedObservationsIndex = _correctionObservations.manipulated.length - 1;

    Observation memory _observationAtManipulationStart = _lastManipulatedObservationsIndex == 0
      ? _correctionObservations.afterManipulation
      : _correctionObservations.manipulated[1];

    int24 _tickAtManipulationStart = int24(
      (_observationAtManipulationStart.tickCumulative - _correctionObservations.manipulated[0].tickCumulative) /
        int56(int32(_observationAtManipulationStart.blockTimestamp - _correctionObservations.manipulated[0].blockTimestamp))
    );

    // [1] Check if _tickAtManipulationStart is extremely higher|lower than _tickBeforeManipulation // 10%
    if (
      _tickBeforeManipulation + UPPER_TICK_DIFF_10 >= _tickAtManipulationStart &&
      _tickBeforeManipulation - LOWER_TICK_DIFF_10 <= _tickAtManipulationStart
    ) revert PriceOracleCorrections_TicksBeforeAndAtManipulationStartAreTooSimilar();

    int56 _manipulationEndTickCumulativeDiff = _correctionObservations.afterManipulation.tickCumulative -
      _correctionObservations.manipulated[_lastManipulatedObservationsIndex].tickCumulative;

    int24 _tickAtManipulationEnd = int24(
      _manipulationEndTickCumulativeDiff /
        int56(
          int32(
            _correctionObservations.afterManipulation.blockTimestamp -
              _correctionObservations.manipulated[_lastManipulatedObservationsIndex].blockTimestamp
          )
        )
    );

    // [2] compare _tickAfterManipulation against _tickAtManipulationEnd // 10%
    if (
      _tickAfterManipulation + UPPER_TICK_DIFF_10 >= _tickAtManipulationEnd &&
      _tickAfterManipulation - LOWER_TICK_DIFF_10 <= _tickAtManipulationEnd
    ) revert PriceOracleCorrections_TicksAfterAndAtManipulationEndAreTooSimilar();

    // [3] check if _tickBeforeManipulation and _tickAfterManipulation are similar // 20%
    if (
      _tickBeforeManipulation + UPPER_TICK_DIFF_20 < _tickAfterManipulation ||
      _tickBeforeManipulation - LOWER_TICK_DIFF_20 > _tickAfterManipulation
    ) revert PriceOracleCorrections_EdgeTicksTooDifferent();

    // Check if _before nor _after observations are manipulated observations
    // [4] check if (_tickBeforeManipulation & _tickAfterManipulation) average is similar to _arithmeticMeanTick // 23.5%
    int24 _averageTick = (_tickBeforeManipulation + _tickAfterManipulation) / 2;
    if (_averageTick + UPPER_TICK_DIFF_23_5 < _arithmeticMeanTick || _averageTick - LOWER_TICK_DIFF_23_5 > _arithmeticMeanTick)
      revert PriceOracleCorrections_EdgeTicksAverageTooDifferent();
  }

  /// @inheritdoc IPriceOracle
  function applyCorrection(
    IUniswapV3Pool _pool,
    uint16 _manipulatedIndex,
    uint16 _period
  ) external {
    IPoolManager _poolManager = POOL_MANAGER_FACTORY.poolManagers(_pool);
    if (address(_poolManager) == address(0)) revert PriceOracleCorrections_PoolNotSupported();

    CorrectionObservations memory _correctionObservations = CorrectionObservations({
      manipulated: new Observation[](_period),
      beforeManipulation: Observation(0, 0, 0, false),
      afterManipulation: Observation(0, 0, 0, false),
      postAfterManipulation: Observation(0, 0, 0, false)
    });

    (, , uint16 _observationIndex, uint16 _observationCardinality, , , ) = _pool.slot0();
    int24 _tickAfterManipulation;

    {
      for (uint16 _index; _index < _period; _index++) {
        _correctionObservations.manipulated[_index] = _getObservation(_pool, (_manipulatedIndex + _index) % _observationCardinality);

        // [IMPORTANT] Checks and sets all timestamps in manipulated observations as corrected
        // this avoids multiple corrections to apply to an already corrected observation.
        // i.e. on x M1 x M2 x Where x is non-manipulated M1 is first manipulation and M2 is second manipulation
        // a correction can be sent to include M1 to M2, and a new correction of M2 will affect N&M correction amount
        if (_correctionTimestamp[_pool][_correctionObservations.manipulated[_index].blockTimestamp])
          revert PriceOracleCorrections_ManipulationAlreadyProcessed();
        _correctionTimestamp[_pool][_correctionObservations.manipulated[_index].blockTimestamp] = true;
      }
    }

    uint32 _manipulatedTimestamp = _correctionObservations.manipulated[0].blockTimestamp;

    // grab surrounding observations
    uint16 _beforeManipulatedIndex = _manipulatedIndex == 0 ? _observationCardinality - 1 : _manipulatedIndex - 1;
    _correctionObservations.beforeManipulation = _getObservation(_pool, _beforeManipulatedIndex);

    uint16 _afterManipulationObservationIndex = (_manipulatedIndex + _period) % _observationCardinality;
    {
      _correctionObservations.afterManipulation = _getObservation(_pool, _afterManipulationObservationIndex);

      // Make sure afterManipulation is newer
      if (_correctionObservations.afterManipulation.blockTimestamp < _correctionObservations.manipulated[_period - 1].blockTimestamp)
        revert PriceOracleCorrections_AfterObservationIsNotNewer();

      // Force a new observation to happen if post after observation is on slot0
      // (after manipulation is on _observationIndex)
      if (_afterManipulationObservationIndex == _observationIndex) {
        uint32 _timeDelta = uint32(block.timestamp) - _correctionObservations.afterManipulation.blockTimestamp;
        if (_timeDelta > 0) {
          _poolManager.burn1();
          _correctionObservations.postAfterManipulation = _getObservation(
            _pool,
            (_afterManipulationObservationIndex + 1) % _observationCardinality
          );
        } else {
          revert PriceOracleCorrections_AfterObservationCannotBeCalculatedOnSameBlock();
        }
      } else {
        _correctionObservations.postAfterManipulation = _getObservation(
          _pool,
          (_afterManipulationObservationIndex + 1) % _observationCardinality
        );
      }

      if (_tickAfterManipulation == 0) {
        // After Manipulation tick needs to be obtained using Post After Manipulation observation.
        // calculate correct _tickAfterManipulation using after & post after available observations (no slot0)
        int56 _afterTickCumulativeDiff = _correctionObservations.postAfterManipulation.tickCumulative -
          _correctionObservations.afterManipulation.tickCumulative;
        _tickAfterManipulation = int24(
          _afterTickCumulativeDiff /
            int56(int32(_correctionObservations.postAfterManipulation.blockTimestamp - _correctionObservations.afterManipulation.blockTimestamp))
        );
      }
    }

    // get correct TWAP
    int24 _arithmeticMeanTick = _getPoolTickWithCorrections(_pool, MIN_CORRECTION_PERIOD);

    // calculate correction
    int56 _correction = _getCorrection(_correctionObservations, _tickAfterManipulation, _arithmeticMeanTick);
    _correctionsTimestamps[_pool].push(_manipulatedTimestamp);
    _corrections[_pool].push(
      Correction({
        amount: _correction,
        beforeTimestamp: _manipulatedTimestamp,
        afterTimestamp: _correctionObservations.afterManipulation.blockTimestamp
      })
    );
  }

  /// @inheritdoc IPriceOracle
  function removeOldCorrections(IUniswapV3Pool _pool) external {
    // Find amount of old correction to remove
    uint256 _correctionsLength = _correctionsTimestamps[_pool].length;
    uint256 _oldCorrectionsToRemove;
    uint32 _oldThreshold = uint32(block.timestamp) - MAX_CORRECTION_AGE;
    for (uint256 _index = 0; _index < _correctionsLength; _index++) {
      if (_correctionsTimestamps[_pool][_index] > _oldThreshold) break;
      _oldCorrectionsToRemove++;
    }

    if (_oldCorrectionsToRemove == 0) revert PriceOracleCorrections_NoCorrectionsToRemove();

    // new length will be
    _correctionsLength -= _oldCorrectionsToRemove;
    // move items _oldCorrectionsToRemove times forward in the array
    for (uint256 _index = 0; _index < _correctionsLength; _index++) {
      uint256 _replaceIndex = _index + _oldCorrectionsToRemove;
      // delete corrected timestamp from mapping
      delete _correctionTimestamp[_pool][_correctionsTimestamps[_pool][_index]];
      _correctionsTimestamps[_pool][_index] = _correctionsTimestamps[_pool][_replaceIndex];
      _corrections[_pool][_index] = _corrections[_pool][_replaceIndex];
    }

    // delete extra array items
    for (uint256 _index = 0; _index < _oldCorrectionsToRemove; _index++) {
      _correctionsTimestamps[_pool].pop();
      _corrections[_pool].pop();
    }
  }

  /**
    @notice Provides the quote taking into account any corrections happened during the provided period
    @param _baseAmount The amount of base token
    @param _baseToken The base token address
    @param _quoteToken The quote token address
    @param _period The TWAP period
    @return _quoteAmount The quote amount
   */
  function _quoteWithCorrections(
    uint256 _baseAmount,
    IERC20 _baseToken,
    IERC20 _quoteToken,
    uint32 _period
  ) internal view returns (uint256 _quoteAmount) {
    if (_period < MIN_CORRECTION_PERIOD) revert PriceOracleCorrections_PeriodTooShort();
    if (_period > MAX_CORRECTION_AGE) revert PriceOracleCorrections_PeriodTooLong();
    if (uint256(uint128(_baseAmount)) != _baseAmount) revert PriceOracleCorrections_BaseAmountOverflow();

    bool _wethIsBase = _baseToken == WETH;
    IERC20 _tokenA = _wethIsBase ? _quoteToken : _baseToken;

    // Using default pool for simplification
    IUniswapV3Pool _pool = _getDefaultWethPool(_tokenA);

    // Get corrected _arithmeticMeanTick;
    int24 _arithmeticMeanTick = _getPoolTickWithCorrections(_pool, _period);

    _quoteAmount = OracleLibrary.getQuoteAtTick(_arithmeticMeanTick, uint128(_baseAmount), address(_baseToken), address(_quoteToken));
  }

  /// @inheritdoc IPriceOracle
  function isManipulated(IUniswapV3Pool _pool) external view returns (bool _manipulated) {
    _manipulated = _isManipulated(_pool, LOWER_TICK_DIFF_10, UPPER_TICK_DIFF_10, MIN_CORRECTION_PERIOD);
  }

  /// @inheritdoc IPriceOracle
  function isManipulated(
    IUniswapV3Pool _pool,
    int24 _lowerTickDifference,
    int24 _upperTickDifference,
    uint32 _correctionPeriod
  ) external view returns (bool _manipulated) {
    _manipulated = _isManipulated(_pool, _lowerTickDifference, _upperTickDifference, _correctionPeriod);
  }

  /**
    @notice Return true if the pool has been manipulated
    @param _pool The Uniswap V3 pool address
    @param _lowerTickDifference The maximum difference between the lower ticks before and after the correction
    @param _upperTickDifference The maximum difference between the upper ticks before and after the correction
    @param _correctionPeriod The correction period
    @return _manipulated Whether the pool is manipulated or not
   */
  function _isManipulated(
    IUniswapV3Pool _pool,
    int24 _lowerTickDifference,
    int24 _upperTickDifference,
    uint32 _correctionPeriod
  ) internal view returns (bool _manipulated) {
    (, int24 _slot0Tick, , , , , ) = _pool.slot0();
    int24 _correctedTick = _getPoolTickWithCorrections(_pool, _correctionPeriod);

    if (_slot0Tick > _correctedTick) {
      _manipulated = _slot0Tick > _correctedTick + _upperTickDifference;
    } else {
      _manipulated = _slot0Tick < _correctedTick - _lowerTickDifference;
    }
  }

  /// @inheritdoc IPriceOracle
  function getPoolTickWithCorrections(IUniswapV3Pool _pool, uint32 _period) external view virtual returns (int24 _arithmeticMeanTick) {
    if (_period < MIN_CORRECTION_PERIOD) revert PriceOracleCorrections_PeriodTooShort();
    if (_period > MAX_CORRECTION_AGE) revert PriceOracleCorrections_PeriodTooLong();
    _arithmeticMeanTick = _getPoolTickWithCorrections(_pool, _period);
  }

  /**
    @notice Returns the arithmetic mean tick from the pool with applied corrections
    @param _pool The Uniswap V3 pool address
    @param _period The period to quote
    @return _arithmeticMeanTick The arithmetic mean tick
   */
  function _getPoolTickWithCorrections(IUniswapV3Pool _pool, uint32 _period) internal view virtual returns (int24 _arithmeticMeanTick) {
    uint32 _blockTimestamp = uint32(block.timestamp);
    uint32 _endTime = _blockTimestamp - CORRECTION_DELAY;
    uint32 _startTime = _endTime - _period;
    // correction to apply
    int56 _correctionAmount;
    (_correctionAmount, _startTime, _endTime) = _getCorrectionsForQuote(_pool, _startTime, _endTime);

    uint32[] memory _secondsAgos = new uint32[](2);
    _secondsAgos[0] = _blockTimestamp - _startTime;
    _secondsAgos[1] = _blockTimestamp - _endTime;

    _arithmeticMeanTick = _consult(_pool, _secondsAgos, _correctionAmount);
  }

  /**
    @notice  Return the arithmetic mean tick from the pool
    @param   _pool The address of the Uniswap V3 pool
    @param   _secondsAgos From how long ago each cumulative tick should be returned
    @param   _correctionAmount By how much the cumulative ticks should be corrected
    @return  _arithmeticMeanTick The arithmetic mean tick
   */
  function _consult(
    IUniswapV3Pool _pool,
    uint32[] memory _secondsAgos,
    int56 _correctionAmount
  ) internal view returns (int24 _arithmeticMeanTick) {
    if (_secondsAgos[1] > _secondsAgos[0]) revert PriceOracleCorrections_InvalidSecondsAgosOrder();

    (int56[] memory _tickCumulatives, ) = _pool.observe(_secondsAgos);
    int56 _tickCumulativesDelta = _tickCumulatives[1] - _tickCumulatives[0] - _correctionAmount;

    uint32 _timeDelta = _secondsAgos[0] - _secondsAgos[1];
    _arithmeticMeanTick = int24(_tickCumulativesDelta / int32(_timeDelta));
    // Always round to negative infinity
    if (_tickCumulativesDelta < 0 && (_tickCumulativesDelta % int32(_timeDelta) != 0)) _arithmeticMeanTick--;
  }

  /**
    @notice Finds a correction for the given period in the given pool
    @param _pool The Uniswap V3 pool address
    @param _startTime The start quote timestamp
    @param _endTime The end quote timestamp
    @return _correctionAmount By how much the tick will be corrected
    @return The start quote timestamp
    @return The end quote timestamp
   */
  function _getCorrectionsForQuote(
    IUniswapV3Pool _pool,
    uint32 _startTime,
    uint32 _endTime
  )
    internal
    view
    virtual
    returns (
      int56 _correctionAmount,
      uint32,
      uint32
    )
  {
    // Finding correction to apply...
    uint256 _correctionsTimestampsLength = _correctionsTimestamps[_pool].length;
    if (_correctionsTimestampsLength == 0) {
      // no corrections to apply, quote normally
      return (0, _startTime, _endTime);
    }

    uint256 _newerCorrectionTimestamp = _correctionsTimestamps[_pool][_correctionsTimestampsLength - 1];
    // is newer correction outside of period?
    // C | x x x x | x ...
    uint256 _newerCorrectionEndTimestamp = _corrections[_pool][_correctionsTimestampsLength - 1].afterTimestamp;
    if (_newerCorrectionEndTimestamp < _startTime) {
      // no corrections to apply, quote normally

      return (0, _startTime, _endTime);
    }

    // now we know that the newer correction might apply

    // if only correction, search no more
    if (_correctionsTimestampsLength == 1) {
      // is newer correction on delay period (correction just happened)
      // x x x x | x C x ...
      if (_newerCorrectionTimestamp > _endTime) {
        // no corrections to apply, quote normally
        return (0, _startTime, _endTime);
      }

      Correction memory _correction = _corrections[_pool][0];
      bool _avoided;
      (_startTime, _endTime, _avoided) = _avoidCollisionTime(_startTime, _endTime, _correction);
      if (_avoided) {
        // correction avoided, just quote
        return (0, _startTime, _endTime);
      }

      // _correction is the only correction to apply
      return (_correction.amount, _startTime, _endTime);
    }

    // there is more than 1 correction
    uint256 _validCorrectionIndex = _correctionsTimestampsLength - 1;
    bool _endTimeCollisionCheck;
    // we need to figure out if there is a more relevant correction (closer to startDate)
    for (; _validCorrectionIndex >= 0; _validCorrectionIndex--) {
      _newerCorrectionTimestamp = _correctionsTimestamps[_pool][_validCorrectionIndex];

      // Check if correction is newer than _endTime
      if (_newerCorrectionTimestamp > _endTime) {
        // newer correction on delay period (correction just happened)
        if (_validCorrectionIndex == 0) break;
        continue;
      }

      Correction memory _correction = _corrections[_pool][_validCorrectionIndex];

      // Check if endTime has a correction collision (only done once for most recent correction that is not newer)
      if (!_endTimeCollisionCheck) {
        _endTimeCollisionCheck = true;
        if (_correction.afterTimestamp > _endTime) {
          // collision, reduce _endTime to avoid correction
          _endTime = _correction.beforeTimestamp;
          // add correction amount to unquotedCorrectionsAmount
          // go to next correction since this is now not being taken into account
          if (_validCorrectionIndex == 0) break;
          continue;
        }
      }

      if (_newerCorrectionTimestamp < _startTime) {
        if (_correction.afterTimestamp < _startTime) {
          // correction is too old, break loop
          break;
        }
        // startTime is in between correction times, avoid startTime
        if (_startTime > _correction.beforeTimestamp && _startTime < _correction.afterTimestamp) {
          // ... C | x x x | ... to ... C x| x x | ...
          // ... C | C x x | ... to ... C C x| x | ...
          // ... x | C x x | ... to ... x C x| x | ...
          _startTime = _correction.afterTimestamp; // reduce quote width to avoid a correction
          break;
        }
      }
      // sum valid correction
      _correctionAmount += _correction.amount;
      if (_validCorrectionIndex == 0) break;
    }

    return (_correctionAmount, _startTime, _endTime);
  }

  /**
    @notice Updates quote start and end timestamps such that they're outside of the correction
    @param _startTime The start quote timestamp
    @param _endTime The end quote timestamp
    @param _correction The correction we're checking
    @return The new start of the quote
    @return The new end of the quote
    @return _avoided If the quote width was reduced to avoid a correction
   */
  function _avoidCollisionTime(
    uint32 _startTime,
    uint32 _endTime,
    Correction memory _correction
  )
    internal
    pure
    returns (
      uint32,
      uint32,
      bool _avoided
    )
  {
    if (_startTime >= _correction.beforeTimestamp && _startTime <= _correction.afterTimestamp) {
      // ... C | x x x | ... to ... C x| x x | ...
      // ... C | C x x | ... to ... C C x| x | ...
      // ... x | C x x | ... to ... x C x| x | ...
      _startTime = _correction.afterTimestamp;
      _avoided = true;
    }
    if (_endTime >= _correction.beforeTimestamp && _endTime <= _correction.afterTimestamp) {
      //  x| x x | C ... to x| x x| C  ...
      //  x| x C | C ... to x| x| C C  ...
      //  x| x C | x ... to x| x| C x  ...
      _endTime = _correction.beforeTimestamp;
      _avoided = true;
    }

    return (_startTime, _endTime, _avoided);
  }
}
