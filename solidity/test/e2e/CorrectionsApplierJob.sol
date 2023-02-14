// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4 <0.9.0;

import '@test/e2e/Common.sol';
import '@contracts/jobs/CorrectionsApplierJob.sol';

contract E2ECorrectionsApplierJob is CommonE2EBase {
  CorrectionsApplierJob correctionsApplierJob;
  IPoolManager _poolManager;
  IUniswapV3Pool _invalidPool = IUniswapV3Pool(newAddress());
  IUniswapV3Pool _pool;
  IERC20 _token;

  uint256 constant ONE_PERCENT = 1e18 / 100;
  uint128 internal baseAmount = 1 ether;

  function setUp() public override {
    super.setUp();

    _poolManager = lockManager.POOL_MANAGER();
    _pool = _poolManager.POOL();
    _token = _poolManager.TOKEN();

    // Initialize the job
    correctionsApplierJob = new CorrectionsApplierJob(poolManagerFactory, governance);
    label(address(correctionsApplierJob), 'CorrectionsApplierJob');

    // Approve and fund the job
    _setUpJob(correctionsApplierJob);
  }

  function testE2EApplyCorrection() public {
    uint256 _quoteBefore = _quoteUniswap(baseAmount, weth, _token);

    vm.startPrank(keeper);

    // The job reverts if called with a random pool not supported by PRICE
    vm.expectRevert(abi.encodeWithSelector(ICorrectionsApplierJob.CorrectionsApplierJob_InvalidPool.selector, _invalidPool));
    correctionsApplierJob.work(_invalidPool, 0, 0);

    vm.stopPrank();

    mineBlock();

    // Manipulate the pool
    (uint16 _manipulatedIndex, uint16 _period) = _manipulatePool(_poolManager);

    // Run the job
    vm.prank(keeper);
    correctionsApplierJob.work(_pool, _manipulatedIndex, _period);

    // There should be one correction for this pool
    assertEq(priceOracle.poolCorrectionsCount(_pool), 1);

    // We need to get the correction in range of the quoting
    advanceTime(2 minutes + 1);

    uint256 _quoteAfter = _quoteUniswap(baseAmount, weth, _token);
    assertGt(_quoteBefore, _quoteAfter);

    uint256 _quoteWithCorrections = priceOracle.quote(baseAmount, weth, _token, 10 minutes);
    assertRelApproxEq(_quoteWithCorrections, _quoteBefore, ONE_PERCENT);
  }

  function testE2EGasMultiplier() public {
    // Set an extremely high gas multiplier
    vm.prank(governance);
    correctionsApplierJob.setGasMultiplier(2_000_000);

    // The job has the full amount of credits initially
    uint256 _creditsBefore = keep3r.jobLiquidityCredits(address(correctionsApplierJob));

    // Manipulate the pool
    (uint16 _manipulatedIndex, uint16 _period) = _manipulatePool(_poolManager);

    // Run the job
    vm.prank(keeper);
    correctionsApplierJob.work(_pool, _manipulatedIndex, _period);

    // There should be one correction for this pool
    assertEq(priceOracle.poolCorrectionsCount(_pool), 1);

    // The job should nearly deplete its credits, leaving only 5% of the initial amount
    uint256 _creditsAfter = keep3r.jobLiquidityCredits(address(correctionsApplierJob));
    assertRelApproxEq(_creditsBefore, _creditsAfter, (_creditsBefore * 5) / 100);
  }
}
