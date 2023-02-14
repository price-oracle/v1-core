// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4 <0.9.0;

import '@test/e2e/Common.sol';

contract E2EPoolManagerGovernance is CommonE2EBase {
  PriceOracle priceOracle2;
  PriceOracle priceOracle3;
  FeeManager feeManager2;
  FeeManager feeManager3;
  IPoolManager _poolManager;

  uint256 migrateMethod = uint256(IPoolManagerGovernor.Methods.Migrate);
  uint256 feeManagerChangeMethod = uint256(IPoolManagerGovernor.Methods.FeeManagerChange);
  uint256 priceOracleChangeMethod = uint256(IPoolManagerGovernor.Methods.PriceOracleChange);

  address randomContract = mockContract('randomContract');
  address randomContract2 = mockContract('randomContract2');
  address wrongContract = mockContract('wrongContract');

  bytes internal constant _MIGRATE = abi.encodeWithSignature('migrate()');

  function setUp() public virtual override {
    super.setUp();

    _poolManager = poolManagerDai;

    vm.startPrank(governance);
    priceOracle2 = new PriceOracle(poolManagerFactory, UNISWAP_V3_FACTORY, POOL_BYTECODE_HASH, weth);
    label(address(priceOracle2), 'PriceOracle2');

    priceOracle3 = new PriceOracle(poolManagerFactory, UNISWAP_V3_FACTORY, POOL_BYTECODE_HASH, weth);
    label(address(priceOracle3), 'PriceOracle3');

    feeManager2 = new FeeManager(poolManagerFactory, governance, weth);
    label(address(feeManager2), 'FeeManager2');

    feeManager3 = new FeeManager(poolManagerFactory, governance, weth);
    label(address(feeManager3), 'FeeManager3');
    vm.stopPrank();

    vm.startPrank(user1);
    weth.approve(address(_poolManager), type(uint256).max);
    _poolManager.TOKEN().approve(address(_poolManager), type(uint256).max);
    vm.stopPrank();

    vm.startPrank(user2);
    weth.approve(address(_poolManager), type(uint256).max);
    _poolManager.TOKEN().approve(address(_poolManager), type(uint256).max);
    vm.stopPrank();
  }

  function testE2EAllowsProposalOverwriteIfNewContractMigrate() public {
    // Increase liquidity in pool manager
    _increaseFullRangePosition(user1, liquidity);
    uint256 _user1Balance = _poolManager.seederBalance(user1);

    // Set new migration contract
    vm.prank(governance);
    poolManagerFactory.setPoolManagerMigrator(randomContract);

    // Create the proposal
    _poolManager.proposeMigrate(randomContract);

    // First accept the proposal
    _acceptMigrate(user1, randomContract);

    // The total votes should be equals to locked from user1
    assertApproxEqAbs(_getVotes(migrateMethod), _user1Balance, DELTA);

    // Set new migration contract
    vm.prank(governance);
    poolManagerFactory.setPoolManagerMigrator(randomContract2);

    // Overwrite the proposal
    _poolManager.proposeMigrate(randomContract2);

    // The total votes which accept the proposal should be 0
    assertApproxEqAbs(_getVotes(migrateMethod), 0, DELTA);

    // First accept the proposal
    _acceptMigrate(user1, randomContract2);

    // The total votes should be equals to locked from user1
    assertApproxEqAbs(_getVotes(migrateMethod), _user1Balance, DELTA);
  }

  function testE2ECancelMigrateProposalStopsIt() public {
    // Increase liquidity in pool manager
    _increaseFullRangePosition(user1, liquidity);
    _increaseFullRangePosition(user2, liquidity);
    _increaseFullRangePosition(user2, liquidity);

    // Set new migration contract
    vm.prank(governance);
    poolManagerFactory.setPoolManagerMigrator(randomContract);

    // Create the proposal
    _poolManager.proposeMigrate(randomContract);

    // First accept the proposal
    _acceptMigrate(user1, randomContract);
    _acceptMigrate(user2, randomContract);

    // Queue proposal, no revert
    _poolManager.queue(migrateMethod, abi.encode(randomContract));

    // Pass time to be able to execute vote
    vm.warp(block.timestamp + _poolManager.executionTimelock());

    // Cancel the proposal only gov
    vm.prank(governance);
    _poolManager.cancelProposal(uint256(IPoolManagerGovernor.Methods.Migrate));

    // Reverts on trying to execute
    vm.expectRevert(abi.encodeWithSelector(IGovernorMiniBravo.ProposalNotExecutable.selector, migrateMethod, 1));
    _poolManager.execute(migrateMethod, abi.encode(randomContract));
  }

  function testE2EUserAcceptAndCancelProposalMigrate() public {
    // Increase liquidity in pool manager
    _increaseFullRangePosition(user1, liquidity);
    uint256 _user1Balance = _poolManager.seederBalance(user1);

    // Set new migration contract
    vm.prank(governance);
    poolManagerFactory.setPoolManagerMigrator(randomContract);

    // Create the proposal
    _poolManager.proposeMigrate(randomContract);

    // First accept the proposal
    _acceptMigrate(user1, randomContract);

    // The total votes should be equals to locked from user1
    assertApproxEqAbs(_getVotes(migrateMethod), _user1Balance, DELTA);

    // Finally decline the proposal
    _cancelProposal(user1, migrateMethod);

    // The total votes which accept the proposal should be 0
    assertApproxEqAbs(_getVotes(migrateMethod), 0, DELTA);
  }

  function testE2EMigrateFlow() public {
    // Increase liquidity in pool manager
    _increaseFullRangePosition(user1, liquidity);
    _increaseFullRangePosition(user2, liquidity);
    _increaseFullRangePosition(user2, liquidity);

    // Set new migration contract
    vm.prank(governance);
    poolManagerFactory.setPoolManagerMigrator(randomContract);

    // Propose migrate with wrong contract should revert
    vm.expectRevert(abi.encodeWithSelector(IPoolManagerGovernor.PoolManager_MigrationContractMismatch.selector, randomContract, wrongContract));
    _poolManager.proposeMigrate(wrongContract);

    // Create the proposal
    _poolManager.proposeMigrate(randomContract);

    // Queue proposal, should fail as quorum not reached
    vm.expectRevert(abi.encodeWithSelector(IGovernorMiniBravo.QuorumNotReached.selector, migrateMethod, 1));
    _poolManager.queue(migrateMethod, abi.encode(randomContract));

    // Accept the proposal
    _acceptMigrate(user1, randomContract);

    // Quorum still not reached
    assertFalse(_poolManager.quorumReached(migrateMethod));

    // Accept the proposal
    _acceptMigrate(user2, randomContract);

    // Do nothing and don't step on proposal if already exists
    _poolManager.proposeMigrate(randomContract);

    // Quorum now reached
    assertTrue(_poolManager.quorumReached(migrateMethod));

    // Queue proposal, no revert
    _poolManager.queue(migrateMethod, abi.encode(randomContract));

    // Queue proposal again, should fail as already queued
    vm.expectRevert(abi.encodeWithSelector(IGovernorMiniBravo.ProposalAlreadyQueued.selector, migrateMethod, 1));
    _poolManager.queue(migrateMethod, abi.encode(randomContract));

    // Execute proposal, should fail as timelock hasn't passed
    vm.expectRevert(abi.encodeWithSelector(IGovernorMiniBravo.ProposalNotExecutable.selector, migrateMethod, 1));
    _poolManager.execute(migrateMethod, abi.encode(randomContract));

    // Pass time to be able to execute vote
    vm.warp(block.timestamp + _poolManager.executionTimelock());

    // Execute proposal, should fail if invalid address sent
    vm.expectRevert(
      abi.encodeWithSelector(
        IGovernorMiniBravo.ParametersMismatch.selector,
        migrateMethod,
        abi.encode(randomContract),
        abi.encode(wrongContract)
      )
    );
    _poolManager.execute(migrateMethod, abi.encode(wrongContract));

    // Execute proposal should work <3
    vm.expectCall(randomContract, _MIGRATE);
    _poolManager.execute(migrateMethod, abi.encode(randomContract));
  }

  function testE2EChangeFeeManagerFlow() public {
    // Increase liquidity in pool manager
    _increaseFullRangePosition(user1, liquidity);
    _increaseFullRangePosition(user2, liquidity);
    _increaseFullRangePosition(user2, liquidity);

    // Set new migration contract
    vm.prank(governance);
    poolManagerFactory.setFeeManager(feeManager2);

    // Propose migrate with wrong contract should revert
    vm.expectRevert(abi.encodeWithSelector(IPoolManagerGovernor.PoolManager_FeeManagerMismatch.selector, feeManager2, feeManager3));
    _poolManager.proposeFeeManagerChange(feeManager3);

    // Create the proposal
    _poolManager.proposeFeeManagerChange(feeManager2);

    // Queue proposal, should fail as quorum not reached
    vm.expectRevert(abi.encodeWithSelector(IGovernorMiniBravo.QuorumNotReached.selector, feeManagerChangeMethod, 1));
    _poolManager.queue(feeManagerChangeMethod, abi.encode(feeManager2));

    // Accept the proposal
    vm.prank(user1);
    _poolManager.acceptFeeManagerChange(feeManager2);

    // Quorum still not reached
    assertFalse(_poolManager.quorumReached(feeManagerChangeMethod));

    // Accept the proposal
    vm.prank(user2);
    _poolManager.acceptFeeManagerChange(feeManager2);

    // Do nothing and don't step on proposal if already exists
    _poolManager.proposeFeeManagerChange(feeManager2);

    // Quorum now reached
    assertTrue(_poolManager.quorumReached(feeManagerChangeMethod));

    // Queue proposal, no revert
    _poolManager.queue(feeManagerChangeMethod, abi.encode(feeManager2));

    // Queue proposal again, should fail as already queued
    vm.expectRevert(abi.encodeWithSelector(IGovernorMiniBravo.ProposalAlreadyQueued.selector, feeManagerChangeMethod, 1));
    _poolManager.queue(feeManagerChangeMethod, abi.encode(feeManager2));

    // Execute proposal, should fail as timelock hasn't passed
    vm.expectRevert(abi.encodeWithSelector(IGovernorMiniBravo.ProposalNotExecutable.selector, feeManagerChangeMethod, 1));
    _poolManager.execute(feeManagerChangeMethod, abi.encode(feeManager2));

    // Pass time to be able to execute vote
    vm.warp(block.timestamp + _poolManager.executionTimelock());

    // Execute proposal, should fail if invalid address sent
    vm.expectRevert(
      abi.encodeWithSelector(
        IGovernorMiniBravo.ParametersMismatch.selector,
        feeManagerChangeMethod,
        abi.encode(feeManager2),
        abi.encode(feeManager3)
      )
    );
    _poolManager.execute(feeManagerChangeMethod, abi.encode(feeManager3));

    // Execute proposal should work <3
    _poolManager.execute(feeManagerChangeMethod, abi.encode(feeManager2));
    assertEq(address(_poolManager.feeManager()), address(feeManager2));
  }

  function testE2EChangePriceOracleFlow() public {
    // Increase liquidity in pool manager
    _increaseFullRangePosition(user1, liquidity);
    _increaseFullRangePosition(user2, liquidity);
    _increaseFullRangePosition(user2, liquidity);

    // Set new migration contract
    vm.prank(governance);
    poolManagerFactory.setPriceOracle(priceOracle2);

    // Propose migrate with wrong contract should revert
    vm.expectRevert(abi.encodeWithSelector(IPoolManagerGovernor.PoolManager_PriceOracleMismatch.selector, priceOracle2, priceOracle3));
    _poolManager.proposePriceOracleChange(priceOracle3);

    // Create the proposal
    _poolManager.proposePriceOracleChange(priceOracle2);

    // Queue proposal, should fail as quorum not reached
    vm.expectRevert(abi.encodeWithSelector(IGovernorMiniBravo.QuorumNotReached.selector, priceOracleChangeMethod, 1));
    _poolManager.queue(priceOracleChangeMethod, abi.encode(priceOracle2));

    // Accept the proposal
    vm.prank(user1);
    _poolManager.acceptPriceOracleChange(priceOracle2);

    // Quorum still not reached
    assertFalse(_poolManager.quorumReached(priceOracleChangeMethod));

    // Accept the proposal
    vm.prank(user2);
    _poolManager.acceptPriceOracleChange(priceOracle2);

    // Do nothing and don't step on proposal if already exists
    _poolManager.proposePriceOracleChange(priceOracle2);

    // Quorum now reached
    assertTrue(_poolManager.quorumReached(priceOracleChangeMethod));

    // Queue proposal, no revert
    _poolManager.queue(priceOracleChangeMethod, abi.encode(priceOracle2));

    // Queue proposal again, should fail as already queued
    vm.expectRevert(abi.encodeWithSelector(IGovernorMiniBravo.ProposalAlreadyQueued.selector, priceOracleChangeMethod, 1));
    _poolManager.queue(priceOracleChangeMethod, abi.encode(priceOracle2));

    // Execute proposal, should fail as timelock hasn't passed
    vm.expectRevert(abi.encodeWithSelector(IGovernorMiniBravo.ProposalNotExecutable.selector, priceOracleChangeMethod, 1));
    _poolManager.execute(priceOracleChangeMethod, abi.encode(priceOracle2));

    // Pass time to be able to execute vote
    vm.warp(block.timestamp + _poolManager.executionTimelock());

    // Execute proposal, should fail if invalid address sent
    vm.expectRevert(
      abi.encodeWithSelector(
        IGovernorMiniBravo.ParametersMismatch.selector,
        priceOracleChangeMethod,
        abi.encode(priceOracle2),
        abi.encode(priceOracle3)
      )
    );
    _poolManager.execute(priceOracleChangeMethod, abi.encode(priceOracle3));

    // Execute proposal should work <3
    _poolManager.execute(priceOracleChangeMethod, abi.encode(priceOracle2));
    assertEq(address(_poolManager.priceOracle()), address(priceOracle2));
  }

  /// @notice Votes yes for migrate call
  function _acceptMigrate(address user, address _migrationContract) internal {
    vm.prank(user);
    _poolManager.acceptMigrate(_migrationContract);
  }

  /// @notice Cancels a proposal
  function _cancelProposal(address user, uint256 method) internal {
    vm.prank(user);
    _poolManager.cancelVote(method);
  }

  /// @notice Gets the total votes that accept the proposal
  function _getVotes(uint256 method) internal view returns (uint256 totalVotes) {
    IGovernorMiniBravo.Proposal memory proposal = _poolManager.getLatest(method);
    totalVotes = proposal.forVotes;
  }

  function _increaseFullRangePosition(address _donor, uint128 _liquidity) public {
    (uint160 _sqrtPriceX96, , , , , , ) = _poolManager.POOL().slot0();
    vm.prank(_donor);
    _poolManager.increaseFullRangePosition(_donor, _liquidity, _sqrtPriceX96);
  }
}
