# Oracle

Historically, oracles suffered from the security-precision tradeoff. Price comes to put an end to that discussion. With manipulation detection in place, the oracle is manipulation-cost agnostic. This paradigm shift unlocks the safe use of higher precision queries (shorter TWAPs). This point is crucial to many applications which are nowadays impossible to implement due to the lack of precision.

Price introduces signal processing jobs that filter potential TWAP manipulations, including the notorious PoS multi-block attack. As mentioned in the [Fee Management](fee-management.md) section, the jobs are paid for automatically with the fees generated from the positions. Another convenient addition is a cache that enables shared gas cost for queries and reduces the cost for the most popular queried pools.

## High-level overview

The oracle introduces a 2-minute delay that enables keepers to capture up to a 9-block manipulation pattern, which includes multi-block attacks. The automated job detects and corrects the observation array with the proper non-manipulated values in case of manipulation-like movements.

Corrections are designed to make false-positive triggers harmless and almost desirable as they erase spurious price data. Other protocols have suggested using medians as an alternative to the standard TWAP to filter away multi-block attacks. But

- Median filters away fast movements but cannot differentiate manipulations from legitimate price swings.
- Medians are always laggier and less precise than TWAPs.
- Medians are not smooth, a desirable property for many use cases, for instance, Dutch auction liquidations.
- It's expensive to implement as a standalone solution. To function with an acceptable cost, we would need a dedicated AMM with native support for medians.

### How do you query the oracle for a certain token?

In order to get a quote from the oracle, you have to call the function [`quote`](../../solidity/interfaces/periphery/IPriceOracle.sol/contract.IPriceOracle.md#quote). Refer to the docs to find out what arguments the function takes. It's worth nothing that you should be careful with the chosen TWAP length, because querying TWAP longer than 2 weeks may result in the manipulated vales being accounted for without any protection.

Also note that only pools supported by Price can be queries at the moment. If your project needs a price feed for a token that doesn't have an oracle yet, you can either seed the pool yourself or approach the protocol to ask them to create the oracle.

## Manipulation correction

Protocols usually only check if TWAP has much difference from spot to revert. This approach has several issues:
- It reverts (halts everything)
- If it's not enough to revert, the manipulation can still lead to TWAPs having unreal values
- It is not enough, for instance, an array of observations like [1, 100, 10] will have TWAP equal to spot and not revert
- This type of check does not consider multiblock manipulations, which eventually expire partially and create imbalanced TWAPs

Our solution is to set up a Keep3r job that looks for clear manipulation patterns and corrects the queried data to ignore the attack completely. The job will be super well-paid to incentivize keepers.

The keeper running the job will have to provide the indexes of the manipulated observations.

Then for each manipulation index we check

1. If the manipulated observation is considerably higher/lower than the one before it. We can compare the value of the tick before and at the manipulated observation, extracted from the accumulators and timestamps. A 10% price change is set as a threshold. This percentage will avoid a "staircase attack" that's distributed among several blocks to avoid being detected.

2. If the manipulated observation is considerably higher/lower than the observation after the manipulation. Again, we use the 10% threshold.

3. If the observations before and after the manipulation are similar. We will not be that rigorous here, as arbitrage might be slow, and will check the difference is smaller than 20% to leave more wiggle room for arbitrage.

4. If the observation before and after the manipulation are not affected. Those values are in sync with the thresholds used for the previous checks, as the TWAP corrected will average the before and after values. We computed this to be 23.5%.

If the oracles's user queries a time that overlaps the manipulation indexes, we will automatically return a TWAP to exclude this manipulation. We don't care if observations in between edges are manipulated or not, the correction will be applied for the whole chunk where manipulated edges were detected.

Triggering false positives is not a problem. A false positive would occur if the price jumps discretely 10% in a block and then falls back strong this same percentage. Correcting these false positives will only improve precision and avoid triggering false positives.

Once detected, we will "patch" the accumulator using the average tick value surrounding the manipulation.
