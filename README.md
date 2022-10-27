# dss-kiln

Permissionless token purchase and disposition module for protocols.

### Requirements

* [Foundry](https://github.com/foundry-rs/foundry)

### Usage

DssVest allows for dollar-cost averaging token purchases via a keeper.
Strategies are employed for purchasing and sending tokens to a wallet, or the module can be used as part of a token burn regimen.

Once deployed, the Kiln contract should be topped up with the token that is to be sold, and the contract will permit permissionless calls that periodically sell one token for another, without the need for an intermediary.

### Example Strategies

* `DssKilnUNIV3SaveStrategy`: Buy a particular token and transfer it to a wallet.
  * This strategy can be used to buy tokens over time via Uniswap V3 and transferred to an external wallet.
  * For example, a protocol may wish to buy WETH or it's own native token over time, and have those tokens returned to it's treasury.

* `DssKilnUNIV3BurnStrategy`: Buy a particular token and burn it.
  * __Note: this strategy requres that the purchased token has a `burn()` function.__
  * This strategy can be used to buy tokens over time via Uniswap V3 and the resulting tokens are burned.
  * For example, a protocol may wish to buy and burn it's own native token over time.

* `DssKilnUNIV2BurnStrategy`: A prototype burn strategy using Uniswap V2.
  * __Note: this strategy is currently susceptible to slippage if pool liquidity is low, it is currently provided as an example integration only__
