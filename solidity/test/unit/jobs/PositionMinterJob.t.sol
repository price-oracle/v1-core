// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4 <0.9.0;

import 'uni-v3-periphery/libraries/OracleLibrary.sol';
import 'solidity-utils/test/DSTestPlus.sol';

import '@contracts/jobs/PositionMinterJob.sol';

contract PositionMinterJobForTest is PositionMinterJob {
  address public upkeepKeeperForTest;

  constructor(IPoolManagerFactory _poolManagerFactory, address _governor) PositionMinterJob(_poolManagerFactory, _governor) {}

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

  PositionMinterJobForTest job;
  IStrategy.LiquidityPosition positionToMint = IStrategy.LiquidityPosition({lowerTick: 0, upperTick: 4, liquidity: 1});

  function setUp() public virtual {
    job = new PositionMinterJobForTest(mockPoolManagerFactory, governor);
    keep3r = job.keep3r();

    vm.mockCall(address(mockPoolManagerFactory), abi.encodeWithSelector(IPoolManagerFactory.isChild.selector), abi.encode(true));
    vm.mockCall(address(mockPoolManager), abi.encodeWithSelector(IPoolManager.lockManager.selector), abi.encode(mockLockManager));
  }
}

contract UnitPositionMinterJobWork is Base {
  event Worked(IPoolManager _poolManager);

  function testUpkeep() external {
    vm.prank(keeper);
    job.work(mockPoolManager);

    assertEq(job.upkeepKeeperForTest(), keeper);
  }

  function testRevertIfPaused() external {
    job.setPausedForTest(true);

    vm.expectRevert(IPausable.Paused.selector);

    job.work(mockPoolManager);
  }

  function testRevertIfInvalidPoolManager() external {
    vm.mockCall(
      address(mockPoolManagerFactory),
      abi.encodeWithSelector(IPoolManagerFactory.isChild.selector, mockPoolManager),
      abi.encode(false)
    );

    vm.expectRevert(abi.encodeWithSelector(IPositionMinterJob.PositionMinterJob_InvalidPoolManager.selector, mockPoolManager));

    job.work(mockPoolManager);
  }

  function testMintPosition() external {
    vm.expectCall(address(mockLockManager), abi.encodeWithSelector(ILockManager.mintPosition.selector));

    job.work(mockPoolManager);
  }

  function testEmitEvent() external {
    vm.expectEmit(false, false, false, true);
    emit Worked(mockPoolManager);

    job.work(mockPoolManager);
  }
}

contract UnitPositionMinterJobIsWorkable is Base {
  int24 lowerTick;
  int24 upperTick;
  uint128 wethDesired;

  function testPaused(bool paused) external {
    vm.mockCall(address(mockLockManager), abi.encodeWithSelector(ILockManager.getPositionToMint.selector), abi.encode(positionToMint));
    vm.mockCall(address(keep3r), abi.encodeWithSelector(IKeep3rJobWorkable.isBondedKeeper.selector), abi.encode(true));

    job.setPausedForTest(paused);

    assertEq(job.isWorkable(mockPoolManager), !paused);
  }

  function testCheckPositions(uint8 amount) external {
    positionToMint.liquidity = amount;
    vm.mockCall(address(mockLockManager), abi.encodeWithSelector(ILockManager.getPositionToMint.selector), abi.encode(positionToMint));
    vm.mockCall(address(keep3r), abi.encodeWithSelector(IKeep3rJobWorkable.isBondedKeeper.selector), abi.encode(true));

    assertEq(job.isWorkable(mockPoolManager), amount > 0);
  }

  function testCheckKeeperValidity(bool isValid, address _keeper) external {
    vm.mockCall(address(mockLockManager), abi.encodeWithSelector(ILockManager.getPositionToMint.selector), abi.encode(positionToMint));
    vm.mockCall(address(keep3r), abi.encodeWithSelector(IKeep3rJobWorkable.isBondedKeeper.selector, _keeper), abi.encode(isValid));

    assertEq(job.isWorkable(mockPoolManager, _keeper), isValid);
  }

  function testPausedWithKeeper(bool paused) external {
    vm.mockCall(address(mockLockManager), abi.encodeWithSelector(ILockManager.getPositionToMint.selector), abi.encode(positionToMint));
    vm.mockCall(address(keep3r), abi.encodeWithSelector(IKeep3rJobWorkable.isBondedKeeper.selector), abi.encode(true));

    job.setPausedForTest(paused);

    assertEq(job.isWorkable(mockPoolManager, address(this)), !paused);
  }

  function testCheckPositionsWithKeeper(uint8 amount) external {
    positionToMint.liquidity = amount;

    vm.mockCall(address(mockLockManager), abi.encodeWithSelector(ILockManager.getPositionToMint.selector), abi.encode(positionToMint));
    vm.mockCall(address(keep3r), abi.encodeWithSelector(IKeep3rJobWorkable.isBondedKeeper.selector), abi.encode(true));

    assertEq(job.isWorkable(mockPoolManager, address(this)), amount > 0);
  }
}
