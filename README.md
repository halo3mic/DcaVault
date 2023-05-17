# DCA Vault [POC]

> Warning! ⚠️ This is experimental code and should not be trused with real funds.

## About

Dollar-cost-average(DCA) vault is a smart contract allowing multiple parties sharing execution of reccuring swaps at the oracle price. 


## How it works

1. Users(makers) deposit funds
   * They set reccuring amount and amount of epochs swap will be spread over.

2. Each new epoch reccuring amount from all users is unlocked for swapping

3. Anyone can swap unlocked funds at the oracle price 

4. Makers can withdraw take-token without closing their position 
5. Makers can close their position prematurely 

## Tests

To run tests forge must be installed. Follow guide [here](https://book.getfoundry.sh/getting-started/installation).

#### Test the scenario
```bash 
forge test --match-test testScenarioB
```

## Contact

Twitter: [@MihaLotric](https://twitter.com/MihaLotric)