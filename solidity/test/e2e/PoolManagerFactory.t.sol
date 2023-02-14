// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4 <0.9.0;

import '@test/e2e/Common.sol';

contract E2EPoolManagerFactory is CommonE2EBase {
  function testChangeOwnership() public {
    // First nominate the new owner
    vm.prank(governance);
    poolManagerFactory.nominateOwner(user1);
    assertEq(poolManagerFactory.pendingOwner(), user1);

    // The new owner does not have the permissions to change anything yet
    assertNoRoles(user1);

    // The old owner still has all permissions
    assertHasRoles(governance);

    // Accept the ownership change
    vm.prank(user1);
    poolManagerFactory.acceptOwnership();

    // The new owner has all permissions, the old owner has none
    assertHasRoles(user1);
    assertNoRoles(governance);

    // Make sure there is no pending owner
    assertEq(poolManagerFactory.pendingOwner(), address(0));
  }

  /// @notice Reverts if the given address has one or more roles needed to manage PoolManagerFactory
  /// @param who The address that shouldn't have any roles
  function assertNoRoles(address who) internal {
    assertTrue(
      !poolManagerFactory.hasRole(poolManagerFactory.DEFAULT_ADMIN_ROLE(), who) &&
        !poolManagerFactory.hasRole(poolManagerFactory.FACTORY_SETTER_ROLE(), who) &&
        !poolManagerFactory.hasRole(poolManagerFactory.STRATEGY_SETTER_ROLE(), who) &&
        !poolManagerFactory.hasRole(poolManagerFactory.MIGRATOR_SETTER_ROLE(), who) &&
        !poolManagerFactory.hasRole(poolManagerFactory.PRICE_ORACLE_SETTER_ROLE(), who)
    );
  }

  /// @notice Reverts if the given address lacks one or more roles needed to manage PoolManagerFactory
  /// @param who The address that should have the roles
  function assertHasRoles(address who) internal {
    assertTrue(
      poolManagerFactory.hasRole(poolManagerFactory.DEFAULT_ADMIN_ROLE(), who) &&
        poolManagerFactory.hasRole(poolManagerFactory.FACTORY_SETTER_ROLE(), who) &&
        poolManagerFactory.hasRole(poolManagerFactory.STRATEGY_SETTER_ROLE(), who) &&
        poolManagerFactory.hasRole(poolManagerFactory.MIGRATOR_SETTER_ROLE(), who) &&
        poolManagerFactory.hasRole(poolManagerFactory.PRICE_ORACLE_SETTER_ROLE(), who)
    );
  }
}
