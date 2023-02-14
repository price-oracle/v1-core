// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4 <0.9.0;

import '@test/e2e/Common.sol';

contract E2EPriceOracleCorrections is CommonE2EBase {
  uint256 balanceBefore;
  uint16 observationIndexBefore;

  IUniswapV3Pool _pool;
  IPoolManager _poolManager;
  IERC20 _token;

  uint256 constant ONE_PERCENT = 1e18 / 100;
  uint256 constant ONE_BPS = ONE_PERCENT / 100;
  uint128 internal baseAmount = 1 ether;
  uint32 internal quotePeriod = 10 minutes;

  function setUp() public override {
    super.setUp();

    _poolManager = poolManagerDai;
    _pool = _poolManager.POOL();
    _token = _poolManager.TOKEN();

    // Approve the Uniswap router to make swaps
    vm.startPrank(user1);
    weth.approve(address(uniswapRouter), type(uint256).max);
    _token.approve(address(uniswapRouter), type(uint256).max);
    vm.stopPrank();
  }

  function testE2EValidateCorrections() public {
    // ----- 1. Apply a correction in a insufficiently volatile pool
    vm.startPrank(user1);

    // Saving the token balance to swap back exactly what was received from the pool
    balanceBefore = _token.balanceOf(user1);

    // Save the current observation index
    (, , observationIndexBefore, , , , ) = _pool.slot0();

    // Mine a block
    mineBlock();

    // The pool is ok before the manipulation
    assertFalse(priceOracle.isManipulated(_pool));

    // Trading just a little bit, this won't trigger the manipulation check
    _swap(weth, _token, 100 ether);

    // Arbitrage back
    _swap(_token, weth, _token.balanceOf(user1) - balanceBefore);

    // Should NOT be manipulated
    assertFalse(priceOracle.isManipulated(_pool));

    vm.expectRevert(IPriceOracle.PriceOracleCorrections_TicksBeforeAndAtManipulationStartAreTooSimilar.selector);
    priceOracle.applyCorrection(_pool, observationIndexBefore + 1, 1);

    // ----- 2. Applying a correction before the price had a chance to return to before-manipulation level
    // Save the current observation index
    (, , observationIndexBefore, , , , ) = _pool.slot0();

    // Manipulate the pool
    _swap(weth, _token, weth.balanceOf(user1) / 150_000);

    // Weak attempt to restore the price, swapping 1% of the manipulation size
    _swap(_token, weth, (_token.balanceOf(user1) - balanceBefore) / 10);

    // Should be manipulated because the arbitrage failed
    assertTrue(priceOracle.isManipulated(_pool));

    vm.expectRevert(IPriceOracle.PriceOracleCorrections_EdgeTicksTooDifferent.selector);
    priceOracle.applyCorrection(_pool, observationIndexBefore + 1, 1);

    // Arbitrage a little bit more
    _swap(_token, weth, _token.balanceOf(user1) / 1500);

    // Should still be manipulated
    assertTrue(priceOracle.isManipulated(_pool));

    vm.expectRevert(IPriceOracle.PriceOracleCorrections_TicksAfterAndAtManipulationEndAreTooSimilar.selector);
    priceOracle.applyCorrection(_pool, observationIndexBefore + 1, 2);

    // Arbitrage all the way back to the original price
    _swap(_token, weth, _token.balanceOf(user1) / 300);
    (, , observationIndexBefore, , , , ) = _pool.slot0();

    // Should NOT be manipulated
    assertFalse(priceOracle.isManipulated(_pool));

    // Save the latest observation index
    (, , observationIndexBefore, , , , ) = _pool.slot0();

    // Manipulate the pool
    _swap(weth, _token, weth.balanceOf(user1) / 1000);

    // Arbitrage back
    _swap(_token, weth, _token.balanceOf(user1) - balanceBefore);

    // Process the manipulation
    priceOracle.applyCorrection(_pool, observationIndexBefore + 1, 1);

    // ----- 3. Processing the same manipulation twice
    vm.expectRevert(IPriceOracle.PriceOracleCorrections_ManipulationAlreadyProcessed.selector);
    priceOracle.applyCorrection(_pool, observationIndexBefore + 1, 1);

    vm.stopPrank();
  }

  function testE2EDetectManipulations() public {
    uint256 _quoteBefore = _quoteUniswap(baseAmount, weth, _token);

    vm.startPrank(user1);

    // The pool is ok before the manipulation
    assertFalse(priceOracle.isManipulated(_pool));

    // Saving the token balance to swap back exactly what was received from the pool
    balanceBefore = _token.balanceOf(user1);

    // Save the current observation index
    (, , observationIndexBefore, , , , ) = _pool.slot0();

    // Mine a block
    mineBlock();

    // Manipulate the pool
    _swap(weth, _token, weth.balanceOf(user1));

    // The pool is manipulated now
    assertTrue(priceOracle.isManipulated(_pool));

    // Mine some blocks to make arbitrage stronger
    advanceTime(BLOCK_TIME * 6);

    // Arbitrage back
    _swap(_token, weth, _token.balanceOf(user1) - balanceBefore);

    // Should NOT be manipulated
    assertFalse(priceOracle.isManipulated(_pool));

    // Apply the correction
    priceOracle.applyCorrection(_pool, observationIndexBefore + 1, 1);

    // Mine more blocks
    advanceTime(BLOCK_TIME * 6);

    uint256 _quoteAfter = _quoteUniswap(baseAmount, weth, _token);
    uint256 _quoteWithCorrections = priceOracle.quote(baseAmount, weth, _token, quotePeriod);

    // Quote before should be more or less equal to the quote with correction
    // While the quote after will be completely off
    assertGt(_quoteBefore, _quoteAfter * 4);
    assertRelApproxEq(_quoteWithCorrections, _quoteBefore, ONE_PERCENT);

    vm.stopPrank();
  }

  function testE2ESubsequentManipulations() public {
    uint16 _manipulatedIndex;
    uint16 _period;
    uint256 _quoteWithCorrections;

    // ----- 1. A few manipulations and corrections in a row
    // x M1 x M2 x M3 x M4, etc each corrected right after the manipulation
    uint256 _quoteBefore = _quoteUniswap(baseAmount, weth, _token);

    for (uint256 _index = 1; _index < 100; _index++) {
      advanceTime(BLOCK_TIME * _index);

      (_manipulatedIndex, _period) = _manipulatePool(_poolManager);
      priceOracle.applyCorrection(_pool, _manipulatedIndex, _period);

      // For the first correction, quote in the middle of the correction to test collisions
      if (_index == 1) {
        advanceTime(2 minutes - BLOCK_TIME * 2);
        _quoteWithCorrections = priceOracle.quote(baseAmount, weth, _token, quotePeriod);
        assertRelApproxEq(_quoteWithCorrections, _quoteBefore, ONE_PERCENT);
      }

      // We need to get the correction in range of the quoting
      advanceTime(2 minutes + 1);

      assertGt(_quoteBefore, _quoteUniswap(baseAmount, weth, _token));

      _quoteWithCorrections = priceOracle.quote(baseAmount, weth, _token, quotePeriod);
      assertRelApproxEq(_quoteWithCorrections, _quoteBefore, ONE_PERCENT);
    }

    // ----- 2. Manipulate, create a normal tick and then manipulate again
    // x x M1 M2 x M3 M4 x, M1-M4 corrected as one
    (_manipulatedIndex, _period) = _manipulatePool(_poolManager);
    (, uint16 _secondPeriod) = _manipulatePool(_poolManager);
    priceOracle.applyCorrection(_pool, _manipulatedIndex, _period + _secondPeriod + 1);

    // We need to get the correction in range of the quoting
    advanceTime(2 minutes + 1);

    assertGt(_quoteBefore, _quoteUniswap(baseAmount, weth, _token));

    _quoteWithCorrections = priceOracle.quote(baseAmount, weth, _token, quotePeriod);
    assertRelApproxEq(_quoteWithCorrections, _quoteBefore, ONE_PERCENT);

    // ----- 3. Test collisions with multiple corrections
    (_manipulatedIndex, _period) = _manipulatePool(_poolManager);
    priceOracle.applyCorrection(_pool, _manipulatedIndex, _period);

    advanceTime(2 minutes - BLOCK_TIME * 2);

    _quoteWithCorrections = priceOracle.quote(baseAmount, weth, _token, quotePeriod);
    assertRelApproxEq(_quoteWithCorrections, _quoteBefore, ONE_PERCENT);
  }

  function testE2EAvoidCollisions() public {
    // Save the current quote
    uint256 _quoteBefore = _quoteUniswap(baseAmount, weth, _token);

    // Manipulate (2 or more consecutive observations)
    advanceTime(2 minutes);
    (uint16 _manipulatedIndex, uint16 _period) = _manipulatePool(_poolManager);
    (uint32 _manipulatedTimestamp, , , ) = _pool.observations(_manipulatedIndex);

    // Apply correction (length > 1)
    assertGt(_period, 1);
    priceOracle.applyCorrection(_pool, _manipulatedIndex, _period);

    // Quote x | ... x | C C x ...
    uint256 _quoteWithCorrections = priceOracle.quote(baseAmount, weth, _token, quotePeriod);
    assertRelApproxEq(_quoteWithCorrections, _quoteBefore, ONE_BPS);

    // Quote x | ... x |C C x ...
    vm.warp(_manipulatedTimestamp + priceOracle.CORRECTION_DELAY());
    _quoteWithCorrections = priceOracle.quote(baseAmount, weth, _token, quotePeriod);
    assertRelApproxEq(_quoteWithCorrections, _quoteBefore, ONE_BPS);

    // Quote x | ... x C | C x ...
    advanceTime(5 seconds);
    _quoteWithCorrections = priceOracle.quote(baseAmount, weth, _token, quotePeriod);
    assertRelApproxEq(_quoteWithCorrections, _quoteBefore, ONE_BPS);

    // Quote x | ... x C |C x ...
    assertEq(_period, 2);
    (_manipulatedTimestamp, , , ) = _pool.observations(_manipulatedIndex + 1);
    vm.warp(_manipulatedTimestamp + priceOracle.CORRECTION_DELAY());
    _quoteWithCorrections = priceOracle.quote(baseAmount, weth, _token, quotePeriod);
    assertRelApproxEq(_quoteWithCorrections, _quoteBefore, ONE_BPS);

    // Quote x | ... x C C | x ...
    advanceTime(5 seconds);
    _quoteWithCorrections = priceOracle.quote(baseAmount, weth, _token, quotePeriod);
    assertRelApproxEq(_quoteWithCorrections, _quoteBefore, ONE_PERCENT);
  }

  function testE2EManipulateObservationZero() public {
    // Save the current quote
    uint256 _quoteBefore = _quoteUniswap(baseAmount, weth, _token);

    // Make new observations in the pool to arrive to the end of the cardinality array
    (, , uint16 _observationIndexBefore, uint16 observationCardinality, , , ) = _pool.slot0();

    for (uint256 _index = _observationIndexBefore; _index < observationCardinality; _index++) {
      vm.prank(address(priceOracle));
      _poolManager.burn1();

      vm.prank(user1);
      _swap(weth, _token, 1 wei);
    }

    // Manipulate observation 0
    (uint16 _manipulatedIndex, uint16 _period) = _manipulatePool(_poolManager);
    priceOracle.applyCorrection(_pool, _manipulatedIndex, _period);

    advanceTime(2 minutes + 1);

    uint256 _quoteWithCorrections = priceOracle.quote(baseAmount, weth, _token, quotePeriod);
    assertRelApproxEq(_quoteWithCorrections, _quoteBefore, ONE_PERCENT);
  }

  function testE2ESameBlockCorrection() public {
    uint256 _quoteBefore = _quoteUniswap(baseAmount, weth, _token);
    // observations [x, x, x]
    // slot0 x, _observationIndex y - 1
    (, , uint16 _manipulatedIndex, , , , ) = _pool.slot0();
    uint256 _arbitrageBackAmount = _manipulatePoolTick(_poolManager);

    // observations [x, x, x]
    // slot0 M
    mineBlock();

    // Arbitrage back
    _arbitragePoolBack(_poolManager, _arbitrageBackAmount);
    // observations [x, x, x, M]
    // slot0 x, _observationIndex y

    vm.expectRevert(IPriceOracle.PriceOracleCorrections_AfterObservationCannotBeCalculatedOnSameBlock.selector);
    priceOracle.applyCorrection(_pool, _manipulatedIndex, 1);
    // reverted, need to wait 1 block to correct

    mineBlock();
    priceOracle.applyCorrection(_pool, _manipulatedIndex, 1);
    // observations [x, x, x, C, x]
    // slot0 x, _observationIndex y+1

    uint256 _arbitrageBackAmount2 = _manipulatePoolTick(_poolManager);
    // observations [x, x, x, C, x]
    // slot0 M, _observationIndex y+1

    mineBlock();

    // Arbitrage back
    _arbitragePoolBack(_poolManager, _arbitrageBackAmount2);
    // observations [x, x, x, C, x, M]
    // slot0 x, _observationIndex y+2

    vm.expectRevert(IPriceOracle.PriceOracleCorrections_AfterObservationCannotBeCalculatedOnSameBlock.selector);
    priceOracle.applyCorrection(_pool, _manipulatedIndex + 2, 1);
    // reverted, need to wait 1 block to correct

    mineBlock();
    priceOracle.applyCorrection(_pool, _manipulatedIndex + 2, 1);
    // observations [x, x, x, C, x, C]
    // slot0 x, _observationIndex y+3

    advanceTime(2 minutes + 1);

    uint256 _quoteWithCorrections = priceOracle.quote(baseAmount, weth, _token, quotePeriod);
    assertRelApproxEq(_quoteWithCorrections, _quoteBefore, ONE_PERCENT);
  }

  function testE2EAfterManipulationBurn1Observation0() public {
    uint256 _quoteBefore = _quoteUniswap(baseAmount, weth, _token);
    (, , uint16 _manipulatedIndex, , , , ) = _pool.slot0();
    // observations [x, x, x]
    // slot0 x, _observationIndex y - 1

    uint256 _arbitrageBackAmount = _manipulatePoolTick(_poolManager);
    // observations [x, x, x]
    // slot0 M

    mineBlock();

    _arbitragePoolBack(_poolManager, _arbitrageBackAmount);
    // observations [x, x, x, M]
    // slot0 x, _observationIndex y

    mineBlock();

    priceOracle.applyCorrection(_pool, _manipulatedIndex, 1);

    advanceTime(2 minutes + 1);

    uint256 _quoteWithCorrections = priceOracle.quote(baseAmount, weth, _token, quotePeriod);
    assertRelApproxEq(_quoteWithCorrections, _quoteBefore, ONE_PERCENT);
  }

  function testE2EPostAfterManipulationBurn1() public {
    uint256 _quoteBefore = _quoteUniswap(baseAmount, weth, _token);
    (, , uint16 _manipulatedIndex, , , , ) = _pool.slot0();
    // observations [x, x, x]
    // slot0 x, _observationIndex y - 1

    uint256 _arbitrageBackAmount = _manipulatePoolTick(_poolManager);
    // observations [x, x, x]
    // slot0 M

    mineBlock();

    _arbitragePoolBack(_poolManager, _arbitrageBackAmount);
    // observations [x, x, x, M]
    // slot0 x, _observationIndex y

    mineBlock();

    priceOracle.applyCorrection(_pool, _manipulatedIndex, 1);

    advanceTime(2 minutes + 1);

    uint256 _quoteWithCorrections = priceOracle.quote(baseAmount, weth, _token, quotePeriod);
    assertRelApproxEq(_quoteWithCorrections, _quoteBefore, ONE_PERCENT);
  }
}
