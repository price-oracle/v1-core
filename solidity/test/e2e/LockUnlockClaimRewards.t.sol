// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4 <0.9.0;

import '@test/e2e/Common.sol';

contract E2ELockAndClaimRewards is CommonE2EBase {
  uint256 user1LockAmount = 1 ether;
  uint256 rewardsToAdd = 50 ether;
  uint256 user1WethEarnings;
  uint256 user2WethEarnings;
  uint256 rewardsDuration;

  function testMultipleLockAndClaimRewards() public {
    _lockWeth(user1, user1LockAmount);
    _addRewards(rewardsToAdd, 0);

    (user1WethEarnings, ) = _claimableRewards(user1);
    (user2WethEarnings, ) = _claimableRewards(user2);
    assertApproxEqAbs(user1WethEarnings, rewardsToAdd, DELTA);
    assertApproxEqAbs(user2WethEarnings, 0, DELTA);

    _lockWeth(user2, user1LockAmount);
    _addRewards(rewardsToAdd, 0);

    (user1WethEarnings, ) = _claimableRewards(user1);
    (user2WethEarnings, ) = _claimableRewards(user2);
    assertApproxEqAbs(user1WethEarnings, rewardsToAdd + rewardsToAdd / 2, DELTA);
    assertApproxEqAbs(user2WethEarnings, rewardsToAdd / 2, DELTA);

    _claimRewards(user1);

    (user1WethEarnings, ) = _claimableRewards(user1);
    (user2WethEarnings, ) = _claimableRewards(user2);
    assertApproxEqAbs(user1WethEarnings, 0, DELTA);
    assertApproxEqAbs(user2WethEarnings, rewardsToAdd / 2, DELTA);

    _lockWeth(user2, user1LockAmount);
    _addRewards(rewardsToAdd, 0);

    (user1WethEarnings, ) = _claimableRewards(user1);
    (user2WethEarnings, ) = _claimableRewards(user2);
    assertApproxEqAbs(user1WethEarnings, rewardsToAdd / 3, DELTA);
    assertApproxEqAbs(user2WethEarnings, (rewardsToAdd * 2) / 3 + rewardsToAdd / 2, DELTA);
  }

  function testRewardsOnPriceLockedTrading() public {
    _lockWeth(user1, user1LockAmount);
    _addRewards(rewardsToAdd, 0);

    (user1WethEarnings, ) = _claimableRewards(user1);
    (user2WethEarnings, ) = _claimableRewards(user2);
    assertApproxEqAbs(user1WethEarnings, rewardsToAdd, DELTA);
    assertApproxEqAbs(user2WethEarnings, 0, DELTA);

    vm.prank(user1);
    lockManager.transfer(user2, user1LockAmount);

    (user1WethEarnings, ) = _claimableRewards(user1);
    (user2WethEarnings, ) = _claimableRewards(user2);
    assertApproxEqAbs(user1WethEarnings, rewardsToAdd, DELTA);
    assertApproxEqAbs(user2WethEarnings, 0, DELTA);

    _addRewards(rewardsToAdd, 0);

    (user1WethEarnings, ) = _claimableRewards(user1);
    (user2WethEarnings, ) = _claimableRewards(user2);
    assertApproxEqAbs(user1WethEarnings, rewardsToAdd, DELTA);
    assertApproxEqAbs(user2WethEarnings, rewardsToAdd, DELTA);
  }

  function testSplittingRewards() public {
    _lockWeth(user1, user1LockAmount);
    advanceTime(rewardsDuration);
    _addRewards(rewardsToAdd, rewardsToAdd);

    _lockWeth(user2, user1LockAmount * 2);
    advanceTime(rewardsDuration);
    _addRewards(rewardsToAdd, rewardsToAdd);

    (user1WethEarnings, ) = _claimRewards(user1);
    (user2WethEarnings, ) = _claimRewards(user2);

    assertApproxEqAbs(user1WethEarnings, rewardsToAdd / 3 + rewardsToAdd, DELTA);
    assertApproxEqAbs(user2WethEarnings, (rewardsToAdd * 2) / 3, DELTA);
  }

  function testUserDepositAfterRewardsGetsNoRewards() public {
    // user1 locks, rewards are added, and wait a total duration
    _lockWeth(user1, 1 ether);
    _addRewards(rewardsToAdd, rewardsToAdd);
    advanceTime(rewardsDuration);

    // user2 locks and wait a total duration
    _lockWeth(user2, 1 ether);
    advanceTime(rewardsDuration);

    // user1 should get all of the rewards
    (user1WethEarnings, ) = _claimRewards(user1);
    assertApproxEqAbs(user1WethEarnings, rewardsToAdd, DELTA);

    // user2 shouldn't get anything
    vm.expectRevert(ILockManager.LockManager_NoRewardsToClaim.selector);
    _claimRewards(user2);
  }
}
