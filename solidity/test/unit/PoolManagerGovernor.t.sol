// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4 <0.9.0;

import 'solidity-utils/test/DSTestPlus.sol';

import '@contracts/PoolManagerGovernor.sol';
import '@test/utils/TestConstants.sol';

contract MigrationContractForTest {
  function migrate() external {}
}

contract RevertableMigrationContractForTest {
  function migrate() external {
    revert('Revert');
  }
}

contract PoolManagerGovernorForTest is PoolManagerGovernor {
  function votingPowerMocked() public view returns (uint256 _totalVotes) {}

  function votingPower(
    address /* _user */
  ) public view virtual override returns (uint256 _balance) {
    return PoolManagerGovernorForTest(address(this)).votingPowerMocked();
  }

  function totalVotesMocked() public view returns (uint256 _totalVotes) {}

  function totalVotes() public view virtual override returns (uint256 _totalVotes) {
    return PoolManagerGovernorForTest(address(this)).totalVotesMocked();
  }

  function getUserVotes(
    address _user,
    uint256 _method,
    uint256 _propId
  ) public view returns (uint256) {
    return _userVotes[_method][_propId][_user];
  }
}

abstract contract Base is DSTestPlus, TestConstants {
  PoolManagerGovernorForTest governor;
  address admin = newAddress();

  uint256 totalVotes = 100 ether;
  uint256 userVotingPower = 40 ether; // Two users can get to quorum
  uint256 migrate = uint256(IPoolManagerGovernor.Methods.Migrate);
  uint256 feeManagerChange = uint256(IPoolManagerGovernor.Methods.FeeManagerChange);
  uint256 priceOracleChange = uint256(IPoolManagerGovernor.Methods.PriceOracleChange);

  IPoolManagerFactory mockPoolManagerFactory = IPoolManagerFactory(mockContract('mockPoolManagerFactory'));
  IPoolManagerDeployer mockPoolManagerDeployer = IPoolManagerDeployer(mockContract('mockPoolManagerDeployer'));
  IFeeManager mockFeeManager = IFeeManager(mockContract('mockFeeManager'));
  IFeeManager mockFeeManagerOld = IFeeManager(mockContract('mockFeeManagerOld'));
  MigrationContractForTest mockMigrate = new MigrationContractForTest();
  RevertableMigrationContractForTest mockMigrateInvalid = new RevertableMigrationContractForTest();
  IPriceOracle mockPriceOracle = IPriceOracle(mockContract('mockPriceOracle'));
  IPriceOracle mockPriceOracleOld = IPriceOracle(mockContract('mockPriceOracleOld'));
  IERC20 mockToken = IERC20(mockContract('mockToken'));
  IERC20 mockWeth = IERC20(mockContract(WETH_ADDRESS, 'mockWeth'));

  function setUp() public virtual {
    vm.mockCall(
      address(mockPoolManagerFactory),
      abi.encodeWithSelector(IPoolManagerFactory.constructorArguments.selector),
      abi.encode(UNISWAP_V3_FACTORY, POOL_BYTECODE_HASH, mockWeth, mockToken, mockFeeManagerOld, mockPriceOracleOld, admin, 0, 0)
    );
    vm.mockCall(
      address(mockPoolManagerDeployer),
      abi.encodeWithSelector(IPoolManagerDeployer.POOL_MANAGER_FACTORY.selector),
      abi.encode(mockPoolManagerFactory)
    );

    vm.prank(address(mockPoolManagerDeployer));
    governor = new PoolManagerGovernorForTest();

    vm.mockCall(address(governor), abi.encodeWithSelector(PoolManagerGovernorForTest.totalVotesMocked.selector), abi.encode(totalVotes));
    vm.mockCall(address(governor), abi.encodeWithSelector(PoolManagerGovernorForTest.votingPowerMocked.selector), abi.encode(userVotingPower));
    vm.mockCall(address(mockPoolManagerFactory), abi.encodeWithSelector(IPoolManagerFactory.feeManager.selector), abi.encode(mockFeeManager));
    vm.mockCall(
      address(mockPoolManagerFactory),
      abi.encodeWithSelector(IPoolManagerFactory.poolManagerMigrator.selector),
      abi.encode(mockMigrate)
    );
    vm.mockCall(address(mockPoolManagerFactory), abi.encodeWithSelector(IPoolManagerFactory.priceOracle.selector), abi.encode(mockPriceOracle));
    vm.mockCall(address(mockFeeManagerOld), abi.encodeWithSelector(IFeeManager.migrateTo.selector, address(mockFeeManager)), abi.encode());
  }
}

contract UnitPoolManagerGovernorCreateProposals is Base {
  function testRevertProposeFeeManagerIfMismatch() public {
    IFeeManager _wrongFeeManager = IFeeManager(newAddress());
    vm.expectRevert(abi.encodeWithSelector(IPoolManagerGovernor.PoolManager_FeeManagerMismatch.selector, mockFeeManager, _wrongFeeManager));
    governor.proposeFeeManagerChange(_wrongFeeManager);
  }

  function testRevertProposePriceOracleIfMismatch() public {
    IPriceOracle _wrongPriceOracle = IPriceOracle(newAddress());
    vm.expectRevert(abi.encodeWithSelector(IPoolManagerGovernor.PoolManager_PriceOracleMismatch.selector, mockPriceOracle, _wrongPriceOracle));
    governor.proposePriceOracleChange(_wrongPriceOracle);
  }

  function testRevertProposeMigrateIfMismatch() public {
    address _wrongMigrateContract = newAddress();
    vm.expectRevert(
      abi.encodeWithSelector(IPoolManagerGovernor.PoolManager_MigrationContractMismatch.selector, address(mockMigrate), _wrongMigrateContract)
    );
    governor.proposeMigrate(_wrongMigrateContract);
  }

  function testRevertProposeFeeManagerIfFeeManagerAlreadySet() public {
    vm.mockCall(address(mockPoolManagerFactory), abi.encodeWithSelector(IPoolManagerFactory.feeManager.selector), abi.encode(mockFeeManagerOld));
    vm.expectRevert(abi.encodeWithSelector(IPoolManagerGovernor.PoolManager_FeeManagerAlreadySet.selector));
    governor.proposeFeeManagerChange(mockFeeManagerOld);
  }

  function testRevertProposePriceOracleIfPriceOracleAlreadySet() public {
    vm.mockCall(
      address(mockPoolManagerFactory),
      abi.encodeWithSelector(IPoolManagerFactory.priceOracle.selector),
      abi.encode(mockPriceOracleOld)
    );
    vm.expectRevert(abi.encodeWithSelector(IPoolManagerGovernor.PoolManager_PriceOracleAlreadySet.selector));
    governor.proposePriceOracleChange(mockPriceOracleOld);
  }

  function testProposeFeeManagerChangeProposal() public {
    governor.proposeFeeManagerChange(mockFeeManager);
    GovernorMiniBravo.Proposal memory _prop = governor.getLatest(feeManagerChange);
    assertEq(_prop.params, abi.encode(mockFeeManager));
  }

  function testProposePriceOracleChangeProposal() public {
    governor.proposePriceOracleChange(mockPriceOracle);
    GovernorMiniBravo.Proposal memory _prop = governor.getLatest(priceOracleChange);
    assertEq(_prop.params, abi.encode(mockPriceOracle));
  }
}

contract UnitPoolManagerGovernorAcceptProposal is Base {
  function setUp() public override {
    super.setUp();

    governor.proposeFeeManagerChange(mockFeeManager);
    governor.proposePriceOracleChange(mockPriceOracle);
    governor.proposeMigrate(address(mockMigrate));
  }

  function testAcceptFeeManagerChangeProposal() public {
    governor.acceptFeeManagerChange(mockFeeManager);
    GovernorMiniBravo.Proposal memory _prop = governor.getLatest(feeManagerChange);
    assertEq(_prop.forVotes, userVotingPower);
  }

  function testAcceptPriceOracleChangeProposal() public {
    governor.acceptPriceOracleChange(mockPriceOracle);
    GovernorMiniBravo.Proposal memory _prop = governor.getLatest(priceOracleChange);
    assertEq(_prop.forVotes, userVotingPower);
  }

  function testAcceptMigrateProposal() public {
    governor.acceptMigrate(address(mockMigrate));
    GovernorMiniBravo.Proposal memory _prop = governor.getLatest(migrate);
    assertEq(_prop.forVotes, userVotingPower);
  }
}

contract UnitPoolManagerGovernorCancelProposal is Base {
  function setUp() public override {
    super.setUp();

    governor.proposeFeeManagerChange(mockFeeManager);
    governor.proposePriceOracleChange(mockPriceOracle);
    governor.proposeMigrate(address(mockMigrate));
  }

  function testRevertCancelMigrateIfNonAdmin() public {
    vm.expectRevert(abi.encodeWithSelector(IRoles.Unauthorized.selector, address(this), governor.DEFAULT_ADMIN_ROLE()));
    governor.cancelProposal(uint256(IPoolManagerGovernor.Methods.Migrate));
  }

  function testCancelMigrate() public {
    vm.prank(admin);
    governor.cancelProposal(uint256(IPoolManagerGovernor.Methods.Migrate));
    GovernorMiniBravo.Proposal memory _prop = governor.getLatest(migrate);
    assertEq(_prop.open, false);
  }

  function testCancelFeeManagerChange() public {
    vm.prank(admin);
    governor.cancelProposal(uint256(IPoolManagerGovernor.Methods.FeeManagerChange));
    GovernorMiniBravo.Proposal memory _prop = governor.getLatest(feeManagerChange);
    assertEq(_prop.open, false);
  }

  function testCancelPriceOracleChange() public {
    vm.prank(admin);
    governor.cancelProposal(uint256(IPoolManagerGovernor.Methods.PriceOracleChange));
    GovernorMiniBravo.Proposal memory _prop = governor.getLatest(priceOracleChange);
    assertEq(_prop.open, false);
  }
}

contract UnitPoolManagerGovernorExecuteProposal is Base {
  event FeeManagerMigrated(IFeeManager _newFeeManager);
  event PriceOracleSet(IPriceOracle _newPriceOracle);

  function setUp() public override {
    super.setUp();

    governor.proposeFeeManagerChange(mockFeeManager);
    governor.proposePriceOracleChange(mockPriceOracle);
    governor.proposeMigrate(address(mockMigrate));

    vm.prank(admin);
    governor.acceptFeeManagerChange(mockFeeManager);
    governor.acceptFeeManagerChange(mockFeeManager);

    vm.prank(admin);
    governor.acceptPriceOracleChange(mockPriceOracle);
    governor.acceptPriceOracleChange(mockPriceOracle);

    vm.prank(admin);
    governor.acceptMigrate(address(mockMigrate));
    governor.acceptMigrate(address(mockMigrate));
  }

  function testExecuteFeeManagerChangeProposal() public {
    governor.queue(feeManagerChange, abi.encode(mockFeeManager));
    vm.warp(block.timestamp + governor.executionTimelock());

    vm.expectEmit(false, false, false, true);
    emit FeeManagerMigrated(mockFeeManager);

    vm.expectCall(address(mockFeeManagerOld), abi.encodeWithSelector(IFeeManager.migrateTo.selector));
    governor.execute(feeManagerChange, abi.encode(mockFeeManager));
    assertEq(address(governor.feeManager()), address(mockFeeManager));
  }

  function testExecutePriceOracleChangeProposal() public {
    governor.queue(priceOracleChange, abi.encode(mockPriceOracle));
    vm.warp(block.timestamp + governor.executionTimelock());

    vm.expectEmit(false, false, false, true);
    emit PriceOracleSet(mockPriceOracle);

    governor.execute(priceOracleChange, abi.encode(mockPriceOracle));
    assertEq(address(governor.priceOracle()), address(mockPriceOracle));
  }

  function testExecuteMigrateProposal() public {
    governor.queue(migrate, abi.encode(address(mockMigrate)));
    vm.warp(block.timestamp + governor.executionTimelock());
    vm.expectCall(address(mockMigrate), abi.encodeWithSelector(MigrationContractForTest.migrate.selector));
    governor.execute(migrate, abi.encode(address(mockMigrate)));
  }

  function testRevertIfMigrationFails() public {
    vm.mockCall(
      address(mockPoolManagerFactory),
      abi.encodeWithSelector(IPoolManagerFactory.poolManagerMigrator.selector),
      abi.encode(mockMigrateInvalid)
    );
    governor.proposeMigrate(address(mockMigrateInvalid));

    vm.prank(admin);
    governor.acceptMigrate(address(mockMigrateInvalid));
    governor.acceptMigrate(address(mockMigrateInvalid));

    governor.queue(migrate, abi.encode(address(mockMigrateInvalid)));
    vm.warp(block.timestamp + governor.executionTimelock());
    vm.expectRevert(abi.encodeWithSelector(IPoolManagerGovernor.PoolManager_MigrationFailed.selector));
    governor.execute(migrate, abi.encode(address(mockMigrateInvalid)));
  }
}
