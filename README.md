# dss-kiln

Permissionless token purchase and disposition module for protocols.

### Requirements

* [Foundry](https://github.com/foundry-rs/foundry)

### Usage

DssVest allows for dollar-cost averaging token purchases via a keeper.
Strategies are employed for purchasing and sending tokens to a wallet, or the module can be used as part of a token burn regimen.

Once deployed, the Kiln contract should be topped up with the token that is to be sold, and the contract will permit permissionless calls that periodically sell one token for another, without the need for an intermediary.

#### KilnUniV3 TWAP Trading

The KilnUniV3 implementation enables trading relative to a UniswapV3 price oracle. By default, the KilnUniV3 implementation will only buy tokens when it can trade at a price better than or the same as the previous 1 hour average. These parameters can be modified by filing new `scope` and `yen` values.

The average price referred to is the multiplication product of single pool TWAP values for the given UniswapV3 routing path. As each TWAP value is not dependent on the actual swap amount, it does not incorporate price deterioration based on the total swap amount (aka price impact).

##### `scope` (Default: `3600`, i.e 1 hour)

The number of seconds to quote average price.
Warning - a low `scope` increases the susceptibility to oracle manipulation attacks.

##### `yen` (Default: `1000000000000000000`, i.e WAD, or 100%)

The amount of acceptable slippage per lot. By default, `yen` is set to `WAD`, which will require that a trade will only execute when the amount received is better than or the same as the average price over the past `scope` period. By raising this value you can seek to trade at a better than average price, or by lowering the value you can account for price impact or additional slippage.
Warning - setting `yen` as 0 or another low value highly increases the susceptibility to oracle manipulation attacks

```
// Allow up to 3% slippage over TWAP average price.
file('yen', 103 * WAD / 100);

// Only trade when the trade can be executed for 10% less than the TWAP average.
file('yen', 90 * WAD / 100);

// Disable the TWAP price calculations by setting `yen` to `0` via the `file` function.
//   Useful for quickly liquidating small lots against highly liquid pairs (i.e "just dump at whatever price").
//   This should be used only in rare cases and under great caution, see warning above.
file('yen', 0);
```
