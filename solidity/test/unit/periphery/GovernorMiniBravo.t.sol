// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4 <0.9.0;

import 'solidity-utils/test/DSTestPlus.sol';
import '@contracts/periphery/GovernorMiniBravo.sol';

contract GovernorMiniBravoForTest is GovernorMiniBravo {
  function setSuperAdmin(address _admin) public {
    _grantRole(DEFAULT_ADMIN_ROLE, _admin);
  }

  function propose(uint256 _method, bytes memory _parameters) public {
    _propose(_method, _parameters);
  }

  function acceptProposal(uint256 _method, bytes memory _parameters) public {
    _acceptProposal(_method, _parameters, msg.sender);
  }

  function publicExecute(uint256 _method, bytes memory _parameters) public {}

  function _execute(uint256 _method, bytes memory _parameters) internal override {
    GovernorMiniBravoForTest(address(this)).publicExecute(_method, _parameters);
  }

  function votingPowerMocked() public view returns (uint256 _totalVotes) {}

  function votingPower(
    address /*_user*/
  ) public view virtual override returns (uint256 _balance) {
    return GovernorMiniBravoForTest(address(this)).votingPowerMocked();
  }

  function totalVotesMocked() public view returns (uint256 _totalVotes) {}

  function totalVotes() public view virtual override returns (uint256 _totalVotes) {
    return GovernorMiniBravoForTest(address(this)).totalVotesMocked();
  }
}

abstract contract Base is DSTestPlus {
  address admin = label(newAddress(), 'admin');

  GovernorMiniBravoForTest governor;

  uint256 totalVotes = 100 ether;
  uint256 userVotingPower = 40 ether; //Two users can get to quorum

  function setUp() public virtual {
    governor = new GovernorMiniBravoForTest();
    governor.setSuperAdmin(admin);
    vm.mockCall(address(governor), abi.encodeWithSelector(GovernorMiniBravoForTest.totalVotesMocked.selector), abi.encode(totalVotes));
    vm.mockCall(address(governor), abi.encodeWithSelector(GovernorMiniBravoForTest.votingPowerMocked.selector), abi.encode(userVotingPower));
  }
}

contract UnitGovernorMiniBravoPropose is Base {
  uint256 method = 1;
  bytes params = abi.encode(admin);

  function testAdminAddsProposal() public {
    vm.prank(admin);
    governor.propose(method, params);
    GovernorMiniBravo.Proposal memory _prop = governor.getLatest(method);
    assertEq(_prop.id, 1);
    assertEq(_prop.params, params);
    assertTrue(_prop.open);
    assertEq(_prop.forVotes, 0);
  }

  function testAdminOverwriteProposal() public {
    vm.prank(admin);
    governor.propose(method, params);

    bytes memory secondParams = abi.encode('test');

    vm.prank(admin);
    governor.propose(method, secondParams);

    GovernorMiniBravo.Proposal memory _prop = governor.getLatest(method);
    assertEq(_prop.params, secondParams);
  }
}

contract UnitGovernorMiniBravoCancelProposal is Base {
  uint256 method = 1;
  bytes params = abi.encode(admin);

  function setUp() public override {
    super.setUp();

    vm.prank(admin);
    governor.propose(method, params);
  }

  function testCancelProposalClosesTheProposal() public {
    vm.prank(admin);
    governor.cancelProposal(method);
    GovernorMiniBravo.Proposal memory _prop = governor.getLatest(method);
    assertFalse(_prop.open);
  }

  function testRevertIfCancelOnClosedProposal() public {
    vm.prank(admin);
    governor.cancelProposal(method);

    vm.expectRevert(abi.encodeWithSelector(IGovernorMiniBravo.ProposalClosed.selector, method, 1));

    vm.prank(admin);
    governor.cancelProposal(method);
  }
}

contract UnitGovernorMiniBravoAcceptProposal is Base {
  uint256 method = 1;
  bytes params = abi.encode(admin);

  function setUp() public override {
    super.setUp();

    vm.prank(admin);
    governor.propose(method, params);
  }

  function testAcceptProposal() public {
    governor.acceptProposal(method, params);
    GovernorMiniBravo.Proposal memory _prop = governor.getLatest(method);
    assertEq(_prop.forVotes, userVotingPower);
  }

  function testRevertIfDoubleAcceptProposal() public {
    governor.acceptProposal(method, params);
    vm.expectRevert(abi.encodeWithSelector(IGovernorMiniBravo.AlreadyVoted.selector, method, 1));

    governor.acceptProposal(method, params);
  }

  function testRevertIfWrongProposalParameters() public {
    bytes memory _wrongParams = abi.encode('wrong');
    vm.expectRevert(abi.encodeWithSelector(IGovernorMiniBravo.ParametersMismatch.selector, method, params, _wrongParams));
    governor.acceptProposal(method, _wrongParams);
  }
}

contract UnitGovernorMiniBravoCancelVoteProposal is Base {
  uint256 method = 1;
  bytes params = abi.encode(admin);

  function setUp() public override {
    super.setUp();

    vm.prank(admin);
    governor.propose(method, params);
    governor.acceptProposal(method, params);
  }

  function testCancelVoteProposal() public {
    governor.cancelVote(method);
    GovernorMiniBravo.Proposal memory _prop = governor.getLatest(method);
    assertEq(_prop.forVotes, 0);
  }

  function testRevertIfCancelVoteWithoutHavingVoted() public {
    address _randomUser = newAddress();
    vm.expectRevert(abi.encodeWithSelector(IGovernorMiniBravo.NoVotes.selector));
    vm.prank(_randomUser);
    governor.cancelVote(method);
  }
}

contract UnitGovernorMiniBravoQueueProposal is Base {
  uint256 method = 1;
  bytes params = abi.encode(admin);

  function setUp() public override {
    super.setUp();

    vm.prank(admin);
    governor.propose(method, params);
    vm.prank(admin);
    governor.acceptProposal(method, params);
  }

  function testQueueProposal() public {
    governor.acceptProposal(method, params);
    governor.queue(method, params);
    GovernorMiniBravo.Proposal memory _prop = governor.getLatest(method);
    assertEq(_prop.timelockExpiry, block.timestamp + governor.executionTimelock());
  }

  function testRevertQueueProposalIfProposalIsClosed() public {
    governor.acceptProposal(method, params);
    vm.prank(admin);
    governor.cancelProposal(method);

    vm.expectRevert(abi.encodeWithSelector(IGovernorMiniBravo.QuorumNotReached.selector, method, 1));
    governor.queue(method, params);
  }

  function testRevertQueueProposalIfProposalNotEnoughVotes() public {
    vm.expectRevert(abi.encodeWithSelector(IGovernorMiniBravo.QuorumNotReached.selector, method, 1));
    governor.queue(method, params);
  }

  function testRevertQueueProposalIfInvalidProposalParameters() public {
    governor.acceptProposal(method, params);
    bytes memory _wrongParams = abi.encode('wrong');
    vm.expectRevert(abi.encodeWithSelector(IGovernorMiniBravo.ParametersMismatch.selector, method, params, _wrongParams));
    governor.queue(method, _wrongParams);
  }

  function testRevertQueueProposalIfAlreadyQueued() public {
    governor.acceptProposal(method, params);
    governor.queue(method, params);
    vm.expectRevert(abi.encodeWithSelector(IGovernorMiniBravo.ProposalAlreadyQueued.selector, method, 1));
    governor.queue(method, params);
  }
}

contract UnitGovernorMiniBravoExecuteProposal is Base {
  uint256 method = 1;
  bytes params = abi.encode(admin);

  function setUp() public override {
    super.setUp();

    vm.prank(admin);
    governor.propose(method, params);
    vm.prank(admin);
    governor.acceptProposal(method, params);
  }

  function testExecuteProposal() public {
    governor.acceptProposal(method, params);
    governor.queue(method, params);
    vm.warp(block.timestamp + governor.executionTimelock());
    vm.expectCall(address(governor), abi.encodeWithSelector(GovernorMiniBravoForTest.publicExecute.selector, method, params));
    governor.execute(method, params);
  }

  function testRevertIfProposalIsClosed() public {
    governor.acceptProposal(method, params);
    governor.queue(method, params);
    vm.warp(block.timestamp + governor.executionTimelock());
    vm.prank(admin);
    governor.cancelProposal(method);

    vm.expectRevert(abi.encodeWithSelector(IGovernorMiniBravo.ProposalNotExecutable.selector, method, 1));
    governor.execute(method, params);
  }

  function testRevertIfProposalNotQueued() public {
    governor.acceptProposal(method, params);

    vm.expectRevert(abi.encodeWithSelector(IGovernorMiniBravo.ProposalNotExecutable.selector, method, 1));
    governor.execute(method, params);
  }

  function testRevertIfTimelockNotExpired() public {
    governor.acceptProposal(method, params);
    governor.queue(method, params);
    vm.warp(block.timestamp + governor.executionTimelock() / 2);

    vm.expectRevert(abi.encodeWithSelector(IGovernorMiniBravo.ProposalNotExecutable.selector, method, 1));
    governor.execute(method, params);
  }

  function testRevertIfInvalidProposalParameters() public {
    governor.acceptProposal(method, params);
    governor.queue(method, params);
    vm.warp(block.timestamp + governor.executionTimelock());
    bytes memory _wrongParams = abi.encode('wrong');
    vm.expectRevert(abi.encodeWithSelector(IGovernorMiniBravo.ParametersMismatch.selector, method, params, _wrongParams));
    governor.execute(method, _wrongParams);
  }
}

contract UnitGovernorIsExecutable is Base {
  uint256 method = 1;
  bytes params = abi.encode(admin);

  function setUp() public override {
    super.setUp();

    vm.prank(admin);
    governor.propose(method, params);
    vm.prank(admin);
    governor.acceptProposal(method, params);
  }

  function testIsProposalExecutable() public {
    governor.acceptProposal(method, params);
    governor.queue(method, params);
    vm.warp(block.timestamp + governor.executionTimelock());
    assertEq(governor.isExecutable(method), true);
  }

  function testIsProposalIsNotExecutable() public {
    governor.acceptProposal(method, params);
    governor.queue(method, params);
    assertEq(governor.isExecutable(method), false);
  }
}
