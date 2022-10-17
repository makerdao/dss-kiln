# dss-kiln

Permissionless token purchase and disposition module for protocols.

### Requirements

* [Foundry](https://github.com/foundry-rs/foundry)

### Usage

DssVest allows for dollar-cost averaging token purchases via a keeper.
Strategies are employed for purchasing and sending tokens to a wallet, or the module can be used as part of a token burn regimen.

Once deployed, the Kiln contract should be topped up with the token that is to be sold, and the contract will permit permissionless calls that periodically sell one token for another, without the need for an intermediary.