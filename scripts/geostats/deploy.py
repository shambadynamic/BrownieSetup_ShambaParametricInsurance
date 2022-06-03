from brownie import GeoInsuranceProvider, GeoInsuranceContract, config, accounts

def main():
    deployer_account = accounts.add(config["wallets"]["from_key"]) or accounts[0]
    print(deployer_account.address)
    contract = GeoInsuranceProvider.deploy({'from': deployer_account})
    print("Deployed at: ", contract.address)
    contract = GeoInsuranceContract.deploy("0xE447E5358e612De3E54f49942733484A503609f5", 300, 5000000000, 10000000000, "0xa36085F69e2889c224210F603D836748e7dC0088", 1000000000000000000, {'from': deployer_account})
    print("Deployed at: ", contract.address)
