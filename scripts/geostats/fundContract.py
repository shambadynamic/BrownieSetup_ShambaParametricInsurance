from brownie import MyLinkToken, GeoInsuranceContract, config, accounts

def fundContract(insuranceContract, deployer_account):
    link = MyLinkToken.at("0xa36085F69e2889c224210F603D836748e7dC0088")
    link.transfer(insuranceContract, 3*1e18, {'from': deployer_account})

def main():
    deployer_account = accounts.add(config["wallets"]["from_key"]) or accounts[0]
    print(deployer_account.address)
    insuranceContract = GeoInsuranceContract[-1]
    fundContract(insuranceContract, deployer_account)
    


    