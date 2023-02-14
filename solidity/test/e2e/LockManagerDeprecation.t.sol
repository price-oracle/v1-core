// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4 <0.9.0;

import '@test/e2e/Common.sol';

contract E2ELockManagerDeprecation is CommonE2EBase {
  uint256 user1LockAmount = 1000 ether;
  uint256 wethToAdd = 50 ether;
  uint256 tokenToAdd = 25 ether;
  uint256 method = uint256(ILockManagerGovernor.Methods.Deprecate);

  function testLockManagerDeprecation() public {
    _lockWeth(user1, user1LockAmount);
    _addRewards(wethToAdd, tokenToAdd);

    // Add concentrated positions and check that WETH balance decreases
    uint256 balanceBeforeMint = weth.balanceOf(address(lockManager));
    lockManager.mintPosition();
    assertEq(lockManager.getPositionsCount(), 1);
    uint256 balanceAfterMint = weth.balanceOf(address(lockManager));
    assertGt(balanceBeforeMint, balanceAfterMint);
    assertEq(balanceBeforeMint - balanceAfterMint, lockManager.concentratedWeth());

    // Vote yes for deprecation from user1 and check that quorum was reached
    vm.prank(user1);
    lockManager.acceptDeprecate();
    assertTrue(lockManager.quorumReached(method));

    // Queue proposal, advance time and execute the deprecation
    lockManager.queue(method, abi.encode());
    vm.warp(block.timestamp + lockManager.executionTimelock());
    lockManager.execute(method, abi.encode());
    assertTrue(lockManager.deprecated());

    // Unwind the lock manager
    lockManager.unwind(1);

    // Check that balance is now the same as before
    assertApproxEqAbs(weth.balanceOf(address(lockManager)), balanceBeforeMint, DELTA);

    // Check that withdrawal data is correct
    (bool withdrawalsEnabled, uint256 totalWeth, ) = lockManager.withdrawalData();
    assertTrue(withdrawalsEnabled);
    assertApproxEqAbs(totalWeth, user1LockAmount, DELTA);

    // Call withdraw and assert that balance increased
    uint256 balanceBeforeWithdraw = weth.balanceOf(user1);
    vm.prank(user1);
    lockManager.withdraw(user1);
    uint256 balanceAfterWithdraw = weth.balanceOf(user1);
    assertApproxEqAbs(balanceBeforeWithdraw, balanceAfterWithdraw - user1LockAmount - wethToAdd, DELTA);

    // Deploy the new lock manager
    vm.prank(user1);
    poolManagerDai.deprecateLockManager();
    ILockManager newLockManager = poolManagerDai.lockManager();
    assertEq(address(poolManagerDai.deprecatedLockManagers(0)), address(lockManager));
    assertTrue(address(lockManager) != address(newLockManager));

    // Verify the new lock manager
    assertEq(address(newLockManager.POOL_MANAGER()), address(poolManagerDai));
    assertEq(address(newLockManager.POOL()), address(lockManager.POOL()));
    assertEq(address(newLockManager.TOKEN()), address(lockManager.TOKEN()));
    assertEq(newLockManager.FEE(), poolFee);
  }
}
