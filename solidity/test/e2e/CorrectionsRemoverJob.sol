// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4 <0.9.0;

import '@test/e2e/Common.sol';
import '@contracts/jobs/CorrectionsRemoverJob.sol';

contract E2ECorrectionsRemoverJob is CommonE2EBase {
  CorrectionsRemoverJob correctionsRemoverJob;
  IPoolManager _poolManager;
  IUniswapV3Pool _invalidPool = IUniswapV3Pool(newAddress());
  IUniswapV3Pool _pool;

  function setUp() public override {
    super.setUp();

    _poolManager = lockManager.POOL_MANAGER();
    _pool = _poolManager.POOL();

    // Initialize the job
    correctionsRemoverJob = new CorrectionsRemoverJob(poolManagerFactory, governance);
    label(address(correctionsRemoverJob), 'CorrectionsRemoverJob');
  }

  function testE2ERemoveCorrections() public {
    vm.startPrank(keeper);

    // The job reverts if called with a random pool not supported by PRICE
    vm.expectRevert(abi.encodeWithSelector(ICorrectionsRemoverJob.CorrectionsRemoverJob_InvalidPool.selector, _invalidPool));
    correctionsRemoverJob.work(_invalidPool);

    // Reverts if there are no corrections to remove
    vm.expectRevert(abi.encodeWithSelector(IPriceOracle.PriceOracleCorrections_NoCorrectionsToRemove.selector));
    correctionsRemoverJob.work(_pool);

    vm.stopPrank();

    uint256 _oldestCorrection = priceOracle.getOldestCorrectionTimestamp(_pool);

    // Manipulate the pool multiple times in a row
    uint16 _manipulatedIndex;
    uint16 _period;
    for (uint256 _index = 1; _index < 50; _index++) {
      advanceTime(BLOCK_TIME * _index + 1);

      (_manipulatedIndex, _period) = _manipulatePool(_poolManager);
      priceOracle.applyCorrection(_pool, _manipulatedIndex, _period);
    }

    // Now we need to mine enough blocks for the corrections to be older than priceOracle.MAX_CORRECTION_AGE()
    advanceTime(priceOracle.MAX_CORRECTION_AGE());
    mineBlock();

    // Approve and fund the job
    _setUpJob(correctionsRemoverJob);

    // Manipulate the pool
    (_manipulatedIndex, _period) = _manipulatePool(_poolManager);

    // Apply a correction
    priceOracle.applyCorrection(_pool, _manipulatedIndex, _period);

    // Run the job
    vm.prank(keeper);
    correctionsRemoverJob.work(_pool);

    // There should be one correction for the pool, the newest
    assertEq(priceOracle.poolCorrectionsCount(_pool), 1);
    assertGt(priceOracle.getOldestCorrectionTimestamp(_pool), _oldestCorrection);

    vm.stopPrank();
  }
}
