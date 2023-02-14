// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4 <0.9.0;

import '@test/e2e/Common.sol';

contract E2ELockManagerGovernance is CommonE2EBase {
  uint256 lockAmount = 100 ether;
  uint256 method = uint256(ILockManagerGovernor.Methods.Deprecate);

  function testE2EUserAcceptAndCancelProposal() public {
    // Lock WETH in lock manager
    _lockWeth(user1, lockAmount);

    // First accept the proposal
    _acceptProposal(user1);

    // The total votes should be equals to locked from user1
    assertEq(_getVotes(), lockAmount);

    // Finally decline the proposal
    _cancelProposal(user1);

    // The total votes which accept the proposal should be 0
    assertEq(_getVotes(), 0);
  }

  function testE2ERevertIfQuorumNotReached() public {
    // Lock WETH in lock manager
    _lockWeth(user1, lockAmount);

    vm.expectRevert(abi.encodeWithSelector(IGovernorMiniBravo.QuorumNotReached.selector, method, 1));

    // Queue proposal, advance time and execute the deprecation
    lockManager.queue(method, abi.encode());
  }

  function testE2EQuorumReached() public {
    // Lock WETH in lock manager
    _lockWeth(user1, lockAmount);
    _lockWeth(user2, lockAmount);
    _lockWeth(user2, lockAmount);

    // User1 votes yes to deprecate lock manager
    _acceptProposal(user1);

    // The total votes should be equals to lock from user1
    assertEq(_getVotes(), lockAmount);

    // Should not reach the quorum
    assertFalse(lockManager.quorumReached(method));

    // User2 votes yes to deprecate lock manager
    _acceptProposal(user2);

    // The total votes which accept the proposal should be equals to all tokens locked
    assertEq(_getVotes(), lockAmount * 3);

    // Should reach the quorum
    assertTrue(lockManager.quorumReached(method));

    // Queue proposal, advance time and execute the deprecation
    lockManager.queue(method, abi.encode());
  }

  function testE2EUserVotesYesTransfer() public {
    // Lock WETH in lock manager
    _lockWeth(user1, lockAmount);
    _lockWeth(user2, lockAmount / 10);

    // Vote yes to deprecate lock manager
    _acceptProposal(user2);

    // Not enough votes to pass the proposal
    assertFalse(lockManager.quorumReached(method));

    // All votes are for user1
    assertEq(lockManager.votingPower(user1), lockAmount);

    // Transfer from user1 to user2
    vm.prank(user1);
    lockManager.transfer(user2, lockAmount);

    // The voting power of user2 is increased by the transfer of the user1
    assertEq(lockManager.votingPower(user2), (lockAmount * 110) / 100);
    assertEq(lockManager.votingPower(user1), 0);

    // The votes are for user2 and as user2 accept the proposal, the following shall be added to the votes
    assertEq(_getVotes(), lockManager.votingPower(user2));
  }

  function testE2EUserVotesNoTransferFrom() public {
    // Lock WETH in lock manager
    _lockWeth(user1, lockAmount);
    _lockWeth(user2, lockAmount / 10);

    // All votes are for user1
    assertEq(lockManager.votingPower(user1), lockAmount);

    // User1 votes yes to deprecate lock manager
    _acceptProposal(user1);

    // Not enough votes to pass the proposal
    assertTrue(lockManager.quorumReached(method));

    // Transfer from user1 to user2
    vm.prank(user1);
    lockManager.approve(address(this), lockAmount);
    lockManager.transferFrom(user1, user2, lockAmount);

    // The voting power of user2 is increased by the transfer of the user1
    assertEq(lockManager.votingPower(user2), (lockAmount * 110) / 100);
    assertEq(lockManager.votingPower(user1), 0);

    // The votes are for user2 and as user2 didn't accept the proposal, so the votes should be 0
    assertEq(_getVotes(), 0);
  }

  function testE2EUserVotesBurn() public {
    // Lock WETH in lock manager
    _lockWeth(user1, lockAmount);

    // Vote yes to deprecate lock manager
    _acceptProposal(user1);

    // Should reach the quorum
    assertTrue(lockManager.quorumReached(method));

    // User1 burn tokens
    vm.prank(user1);
    lockManager.burn(lockAmount);

    // The voting power of user1 is 0
    assertEq(lockManager.votingPower(user1), 0);

    // The total votes should be 0 because all amounts have been burned
    assertEq(lockManager.totalVotes(), 0);
  }

  function testE2EUsersAcceptAndExecuteProposal() public {
    // Lock WETH in lock manager
    _lockWeth(user1, lockAmount);

    // Lock WETH in lock manager
    _lockWeth(user2, lockAmount);

    // User1 accept the proposal
    _acceptProposal(user1);

    // User2 accept the proposal
    _acceptProposal(user2);

    // Should reach the quorum
    assertTrue(lockManager.quorumReached(method));

    // Queue the proposal
    lockManager.queue(method, '');

    // Wait for the proposal to become executable
    vm.warp(block.timestamp + 1 weeks);

    // Execute the deprecation
    lockManager.execute(method, abi.encode());

    // Lock manager should be deprecated
    assertTrue(lockManager.deprecated());
  }

  /// @notice Votes yes for deprecate lock manager
  function _acceptProposal(address user) internal {
    vm.prank(user);
    lockManager.acceptDeprecate();
  }

  /// @notice Votes no for deprecate lock manager
  function _cancelProposal(address user) internal {
    vm.prank(user);
    lockManager.cancelVote(method);
  }

  /// @notice Gets the total votes that accept the proposal
  function _getVotes() internal view returns (uint256 totalVotes) {
    IGovernorMiniBravo.Proposal memory proposal = lockManager.getLatest(method);
    totalVotes = proposal.forVotes;
  }
}
