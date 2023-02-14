// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4 <0.9.0;

import 'solidity-utils/test/DSTestPlus.sol';
import 'solidity-utils/contracts/Governable.sol';
import '@contracts/jobs/CorrectionsRemoverJob.sol';

contract CorrectionsRemoverJobForTest is CorrectionsRemoverJob {
  address public upkeepKeeperForTest;

  constructor(IPoolManagerFactory _poolManagerFactory, address _governor) CorrectionsRemoverJob(_poolManagerFactory, _governor) {}

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
  address governance = label(address(101), 'governance');

  IKeep3r keep3r;
  CorrectionsRemoverJobForTest job;

  IUniswapV3Pool mockPool = IUniswapV3Pool(mockContract('mockPool'));
  IPoolManager mockPoolManager = IPoolManager(mockContract('mockPool'));
  IPriceOracle mockPriceOracle = IPriceOracle(mockContract('mockPriceOracle'));
  IPoolManagerFactory mockPoolManagerFactory = IPoolManagerFactory(mockContract('mockPoolManagerFactory'));

  function setUp() public virtual {
    vm.mockCall(address(mockPoolManagerFactory), abi.encodeWithSelector(IPoolManagerFactory.priceOracle.selector), abi.encode(mockPriceOracle));
    vm.mockCall(
      address(mockPoolManagerFactory),
      abi.encodeWithSelector(IPoolManagerFactory.isSupportedPool.selector, address(mockPool)),
      abi.encode(true)
    );

    job = new CorrectionsRemoverJobForTest(mockPoolManagerFactory, governance);
    keep3r = job.keep3r();
  }
}

contract UnitCorrectionsRemoverJobConstructor is Base {
  function testParameters() external {
    assertEq(address(job.POOL_MANAGER_FACTORY()), address(mockPoolManagerFactory));
    assertEq(address(job.PRICE_ORACLE()), address(mockPriceOracle));
  }
}

contract UnitCorrectionsRemoverJobWorkPool is Base {
  event Worked(IUniswapV3Pool _pool);

  function testUpkeep() external {
    vm.prank(keeper);
    job.work(mockPool);

    assertEq(job.upkeepKeeperForTest(), keeper);
  }

  function testRevertIfPaused() external {
    job.pauseForTest();

    vm.expectRevert(IPausable.Paused.selector);

    job.work(mockPool);
  }

  function testRevertIfInvalidPool() external {
    vm.mockCall(
      address(mockPoolManagerFactory),
      abi.encodeWithSelector(IPoolManagerFactory.isSupportedPool.selector, address(mockPool)),
      abi.encode(false)
    );

    vm.expectRevert(abi.encodeWithSelector(ICorrectionsRemoverJob.CorrectionsRemoverJob_InvalidPool.selector, mockPool));

    job.work(mockPool);
  }

  function testWorkJob() external {
    vm.expectCall(address(mockPriceOracle), abi.encodeWithSelector(IPriceOracle.removeOldCorrections.selector, mockPool));
    job.work(mockPool);
  }

  function testEmitEvent() external {
    vm.expectEmit(false, false, false, true);
    emit Worked(mockPool);

    job.work(mockPool);
  }
}
