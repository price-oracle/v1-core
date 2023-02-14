// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4 <0.9.0;

import 'solidity-utils/test/DSTestPlus.sol';

import '@contracts/periphery/PriceOracle.sol';
import '@test/utils/TestConstants.sol';
import '@test/utils/ContractDeploymentAddress.sol';

contract PriceOracleForTest is PriceOracle {
  constructor(
    IPoolManagerFactory _poolManagerFactory,
    IUniswapV3Factory _uniswapV3Factory,
    bytes32 _poolBytecodeHash,
    IERC20 _weth
  ) PriceOracle(_poolManagerFactory, _uniswapV3Factory, _poolBytecodeHash, _weth) {}

  function setCacheForTest(
    IERC20 _baseToken,
    IERC20 _quoteToken,
    uint32 _period,
    uint256 _quote
  ) external {
    (IERC20 _token0, IERC20 _token1) = _baseToken < _quoteToken ? (_baseToken, _quoteToken) : (_quoteToken, _baseToken);
    IPriceOracle.QuoteCache memory _quoteCache = IPriceOracle.QuoteCache({quote: _quote, timestamp: block.timestamp});
    _cache[_token0][_token1][_period] = _quoteCache;
  }

  function getPoolCorrectionsForTest(IUniswapV3Pool _pool) external view returns (uint256 _correctionsCount) {
    _correctionsCount = _corrections[_pool].length;
  }

  function setPoolCorrectionsTimestampsForTest(IUniswapV3Pool _pool, uint256[] memory _timestamps) external {
    _correctionsTimestamps[_pool] = _timestamps;
  }

  function setPoolCorrectionsForTest(IUniswapV3Pool _pool, IPriceOracle.Correction[] calldata _poolCorrections) external {
    for (uint256 _i; _i < _poolCorrections.length; _i++) {
      _corrections[_pool].push(
        IPriceOracle.Correction({
          amount: _poolCorrections[_i].amount,
          beforeTimestamp: _poolCorrections[_i].beforeTimestamp,
          afterTimestamp: _poolCorrections[_i].afterTimestamp
        })
      );
    }
  }

  function avoidCollisionTime(
    uint32 _startTime,
    uint32 _endTime,
    Correction memory _correction
  )
    external
    pure
    returns (
      uint32,
      uint32,
      bool _avoided
    )
  {
    return super._avoidCollisionTime(_startTime, _endTime, _correction);
  }
}

abstract contract Base is DSTestPlus, TestConstants {
  uint256 internal constant _BASE = 1 ether;

  address governance = label(address(100), 'governance');
  uint24[] fees = [10];
  uint24[] multiFees = [10, 100];
  uint160[] secondsPerLiquidityCumulativeX128s = [4, 5];
  int56[] tickCumulatives = [-2, 3];

  int24 weightedArithmeticMeanTickRes = 100000;
  int24 arithmeticMeanTick = 100000;
  uint256 public quoteRes = 10 ether;
  uint160 sqrtPrice = 1 << 96;
  uint16 observationCardinality = 10;
  uint16 observationCardinalityNext = 15;

  OracleLibrary.WeightedTickData public weightedTickDataRes = OracleLibrary.WeightedTickData(100000, 10000000000000000000);
  OracleLibrary.WeightedTickData[] ticksAndLiqs;

  PriceOracleForTest priceOracle;
  IUniswapV3Pool mockPool;
  IUniswapV3Pool anotherPool;

  IPoolManagerFactory mockPoolManagerFactory = IPoolManagerFactory(mockContract('mockPoolManagerFactory'));
  IERC20 mockWeth = IERC20(mockContract(WETH_ADDRESS, 'mockWeth'));
  IERC20 mockToken = IERC20(mockContract('mockToken'));
  IERC20 anotherToken = IERC20(mockContract('anotherToken'));

  function setUp() public virtual {
    vm.mockCall(address(mockPoolManagerFactory), abi.encodeWithSelector(IPoolManagerFactory.tokenFees.selector), abi.encode(fees));
    vm.mockCall(address(mockPoolManagerFactory), abi.encodeWithSelector(IPoolManagerFactory.isSupportedToken.selector), abi.encode(true));
    vm.mockCall(address(mockPoolManagerFactory), abi.encodeWithSelector(IPoolManagerFactory.isSupportedTokenPair.selector), abi.encode(true));

    priceOracle = new PriceOracleForTest(mockPoolManagerFactory, UNISWAP_V3_FACTORY, POOL_BYTECODE_HASH, mockWeth);

    mockPool = ContractDeploymentAddress.getTheoreticalUniPool(mockToken, mockWeth, fees[0], UNISWAP_V3_FACTORY);
    anotherPool = ContractDeploymentAddress.getTheoreticalUniPool(mockWeth, anotherToken, fees[0], UNISWAP_V3_FACTORY);

    mockCallsIUniswapV3PoolState(address(mockPool), 0, 1);
    mockCallsIUniswapV3PoolState(address(anotherPool), 0, 1);

    ticksAndLiqs.push(weightedTickDataRes);
    ticksAndLiqs.push(weightedTickDataRes);
    vm.mockCall(address(mockPoolManagerFactory), abi.encodeWithSelector(IPoolManagerFactory.tokenFees.selector), abi.encode(fees));
    vm.mockCall(address(mockPoolManagerFactory), abi.encodeWithSelector(IPoolManagerFactory.isSupportedToken.selector), abi.encode(true));
    vm.mockCall(address(mockPoolManagerFactory), abi.encodeWithSelector(IPoolManagerFactory.isSupportedTokenPair.selector), abi.encode(true));
  }

  function mockCallsIUniswapV3PoolState(
    address _pool,
    int24 _tick,
    uint128 _liquidity
  ) public {
    vm.mockCall(_pool, abi.encode(IUniswapV3PoolDerivedState.observe.selector), abi.encode(tickCumulatives, secondsPerLiquidityCumulativeX128s));
    vm.mockCall(
      _pool,
      abi.encodeWithSelector(IUniswapV3PoolState.slot0.selector),
      abi.encode(sqrtPrice, _tick, observationCardinality, observationCardinalityNext, 0, 0, 0)
    );
    vm.mockCall(_pool, abi.encodeWithSelector(IUniswapV3PoolState.observations.selector), abi.encode(0, 0, 0, true));
    vm.mockCall(_pool, abi.encodeWithSelector(IUniswapV3PoolState.liquidity.selector), abi.encode(_liquidity));
  }
}

contract UnitPriceOracleQuoteCache is Base {
  uint32 public _period = 10 minutes;
  bool _baseTokenIsToken0;

  function setUp() public override {
    super.setUp();
    _baseTokenIsToken0 = mockWeth < mockToken;
  }

  function testUsesCacheIfAvailable(uint128 _baseAmount, uint128 _baseAmount2) public {
    _baseAmount = uint128(bound(_baseAmount, 1 ether, type(uint64).max - 1));
    _baseAmount2 = uint128(bound(_baseAmount2, 1 ether, type(uint64).max - 1));

    uint24 _maxCacheAge = 1000000;
    uint256 _quote = priceOracle.quoteCache(_baseAmount, mockWeth, mockToken, _period, _maxCacheAge);
    uint256 _cachedQuote = priceOracle.quoteCache(_baseAmount2, mockWeth, mockToken, _period, _maxCacheAge);

    assertEq(_cachedQuote, (_quote * _baseAmount2) / _baseAmount);
  }

  function testUsesCacheIfAvailableReverse(uint128 _baseAmount, uint128 _baseAmount2) public {
    _baseAmount = uint128(bound(_baseAmount, 1 ether, type(uint64).max - 1));
    _baseAmount2 = uint128(bound(_baseAmount2, 1 ether, type(uint64).max - 1));

    uint24 _maxCacheAge = 1000000;
    uint256 _quote = priceOracle.quoteCache(_baseAmount, mockWeth, mockToken, _period, _maxCacheAge);
    uint256 _cachedQuote = priceOracle.quoteCache(_baseAmount2, mockToken, mockWeth, _period, _maxCacheAge);

    assertEq(_cachedQuote, (uint256(_baseAmount) * uint256(_baseAmount2)) / _quote);
  }

  function testIgnoresExpiredCache(
    uint128 _baseAmount,
    uint128 _baseAmount2,
    uint32 _quote
  ) public {
    vm.assume(_quote > 0);
    _baseAmount = uint128(bound(_baseAmount, 0.0001 ether, type(uint64).max - 1));
    _baseAmount2 = uint128(bound(_baseAmount2, 0.0001 ether, type(uint64).max - 1));

    priceOracle.setCacheForTest(mockWeth, mockToken, _period, _quote);
    uint24 _maxCacheAge = 100;
    uint256 _expectedQuote = _baseTokenIsToken0 ? (_baseAmount * _quote) / _BASE : (_baseAmount * _BASE) / (_quote);
    uint256 _cachedQuote = priceOracle.quoteCache(_baseAmount, mockWeth, mockToken, _period, _maxCacheAge);
    assertEq(_cachedQuote, _expectedQuote);

    vm.warp(block.timestamp + _maxCacheAge + 1);

    _cachedQuote = priceOracle.quoteCache(_baseAmount2, mockWeth, mockToken, _period, _maxCacheAge);
    assertTrue(_cachedQuote != _expectedQuote);
  }
}

contract UnitPriceOracleIsPairSupported is Base {
  function testIsPairSupportedWethToken() public {
    vm.expectCall(address(mockPoolManagerFactory), abi.encodeWithSelector(IPoolManagerFactory.isSupportedToken.selector, mockToken));
    priceOracle.isPairSupported(mockWeth, mockToken);
  }

  function testIsPairSupportedTokenWeth() public {
    vm.expectCall(address(mockPoolManagerFactory), abi.encodeWithSelector(IPoolManagerFactory.isSupportedToken.selector, mockToken));
    priceOracle.isPairSupported(mockToken, mockWeth);
  }

  function testIsPairSupportedTokenToken() public {
    vm.expectCall(
      address(mockPoolManagerFactory),
      abi.encodeWithSelector(IPoolManagerFactory.isSupportedTokenPair.selector, mockToken, anotherToken)
    );
    priceOracle.isPairSupported(mockToken, anotherToken);
  }
}

contract UnitPriceOracleCorrectionsRemoveOldCorrections is Base {
  IPriceOracle.Correction mockCorrection = IPriceOracle.Correction({amount: 0, beforeTimestamp: 0, afterTimestamp: 0});

  function testRevertIfNoCorrections() public {
    vm.expectRevert(IPriceOracle.PriceOracleCorrections_NoCorrectionsToRemove.selector);
    priceOracle.removeOldCorrections(mockPool);
  }

  function testRemoveOnlyOldCorrections() public {
    uint256[] memory _timestamps = new uint256[](2);
    _timestamps[0] = block.timestamp - priceOracle.MAX_CORRECTION_AGE();
    _timestamps[1] = block.timestamp;

    priceOracle.setPoolCorrectionsTimestampsForTest(mockPool, _timestamps);

    IPriceOracle.Correction[] memory _poolCorrections = new IPriceOracle.Correction[](2);
    _poolCorrections[0] = mockCorrection;
    _poolCorrections[1] = mockCorrection;

    priceOracle.setPoolCorrectionsForTest(mockPool, _poolCorrections);
    assertEq(priceOracle.poolCorrectionsCount(mockPool), 2);
    assertEq(priceOracle.getPoolCorrectionsForTest(mockPool), 2);

    priceOracle.removeOldCorrections(mockPool);
    assertEq(priceOracle.poolCorrectionsCount(mockPool), 1);
    assertEq(priceOracle.getPoolCorrectionsForTest(mockPool), 1);
  }
}

contract UnitPriceOracleCorrectionsAvoidCollisionTime is Base {
  function testStartTimeBetweenBeforeAndAfterTimestamps(uint32 beforeTimestamp, uint32 afterTimestamp) public {
    vm.assume(beforeTimestamp < type(uint32).max && afterTimestamp > beforeTimestamp + 1);

    IPriceOracle.Correction memory _correction = IPriceOracle.Correction({
      amount: 0,
      beforeTimestamp: beforeTimestamp,
      afterTimestamp: afterTimestamp
    });

    (uint32 _startTime, , bool _avoided) = priceOracle.avoidCollisionTime(beforeTimestamp + 1, afterTimestamp, _correction);

    assertTrue(_avoided);
    assertEq(_startTime, afterTimestamp);
  }

  function testEndTimeBetweenBeforeAndAfterTimestamps(uint32 beforeTimestamp, uint32 afterTimestamp) public {
    vm.assume(beforeTimestamp < type(uint32).max && afterTimestamp > beforeTimestamp + 1);

    IPriceOracle.Correction memory _correction = IPriceOracle.Correction({
      amount: 0,
      beforeTimestamp: beforeTimestamp,
      afterTimestamp: afterTimestamp
    });

    (, uint32 _endTime, bool _avoided) = priceOracle.avoidCollisionTime(beforeTimestamp, afterTimestamp - 1, _correction);

    assertTrue(_avoided);
    assertEq(_endTime, beforeTimestamp);
  }

  function testStartAndEndTimeOutsideOfTimestamps(uint32 beforeTimestamp, uint32 afterTimestamp) public {
    vm.assume(afterTimestamp > beforeTimestamp && afterTimestamp < type(uint32).max && beforeTimestamp > 1);

    IPriceOracle.Correction memory _correction = IPriceOracle.Correction({
      amount: 0,
      beforeTimestamp: beforeTimestamp,
      afterTimestamp: afterTimestamp
    });

    (uint32 _startTime, uint32 _endTime, bool _avoided) = priceOracle.avoidCollisionTime(beforeTimestamp - 1, afterTimestamp + 1, _correction);

    assertFalse(_avoided);
    assertEq(_startTime, beforeTimestamp - 1);
    assertEq(_endTime, afterTimestamp + 1);
  }
}
