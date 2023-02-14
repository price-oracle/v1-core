// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4 <0.9.0;

import 'uni-v3-periphery/libraries/OracleLibrary.sol';
import 'solidity-utils/interfaces/IGovernable.sol';
import 'solidity-utils/test/DSTestPlus.sol';

import '@interfaces/IPoolManager.sol';
import '@contracts/jobs/FeeCollectorJob.sol';

contract FeeCollectorJobForTest is FeeCollectorJob {
  address public upkeepKeeperForTest;

  constructor(IPoolManagerFactory _poolManagerFactory, address _governor) FeeCollectorJob(_poolManagerFactory, _governor) {}

  function pauseForTest() external {
    paused = true;
  }

  modifier upkeep(address _keeper) override {
    upkeepKeeperForTest = _keeper;
    _;
  }
}

contract Base is DSTestPlus {
  address keeper = label(address(100), 'keeper');
  address governor = label(address(101), 'governor');

  IKeep3r keep3r;
  FeeCollectorJobForTest job;

  IPoolManager mockPoolManager = IPoolManager(mockContract(address(200), 'mockPoolManager'));
  ILockManager mockLockManager = ILockManager(mockContract(address(201), 'mockLockManager'));
  IPoolManagerFactory mockPoolManagerFactory = IPoolManagerFactory(mockContract(address(202), 'mockPoolManagerFactory'));

  function setUp() public virtual {
    job = new FeeCollectorJobForTest(mockPoolManagerFactory, governor);
    keep3r = job.keep3r();

    vm.mockCall(address(mockPoolManagerFactory), abi.encodeWithSelector(IPoolManagerFactory.isChild.selector), abi.encode(true));
    vm.mockCall(address(mockPoolManager), abi.encodeWithSelector(IPoolManager.lockManager.selector), abi.encode(mockLockManager));
  }
}

contract UnitFeeCollectorJobWorkLockManager is Base {
  event WorkedLockManager(ILockManager _lockManager, IStrategy.Position[] _positions);

  function testUpkeep(IStrategy.Position[] calldata positions) external {
    vm.prank(keeper);
    job.work(mockPoolManager, positions);

    assertEq(job.upkeepKeeperForTest(), keeper);
  }

  function testRevertIfPaused(IStrategy.Position[] calldata positions) external {
    job.pauseForTest();

    vm.expectRevert(IPausable.Paused.selector);

    job.work(mockPoolManager, positions);
  }

  function testRevertIfInvalidPoolManager(IStrategy.Position[] calldata positions) external {
    vm.mockCall(
      address(mockPoolManagerFactory),
      abi.encodeWithSelector(IPoolManagerFactory.isChild.selector, mockPoolManager),
      abi.encode(false)
    );

    vm.expectRevert(abi.encodeWithSelector(IFeeCollectorJob.FeeCollectorJob_InvalidPoolManager.selector, mockPoolManager));

    job.work(mockPoolManager, positions);
  }

  function testCollectFeesLockManagerForJob(IStrategy.Position[] calldata positions) external {
    vm.expectCall(address(mockLockManager), abi.encodeWithSelector(ILockManager.collectFees.selector));
    job.work(mockPoolManager, positions);
  }

  function testEmitEvent(IStrategy.Position[] calldata positions) external {
    vm.expectEmit(false, false, false, true);
    emit WorkedLockManager(mockLockManager, positions);

    job.work(mockPoolManager, positions);
  }
}

contract UnitFeeCollectorJobWorkPoolManager is Base {
  event WorkedPoolManager(IPoolManager _poolManager);

  function testUpkeep() external {
    vm.prank(keeper);
    job.work(mockPoolManager);

    assertEq(job.upkeepKeeperForTest(), keeper);
  }

  function testRevertIfPaused() external {
    job.pauseForTest();

    vm.expectRevert(IPausable.Paused.selector);

    job.work(mockPoolManager);
  }

  function testRevertIfInvalidPoolManager() external {
    vm.mockCall(
      address(mockPoolManagerFactory),
      abi.encodeWithSelector(IPoolManagerFactory.isChild.selector, mockPoolManager),
      abi.encode(false)
    );

    vm.expectRevert(abi.encodeWithSelector(IFeeCollectorJob.FeeCollectorJob_InvalidPoolManager.selector, mockPoolManager));

    job.work(mockPoolManager);
  }

  function testCollectFeesPoolManagerForJob() external {
    vm.expectCall(address(mockPoolManager), abi.encodeWithSelector(IPoolManager.collectFees.selector));
    job.work(mockPoolManager);
  }

  function testEmitEvent() external {
    vm.expectEmit(false, false, false, true);
    emit WorkedPoolManager(mockPoolManager);

    job.work(mockPoolManager);
  }
}

contract UnitFeeCollectorJobSetCollectMultiplier is Base {
  event CollectMultiplierSet(uint256 collectMultiplier);

  function testRevertIfNotGovernor(uint256 collectMultiplier) public {
    vm.expectRevert(abi.encodeWithSelector(IGovernable.OnlyGovernor.selector));
    job.setCollectMultiplier(collectMultiplier);
  }

  function testSetMultiplier(uint256 collectMultiplier) external {
    vm.prank(governor);
    job.setCollectMultiplier(collectMultiplier);

    assertEq(collectMultiplier, job.collectMultiplier());
  }

  function testEmitCollectMultiplier(uint256 collectMultiplier) external {
    vm.expectEmit(false, false, false, true);
    emit CollectMultiplierSet(collectMultiplier);

    vm.prank(governor);
    job.setCollectMultiplier(collectMultiplier);
  }
}
