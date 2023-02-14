// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4 <0.9.0;

import 'solidity-utils/test/DSTestPlus.sol';
import '@contracts/LockManagerGovernor.sol';

contract LockManagerGovernorForTest is LockManagerGovernor {
  constructor(IPoolManager.LockManagerParams memory _lockManagerParams) LockManagerGovernor(_lockManagerParams) {}

  function deprecate() external {}

  function _deprecate() internal virtual override {
    LockManagerGovernorForTest(address(this)).deprecate();
  }

  function votingPowerMocked() public view returns (uint256 _totalVotes) {}

  function votingPower(
    address /*_user*/
  ) public view virtual override(GovernorMiniBravo, IGovernorMiniBravo) returns (uint256 _balance) {
    return LockManagerGovernorForTest(address(this)).votingPowerMocked();
  }

  function totalVotesMocked() public view returns (uint256 _totalVotes) {}

  function totalVotes() public view virtual override(GovernorMiniBravo, IGovernorMiniBravo) returns (uint256 _totalVotes) {
    return LockManagerGovernorForTest(address(this)).totalVotesMocked();
  }

  function cancelVotes(address _voter, uint256 _votes) public {
    _cancelVotes(_voter, _votes);
  }

  function transferVotes(
    address _sender,
    address _receiver,
    uint256 _votes
  ) public {
    _transferVotes(_sender, _receiver, _votes);
  }

  function getUserVotes(
    address _user,
    uint256 _method,
    uint256 _propId
  ) public view returns (uint256) {
    return _userVotes[_method][_propId][_user];
  }
}

abstract contract Base is DSTestPlus {
  LockManagerGovernorForTest governor;
  address admin = newAddress();

  uint256 totalVotes = 100 ether;
  uint256 userVotingPower = 40 ether; //Two users can get to quorum
  uint256 method = uint256(ILockManagerGovernor.Methods.Deprecate);

  IPoolManagerFactory mockPoolManagerFactory = IPoolManagerFactory(newAddress());

  function setUp() public virtual {
    vm.prank(admin);

    IPoolManager.LockManagerParams memory _lockManagerParams;
    _lockManagerParams.factory = mockPoolManagerFactory;
    _lockManagerParams.governance = admin;

    governor = new LockManagerGovernorForTest(_lockManagerParams);
    vm.mockCall(address(governor), abi.encodeWithSelector(LockManagerGovernorForTest.totalVotesMocked.selector), abi.encode(totalVotes));
    vm.mockCall(address(governor), abi.encodeWithSelector(LockManagerGovernorForTest.votingPowerMocked.selector), abi.encode(userVotingPower));
  }
}

contract UnitLockManagerGovernorCreateProposals is Base {
  function testDeprecateProposalAlreadyCreated() public {
    GovernorMiniBravo.Proposal memory _prop = governor.getLatest(method);
    assertEq(_prop.id, 1);
  }
}

contract UnitLockManagerGovernorAcceptProposal is Base {
  function setUp() public override {
    super.setUp();
  }

  function testAcceptDeprecateProposal() public {
    governor.acceptDeprecate();

    GovernorMiniBravo.Proposal memory _prop = governor.getLatest(method);
    assertEq(_prop.forVotes, userVotingPower);
  }
}

contract UnitLockManagerGovernorCancelProposal is Base {
  function testRevertCancelMigrateIfNonAdmin() public {
    vm.expectRevert(abi.encodeWithSelector(IRoles.Unauthorized.selector, address(this), governor.DEFAULT_ADMIN_ROLE()));
    governor.cancelProposal(method);
  }

  function testCancelMigrate() public {
    vm.prank(admin);
    governor.cancelProposal(method);
    GovernorMiniBravo.Proposal memory _prop = governor.getLatest(method);
    assertEq(_prop.open, false);
  }
}

contract UnitLockManagerGovernorCancelVoteProposal is Base {
  function setUp() public override {
    super.setUp();

    governor.acceptDeprecate();
  }

  function testCancelVoteProposal() public {
    governor.cancelVote(method);

    GovernorMiniBravo.Proposal memory _prop = governor.getLatest(method);
    assertEq(_prop.forVotes, 0);
  }
}

contract UnitGovernorMiniBravoExecuteProposal is Base {
  function setUp() public override {
    super.setUp();

    vm.prank(admin);
    governor.acceptDeprecate();
    governor.acceptDeprecate();
  }

  function testExecuteDeprecateProposal() public {
    governor.queue(method, abi.encode());
    vm.warp(block.timestamp + governor.executionTimelock());
    vm.expectCall(address(governor), abi.encodeWithSelector(LockManagerGovernorForTest.deprecate.selector));
    governor.execute(method, abi.encode());
  }
}

contract UnitGovernorMiniBravoTransferVotes is Base {
  function setUp() public override {
    super.setUp();
  }

  function testTransferVotesNoProposalsCreated() public {
    governor.transferVotes(address(this), admin, userVotingPower);
    GovernorMiniBravo.Proposal memory _prop = governor.getLatest(method);
    assertEq(_prop.forVotes, 0);
  }

  function testTransferVotesFromUserToUserWithoutVotesRemovesVotes() public {
    governor.acceptDeprecate();

    governor.transferVotes(address(this), admin, userVotingPower);
    GovernorMiniBravo.Proposal memory _prop = governor.getLatest(method);
    assertEq(_prop.forVotes, 0);
  }

  function testTransferVotesFromUserToUserWithVotesMovesVotes() public {
    governor.acceptDeprecate();

    vm.prank(admin);
    governor.acceptDeprecate();

    governor.transferVotes(address(this), admin, userVotingPower);

    GovernorMiniBravo.Proposal memory _prop = governor.getLatest(method);
    assertEq(_prop.forVotes, userVotingPower * 2);
    assertEq(governor.getUserVotes(admin, method, 1), userVotingPower * 2);
  }

  function testTransferVotesFromNonVoterToVoterAddsVotes() public {
    governor.acceptDeprecate();

    governor.transferVotes(admin, address(this), userVotingPower);
    GovernorMiniBravo.Proposal memory _prop = governor.getLatest(method);
    assertEq(_prop.forVotes, userVotingPower * 2);
  }

  function testTransferVotesFromNonVoterToNonVoterDoesNothing() public {
    governor.acceptDeprecate();

    address nonVoterOne = newAddress();
    address nonVoterTwo = newAddress();
    governor.transferVotes(nonVoterOne, nonVoterTwo, userVotingPower);
    GovernorMiniBravo.Proposal memory _prop = governor.getLatest(method);
    assertEq(_prop.forVotes, userVotingPower);
    assertEq(governor.getUserVotes(nonVoterOne, method, 1), 0);
    assertEq(governor.getUserVotes(nonVoterTwo, method, 1), 0);
  }

  function testRevertIfTransferringMoreVotesThanTheVoterHas() public {
    governor.acceptDeprecate();
    vm.expectRevert(abi.encodeWithSelector(ILockManagerGovernor.LockManager_ArithmeticUnderflow.selector));
    governor.transferVotes(address(this), admin, userVotingPower * 10000);
  }
}

contract UnitGovernorMiniBravoCancelVotes is Base {
  function setUp() public override {
    super.setUp();

    governor.acceptDeprecate();
  }

  function testCancelVotesRemovesPartialVotes() public {
    governor.cancelVotes(address(this), userVotingPower / 2);

    GovernorMiniBravo.Proposal memory _prop = governor.getLatest(method);
    assertEq(_prop.forVotes, userVotingPower / 2);
    assertEq(governor.getUserVotes(address(this), method, 1), userVotingPower / 2);
  }

  function testCancelVotesRemovesAllVotes() public {
    governor.cancelVotes(address(this), userVotingPower);

    GovernorMiniBravo.Proposal memory _prop = governor.getLatest(method);
    assertEq(_prop.forVotes, 0);
    assertEq(governor.getUserVotes(address(this), method, 1), 0);
  }
}
