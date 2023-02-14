// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4 <0.9.0;

import '@test/e2e/Common.sol';
import '@test/e2e/BasicToken.sol';
import 'uni-v3-periphery/libraries/OracleLibrary.sol';

contract E2EPriceOracle is CommonE2EBase {
  uint24[] _fees;
  uint256 _baseAmount = 12 ether;
  uint256 constant _PRECISION = 200 gwei;

  function setUp() public override {
    super.setUp();
    _fees = new uint24[](1);
    _fees[0] = poolFee;
    vm.prank(user1);
    weth.approve(address(uniswapRouter), type(uint256).max);
  }

  function testE2EQuoteCache() public {
    uint32 _period = priceOracle.MIN_CORRECTION_PERIOD();
    uint24 _maxCacheAge = 100;
    uint256 priceOracleQuoteBefore = priceOracle.quoteCache(_baseAmount, weth, dai, _period, _maxCacheAge);

    vm.startPrank(user1);
    _swap(weth, dai, weth.balanceOf(user1));
    vm.stopPrank();

    uint256 priceOracleQuoteAfter = priceOracle.quoteCache(_baseAmount, weth, dai, _period, uint24(_period));
    uint256 uniOracleQuote = _getUniswapOracleQuote(_baseAmount, address(weth), address(dai), _fees, _period);

    assertApproxEqAbs(priceOracleQuoteBefore, priceOracleQuoteAfter, _PRECISION);
    assertGt(priceOracleQuoteAfter, uniOracleQuote);
  }

  function testE2EQuoteCacheExpired() public {
    uint32 _period = priceOracle.MIN_CORRECTION_PERIOD();
    uint24 _maxCacheAge = 160;
    uint256 priceOracleQuoteBefore = priceOracle.quoteCache(_baseAmount, weth, dai, _period, _maxCacheAge);

    vm.startPrank(user1);
    _swap(weth, dai, weth.balanceOf(user1));
    vm.stopPrank();

    advanceTime(_maxCacheAge + 1);

    uint256 priceOracleQuoteAfter = priceOracle.quoteCache(_baseAmount, weth, dai, _period, _maxCacheAge);
    assertTrue(priceOracleQuoteBefore != priceOracleQuoteAfter);
  }

  function _getUniswapOracleQuote(
    uint256 _amount,
    address _fromToken,
    address _toToken,
    uint24[] memory _poolFees,
    uint32 _period
  ) internal view returns (uint256 _amountOut) {
    OracleLibrary.WeightedTickData[] memory _tickData = new OracleLibrary.WeightedTickData[](_poolFees.length);

    for (uint256 i; i < _poolFees.length; i++) {
      address _pool = UNISWAP_V3_FACTORY.getPool(address(_fromToken), address(_toToken), _poolFees[i]);
      (_tickData[i].tick, _tickData[i].weight) = OracleLibrary.consult(_pool, _period);
    }

    int24 _weightedTick = _tickData.length == 1 ? _tickData[0].tick : OracleLibrary.getWeightedArithmeticMeanTick(_tickData);
    _amountOut = OracleLibrary.getQuoteAtTick(_weightedTick, uint128(_amount), _fromToken, _toToken);
  }
}
