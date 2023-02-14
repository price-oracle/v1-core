# Seeding

A protocol or any other interested party that wishes to use Price for a particular token will need to lock liquidity. This will

1. Initialize the Uniswap V3 pool if it does not exist already
2. Increase the observation array up to a safe length if not already there
3. Add tokens to be used as a full-range position

We call this process **seeding** and the WETH/tokens provided to the full-range position **seeded liquidity**.

## How do I seed?

Let's say I have a token called RICH and I need to build some smart contract that quotes 1 WETH to RICH tokens, using a 5-minute TWAP. I heard about Price and I wanna use it for my use case. As I have tons of money, I wouldn't have an issue seeding the liquidity myself. What steps should I follow, until I have everything I need to develop my smart contract?

1. Visit [the seeding page](https://oracles.rip/app/seed-liquidity) and create the price pool by seeding the minimum amount of liquidity. The transaction will take care of everything for the pool to be healthy, with a good liquidity positioning, and a bigger cardinality array
2. Now your pair is officially supported by Price. You can double check it by querying `PriceOracle.isPairSupported(WETH, RICH)`. The address of the oracle contract can be found in the [contracts registry](/content/smart-contracts/addresses.md).
3. It is as simple as that! Now, in your smart-contract you can utilize the `PriceOracle` functions in order to query safely. For example, `PriceOracle.quotePeriod(1 ether, WETH, RICH, 10 minutes)`. If you want to cache the TWAP response, or look at other query possibilities, make sure to check the [PriceOracle interface documentation](/solidity/interfaces/periphery/IPriceOracle.sol/contract.IPriceOracle.md).

### Minimum liquidity requirement

The full-range liquidity and TWAP length are the primary safety net against price manipulation. A manipulation detection job makes sense only after meeting some basic security standards.

For the first deposit, we will require minimum total liquidity of **50 WETH**, half in the specific token, half in WETH. This is a safe amount to justify the gas costs for maintenance.
With this requirement, we want to make a manipulation extremely expensive, have a basic precision standard on the price (arbitrage) and generate enough fees to trigger the maintenance jobs with a target frequency. The minimum liquidity requirement will probably be fine-tuned in future versions.

If at some point the position's value drops significantly, the only net result will be a decline on the job's frequency. The protocol is designed to be sustainable independently of the trading volume or the locked value.

### What happens if the pool already exists?

A pool might be already created by another user directly in Uniswap. We are not worried about this, and the contracts & UI will be able to recognize it. In this case, cardinality will be increased from the starting point onward, and the current price will be taken for reference. If a malicious user front-runs the pool creation with a bad price, they will get arbitraged. There will then be no incentive to do something like this.

## Fee management
The fees from the full-range position will be [automatically managed](fee-management.md) to improve the oracle's health.

The seeders can claim some of the fees as rewards but cannot withdraw the funds at will, making liquidity reliable for oracle's users. From the seeder's perspective, they commit the liquidity in exchange for trust from lending markets and other oracle's users, and fees. This trust will eventually translate into token usage and demand.

### Unlocking

Seeders can vote to migrate funds, which might be necessary for moving the liquidity to future versions of Uniswap or Price. This could also be used as an escape hatch in case of protocol deprecation. Price can only propose a migration, which the seeders will vote on, and any liquidity movement will be protected with a long timelock.

For more details on this process, read [Unlocking](unlocking.md).
