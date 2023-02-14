// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4 <0.9.0;

import 'solidity-utils/test/DSTestPlus.sol';
import 'solidity-utils/contracts/Governable.sol';
import 'keep3r/interfaces/IKeep3rHelper.sol';

import '@contracts/jobs/CorrectionsApplierJob.sol';

contract CorrectionsApplierJobForTest is CorrectionsApplierJob {
  constructor(IPoolManagerFactory _poolManagerFactory, address _governor) CorrectionsApplierJob(_poolManagerFactory, _governor) {}

  function pauseForTest() external {
    paused = true;
  }

  function _isValidKeeper(
    address /* _keeper */
  ) internal pure override returns (bool) {
    return true;
  }
}

contract Base is DSTestPlus {
  address keeper = label('keeper');
  address governance = label('governance');

  IKeep3r keep3r;
  IKeep3rHelper keep3rHelper;
  CorrectionsApplierJobForTest job;

  IUniswapV3Pool mockPool = IUniswapV3Pool(mockContract('mockPoolManager'));
  IPriceOracle mockPriceOracle = IPriceOracle(mockContract('mockPriceOracle'));
  IPoolManagerFactory mockPoolManagerFactory = IPoolManagerFactory(mockContract(address(202), 'mockPoolManagerFactory'));

  function setUp() public {
    vm.mockCall(address(mockPoolManagerFactory), abi.encodeWithSelector(IPoolManagerFactory.priceOracle.selector), abi.encode(mockPriceOracle));
    vm.mockCall(
      address(mockPoolManagerFactory),
      abi.encodeWithSelector(IPoolManagerFactory.isSupportedPool.selector, address(mockPool)),
      abi.encode(true)
    );

    job = new CorrectionsApplierJobForTest(mockPoolManagerFactory, governance);
    keep3r = job.keep3r();
    keep3rHelper = job.keep3rHelper();

    vm.mockCall(address(keep3r), abi.encodeWithSelector(IKeep3rJobWorkable.bondedPayment.selector), abi.encode(true));

    vm.mockCall(address(keep3rHelper), abi.encodeWithSelector(IKeep3rHelper.getRewardAmountFor.selector), abi.encode(0));
  }
}

contract UnitCorrectionsApplierJobConstructor is Base {
  function testParameters() external {
    assertEq(address(job.POOL_MANAGER_FACTORY()), address(mockPoolManagerFactory));
    assertEq(address(job.PRICE_ORACLE()), address(mockPriceOracle));
  }
}

contract UnitCorrectionsApplierJobWorkPool is Base {
  uint32 internal constant _BASE = 10_000;

  event Worked(IUniswapV3Pool _pool, uint16 manipulatedIndex, uint16 period);

  function testRevertIfPaused(uint16 manipulatedIndex, uint16 period) external {
    job.pauseForTest();

    vm.expectRevert(IPausable.Paused.selector);

    job.work(mockPool, manipulatedIndex, period);
  }

  function testRevertIfInvalidPool(uint16 manipulatedIndex, uint16 period) external {
    vm.mockCall(
      address(mockPoolManagerFactory),
      abi.encodeWithSelector(IPoolManagerFactory.isSupportedPool.selector, address(mockPool)),
      abi.encode(false)
    );

    vm.expectRevert(abi.encodeWithSelector(ICorrectionsApplierJob.CorrectionsApplierJob_InvalidPool.selector, mockPool));

    job.work(mockPool, manipulatedIndex, period);
  }

  function testUpkeepMetered(
    uint16 manipulatedIndex,
    uint16 period,
    uint16 reward,
    uint8 gasMultiplier
  ) external {
    vm.mockCall(address(keep3rHelper), abi.encodeWithSelector(IKeep3rHelper.getRewardAmountFor.selector), abi.encode(reward));

    vm.prank(governance);
    job.setGasMultiplier(gasMultiplier);

    vm.expectCall(
      address(keep3r),
      abi.encodeWithSelector(IKeep3rJobWorkable.bondedPayment.selector, keeper, (uint256(reward) * uint256(gasMultiplier)) / _BASE)
    );

    vm.prank(keeper);
    job.work(mockPool, manipulatedIndex, period);
  }

  function testWorkJob(uint16 manipulatedIndex, uint16 period) external {
    vm.expectCall(address(mockPriceOracle), abi.encodeWithSelector(IPriceOracle.applyCorrection.selector, mockPool, manipulatedIndex, period));
    job.work(mockPool, manipulatedIndex, period);
  }

  function testEmitEvent(uint16 manipulatedIndex, uint16 period) external {
    expectEmitNoIndex();
    emit Worked(mockPool, manipulatedIndex, period);

    job.work(mockPool, manipulatedIndex, period);
  }
}

contract UnitCorrectionsApplierJobSetKeep3rHelper is Base {
  event Keep3rHelperChanged(IKeep3rHelper _keep3rHelper);

  function testRevertIfNotGovernance(IKeep3rHelper _keep3rHelper) public {
    vm.expectRevert(abi.encodeWithSelector(IGovernable.OnlyGovernor.selector));

    job.setKeep3rHelper(_keep3rHelper);
  }

  function testSetKeep3rHelper(IKeep3rHelper _keep3rHelper) public {
    vm.prank(governance);
    job.setKeep3rHelper(_keep3rHelper);
    assertEq(address(job.keep3rHelper()), address(_keep3rHelper));
  }

  function testEmitEvent(IKeep3rHelper _keep3rHelper) public {
    expectEmitNoIndex();
    emit Keep3rHelperChanged(_keep3rHelper);

    vm.prank(governance);
    job.setKeep3rHelper(_keep3rHelper);
  }
}

contract UnitCorrectionsApplierJobSetGasMultiplier is Base {
  event GasMultiplierChanged(uint256 _gasMultiplier);

  function testRevertIfNotGovernance(uint256 gasMultiplier) public {
    vm.expectRevert(abi.encodeWithSelector(IGovernable.OnlyGovernor.selector));

    job.setGasMultiplier(gasMultiplier);
  }

  function testSetGasCostMultiplier(uint256 gasMultiplier) public {
    vm.prank(governance);
    job.setGasMultiplier(gasMultiplier);

    assertEq(job.gasMultiplier(), gasMultiplier);
  }

  function testEmitEvent(uint256 gasMultiplier) public {
    expectEmitNoIndex();
    emit GasMultiplierChanged(gasMultiplier);

    vm.prank(governance);
    job.setGasMultiplier(gasMultiplier);
  }
}
