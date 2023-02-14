// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4 <0.9.0;

import 'uni-v3-periphery/libraries/OracleLibrary.sol';
import 'solidity-utils/test/DSTestPlus.sol';

import '@contracts/jobs/PositionBurnerJob.sol';

contract PositionBurnerJobForTest is PositionBurnerJob {
  address public upkeepKeeperForTest;

  constructor(IPoolManagerFactory _poolManagerFactory, address _governor) PositionBurnerJob(_poolManagerFactory, _governor) {}

  function setPausedForTest(bool _paused) external {
    paused = _paused;
  }

  modifier upkeep(address _keeper) override {
    upkeepKeeperForTest = _keeper;
    _;
  }
}

contract Base is DSTestPlus {
  address keeper = label(newAddress(), 'keeper');
  address governor = label(newAddress(), 'governor');

  IKeep3r keep3r;
  IPoolManager mockPoolManager = IPoolManager(mockContract('mockPoolManager'));
  ILockManager mockLockManager = ILockManager(mockContract('mockLockManager'));
  IPoolManagerFactory mockPoolManagerFactory = IPoolManagerFactory(mockContract('mockPoolManagerFactory'));

  PositionBurnerJobForTest job;
  IStrategy.Position positionToBurn = IStrategy.Position({lowerTick: 0, upperTick: 4});
  IStrategy.LiquidityPosition liquidityPosition = IStrategy.LiquidityPosition({lowerTick: 0, upperTick: 4, liquidity: 1});

  function setUp() public virtual {
    job = new PositionBurnerJobForTest(mockPoolManagerFactory, governor);
    keep3r = job.keep3r();

    vm.mockCall(
      address(mockPoolManagerFactory),
      abi.encodeWithSelector(IPoolManagerFactory.isChild.selector, mockPoolManager),
      abi.encode(true)
    );
    vm.mockCall(address(mockPoolManager), abi.encodeWithSelector(IPoolManager.lockManager.selector), abi.encode(mockLockManager));
    vm.mockCall(address(mockLockManager), abi.encodeWithSelector(ILockManager.getPositionToBurn.selector), abi.encode(liquidityPosition));
  }
}

contract UnitPositionBurnerJobWork is Base {
  event Worked(ILockManager _lockManager, IStrategy.Position _position);

  function testUpkeep() external {
    vm.prank(keeper);
    job.work(mockPoolManager, positionToBurn);

    assertEq(job.upkeepKeeperForTest(), keeper);
  }

  function testRevertIfPaused() external {
    job.setPausedForTest(true);

    vm.expectRevert(IPausable.Paused.selector);

    job.work(mockPoolManager, positionToBurn);
  }

  function testRevertIfInvalidPoolManager() external {
    vm.mockCall(
      address(mockPoolManagerFactory),
      abi.encodeWithSelector(IPoolManagerFactory.isChild.selector, mockPoolManager),
      abi.encode(false)
    );

    vm.expectRevert(abi.encodeWithSelector(IPositionBurnerJob.PositionBurnerJob_InvalidPoolManager.selector, mockPoolManager));

    job.work(mockPoolManager, positionToBurn);
  }

  function testBurnPosition() external {
    vm.expectCall(address(mockLockManager), abi.encodeWithSelector(ILockManager.burnPosition.selector, positionToBurn));

    job.work(mockPoolManager, positionToBurn);
  }

  function testEmitEvent() external {
    vm.expectEmit(false, false, false, true);
    emit Worked(mockLockManager, positionToBurn);

    job.work(mockPoolManager, positionToBurn);
  }
}

contract UnitPositionBurnerJobIsWorkable is Base {
  function testPaused(bool paused) external {
    vm.mockCall(address(keep3r), abi.encodeWithSelector(IKeep3rJobWorkable.isBondedKeeper.selector), abi.encode(true));

    job.setPausedForTest(paused);

    assertEq(job.isWorkable(mockPoolManager, positionToBurn), !paused);
  }

  function testWorkWithKeeper(bool isValid, address _keeper) external {
    vm.mockCall(address(keep3r), abi.encodeWithSelector(IKeep3rJobWorkable.isBondedKeeper.selector, _keeper), abi.encode(isValid));

    assertEq(job.isWorkable(mockPoolManager, positionToBurn, _keeper), isValid);
  }

  function testPausedWithKeeper(bool paused) external {
    vm.mockCall(address(keep3r), abi.encodeWithSelector(IKeep3rJobWorkable.isBondedKeeper.selector), abi.encode(true));

    job.setPausedForTest(paused);

    assertEq(job.isWorkable(mockPoolManager, positionToBurn, address(this)), !paused);
  }

  function testWithValidPosition() external {
    IStrategy.Position memory position = IStrategy.Position({lowerTick: positionToBurn.lowerTick, upperTick: positionToBurn.upperTick});
    assertEq(job.isWorkable(mockPoolManager, position), true);
  }

  function testWithInvalidPosition(IStrategy.Position memory position) external {
    vm.assume(position.upperTick != liquidityPosition.upperTick && position.lowerTick != liquidityPosition.lowerTick);

    assertEq(job.isWorkable(mockPoolManager, position), false);
  }
}
