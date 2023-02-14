// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4 <0.9.0;

import '@test/e2e/Common.sol';

contract E2EBribe is CommonE2EBase {
  function setUp() public override {
    super.setUp();
    vm.prank(user1);
    dai.approve(address(bribe), type(uint256).max);
    vm.prank(user2);
    lockManager.approve(address(bribe), type(uint256).max);
    _lockWeth(user2, weth.balanceOf(user2));
  }

  function testCreateBribesAndClaim() public {
    /// Creates 1st period with depositing
    vm.prank(user2);
    bribe.deposit(lockManager, 1 ether);

    /// Initializes and starts the bribe period
    vm.prank(user1);
    bribe.createBribe(lockManager, dai, 100 ether);

    /// Create another bribe for the next period
    vm.prank(user1);
    bribe.createBribe(lockManager, dai, 100 ether);

    /// Create another bribe for the next period (will add the amount to the existing one)
    vm.prank(user1);
    bribe.createBribe(lockManager, dai, 100 ether);

    /// Warp to finish the 1st bribe
    vm.warp(block.timestamp + 8 days);

    /// Creates another bribe, this should be in the 3rd bribe period
    vm.prank(user1);
    bribe.createBribe(lockManager, dai, 100 ether);

    /// User claims
    IERC20[] memory _tokens = new IERC20[](1);
    _tokens[0] = dai;
    vm.prank(user2);
    bribe.claimRewards(lockManager, _tokens, 1, 2);
  }

  function testClaimEarlierPeriodRewardsAfterClaimingLastRewards() public {
    vm.prank(user2);
    bribe.deposit(lockManager, 1 ether);

    /// 1st Bribe
    vm.prank(user1);
    bribe.createBribe(lockManager, dai, 100 ether);

    vm.warp(block.timestamp + 8 days);

    /// 2nd Bribe
    vm.prank(user1);
    bribe.createBribe(lockManager, dai, 100 ether);

    vm.warp(block.timestamp + 8 days);

    /// 3rd Bribe
    vm.prank(user1);
    bribe.createBribe(lockManager, dai, 100 ether);

    vm.warp(block.timestamp + 8 days);

    IERC20[] memory _tokens = new IERC20[](1);
    _tokens[0] = dai;

    uint256 _userBalance = dai.balanceOf(user2);

    /// Claim 3rd bribe rewards
    vm.prank(user2);
    bribe.claimRewards(lockManager, _tokens, 3, 3);

    assertEq(_userBalance + 100 ether, dai.balanceOf(user2));

    /// Claim 1 and 2 bribe rewards
    vm.prank(user2);
    bribe.claimRewards(lockManager, _tokens, 1, 2);

    assertEq(_userBalance + 300 ether, dai.balanceOf(user2));
  }
}
