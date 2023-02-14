# Unlocking liquidity

A core idea of Price is ensuring liquidity will behave predictably. The only way of doing this is by committing the liquidity under a series of locks, such as governance and timelock. That's why once [seeders](seeders.md) or [lockers](lockers.md) have provided liquidity for an oracle, they won't be able to claim it back immediately. Instead, they will have to go through the deprecation process for either `PoolManager` or `LockManager`. This will enable users to trust oracle long-term.

## Seeders (PoolManager)

Once the seeder deposits their positions, there is an ownership change. This liquidity becomes protocol-owned, and thus we have permits to move the funds. We can only do so under the seeder's approval.

The process will be done manually, as each case must be properly investigated and discussed in Governance. It's not the same to unlock funds due to WETH depreciation, where we move the funds to a new contract to be claimed by the seeders, as moving liquidity to Uniswap v4 or Curve.

Once discussions have settled, we will propose a migration contract. Seeders will have time to vote and decide whether or not they accept the migration. If accepted, a long timelock will begin.

## Lockers (LockManager)

LockManager will behave like a DAO which owns its funds.

As soon as a LockManager is deployed, a vote will be created to deprecated it. Initially lockers have no incentive to deprecate the LockManager but with time, in case the strategy becomes less efficient, they will vote in favor of exiting the lock and moving their funds to a new LockManager or somewhere else.

If more than 70% of the locked tokens are tuned into "leave", a timelock to unwind the position will be initialized. During this period, lockers can change their mind as many times as they wish. In the alpha version, new lockers will be accepted even after the timelock has started, but that will change in future releases.

If the LockManager is deprecated, the concentrated positions can be withdrawn from Uniswap. Then redeemed positions + non-deployed WETH + any fees left become claimable by the lockers. In parallel, a new LockManager for the pool will be initialized with a different lock ERC20, and the cycle will start again.
