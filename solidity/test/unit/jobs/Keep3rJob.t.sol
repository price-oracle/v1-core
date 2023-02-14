// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4 <0.9.0;

import 'keep3r/interfaces/IKeep3r.sol';
import 'keep3r/interfaces/peripherals/IKeep3rJobs.sol';
import 'solidity-utils/interfaces/IGovernable.sol';
import 'solidity-utils/test/DSTestPlus.sol';

import '@contracts/jobs/Keep3rJob.sol';

contract Keep3rJobForTest is Keep3rJob {
  constructor(address _governor) Governable(_governor) {}

  function upkeepForTest() external upkeep(msg.sender) {}
}

contract Base is DSTestPlus {
  address governor = label(address(100), 'governor');
  address keeper = label(address(101), 'keeper');

  IKeep3r keep3r;
  Keep3rJobForTest job;

  function setUp() public virtual {
    job = new Keep3rJobForTest(governor);
    keep3r = IKeep3r(mockContract(address(job.keep3r()), 'keep3r'));
  }
}

contract UnitKeep3rJobSetKeep3r is Base {
  event Keep3rSet(IKeep3r keep3r);

  function testRevertIfNotGovernor(IKeep3r keep3r) public {
    vm.expectRevert(abi.encodeWithSelector(IGovernable.OnlyGovernor.selector));
    job.setKeep3r(keep3r);
  }

  function testSetKeep3r(IKeep3r keep3r) public {
    vm.prank(governor);
    job.setKeep3r(keep3r);

    assertEq(address(job.keep3r()), address(keep3r));
  }

  function testEmitEvent(IKeep3r keep3r) public {
    vm.expectEmit(false, false, false, true);
    emit Keep3rSet(keep3r);

    vm.prank(governor);
    job.setKeep3r(keep3r);
  }
}

contract UnitKeep3rJobSetKeep3rRequirements is Base {
  event Keep3rRequirementsSet(IERC20 bond, uint256 minBond, uint256 earnings, uint256 age);

  function testRevertIfNotGovernor(
    IERC20 bond,
    uint256 minBond,
    uint256 earnings,
    uint256 age
  ) public {
    vm.expectRevert(abi.encodeWithSelector(IGovernable.OnlyGovernor.selector));
    job.setKeep3rRequirements(bond, minBond, earnings, age);
  }

  function testSetRequirements(
    IERC20 bond,
    uint256 minBond,
    uint256 earnings,
    uint256 age
  ) public {
    vm.prank(governor);
    job.setKeep3rRequirements(bond, minBond, earnings, age);

    assertEq(address(job.requiredBond()), address(bond));
    assertEq(job.requiredMinBond(), minBond);
    assertEq(job.requiredEarnings(), earnings);
    assertEq(job.requiredAge(), age);
  }

  function testEmitEvent(
    IERC20 bond,
    uint256 minBond,
    uint256 earnings,
    uint256 age
  ) public {
    vm.expectEmit(false, false, false, true);
    emit Keep3rRequirementsSet(bond, minBond, earnings, age);

    vm.prank(governor);
    job.setKeep3rRequirements(bond, minBond, earnings, age);
  }
}

contract UnitKeep3rJobUpkeep is Base {
  function setUp() public override {
    super.setUp();

    vm.mockCall(address(keep3r), abi.encodeWithSelector(IKeep3rJobWorkable.worked.selector, keeper), abi.encode());
  }

  function testCheckKeeperValidity(
    IERC20 bond,
    uint256 minBond,
    uint256 earnings,
    uint256 age
  ) public {
    vm.prank(governor);
    job.setKeep3rRequirements(bond, minBond, earnings, age);

    vm.mockCall(
      address(keep3r),
      abi.encodeWithSelector(IKeep3rJobWorkable.isBondedKeeper.selector, keeper, bond, minBond, earnings, age),
      abi.encode(true)
    );
    vm.expectCall(address(keep3r), abi.encodeWithSelector(IKeep3rJobWorkable.isBondedKeeper.selector, keeper, bond, minBond, earnings, age));

    vm.prank(keeper);
    job.upkeepForTest();
  }

  function testRevertIfInvalidKeeper() public {
    vm.mockCall(address(keep3r), abi.encodeWithSelector(IKeep3rJobWorkable.isBondedKeeper.selector), abi.encode(false));

    vm.expectRevert(abi.encodeWithSelector(IKeep3rJob.InvalidKeeper.selector));
    job.upkeepForTest();
  }

  function testCallWorked() public {
    vm.mockCall(address(keep3r), abi.encodeWithSelector(IKeep3rJobWorkable.isBondedKeeper.selector), abi.encode(true));
    vm.expectCall(address(keep3r), abi.encodeWithSelector(IKeep3rJobWorkable.worked.selector, keeper));

    vm.prank(keeper);
    job.upkeepForTest();
  }
}
