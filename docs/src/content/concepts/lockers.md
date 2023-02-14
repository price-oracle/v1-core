# Locking

Any user can **lock WETH** to the seeded pools, this liquidity will automatically generate **concentrated positions**. The protocol can function without lockers, it's just an extra mechanism for improving the oracles.

Lockers will receive an ERC-20 lock token that will allow them to claim their corresponding fees. They will not be able to claim their WETH back immediately after locking, but they can collectively vote to close the position. If the majority votes in favor of it, all lockers can redeem their share of the position.

Locked liquidity will behave in a shared and predictable way. This liquidity will follow a low-risk profile in the alpha release, but we expect to develop different strategies that lockers can choose. Eventually, strategies should be open for anyone to create/integrate with existing Uniswap LP management strategies. See [Strategy](strategy.md) for more details.

If you want to lock liquidity, visit [the pools page](https://oracles.rip/app/pools) and choose the pool you're interested in.

### How does concentrated liquidity improve an oracle?

As we mentioned in our [blog posts](https://price-oracle.notion.site/bc7441a9468d4eab9631c865fda3a26c), concentrated liquidity increases capital efficiency for LPs but makes manipulation easier. Think of it as selling more capital at an average lower price. Why do we need concentrated positions, then?

To answer that question, we must remember that arbitrage is at the core of the oracle, as it allows information to travel on-chain. Arbitrage is what ultimately replaces nodes from regular oracles. Even though the protocol could work perfectly fine without lockers, concentrated liquidity creates a crucial advantage: deeper liquidity close to the active range will make arbitrage more efficient as more volume is available. Having more liquidity will result in a more precise value for the oracle. This will incentivize seeders and oracle users to lock or further bribe the lockers.

### Why would someone lock via Price instead of directly on Uniswap?

1. All complexity from the concentrated positions will get abstracted away from the lockers. This includes fees, gas costs, and position management.
2. Deploying liquidity into a specific position is a bet on the market which could be wrong. By creating several positions distributed in time, they're lowering their risk, effectively DCAing the LP.
3. Additionally, we will introduce "bribe" contracts for anyone to give additional rewards to the lockers. Seeders that wish to have more concentrated liquidity are incentivized to "bribe" the lockers in this way.

### Unlocking

Users cannot withdraw their WETH unless most lockers choose to do so. Users are gathering and joining a strategy we will manage in a predetermined way. Think of it like a hedge fund, where users give their capital to be managed by the fund. Sometimes individual users can not withdraw if the capital is deployed to a strategy, but they can if the majority wishes.

Each address is assigned to a boolean, signalling a stay-leave vote. This parameter defaults to stay but can be changed to leave at any time by the user. If more than X% of the users have voted to leave, the funds become available for claiming. No one else can add liquidity to this LockManager. A new LockManager is initialized for those who wish to remain in the pool.

To make on- and off-ramping easier, we will launch a secondary market for users to trade these lock tokens at a discount at any time. Sellers can exit their position with a profit if fees were larger than the discount, and buyers can get in with zero-risk leveraged exposure to fees.

More details [here](unlocking.md).
