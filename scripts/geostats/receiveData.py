from brownie import GeoInsuranceContract, config, accounts

def printGeoData(insuranceContract, deployer_account):

    tx = insuranceContract.getShambaGeostatsData({'from': deployer_account})

    geoData = tx.events['dataReceived']['_geostats']

    if geoData != 0:
        print(geoData)
    else:
        print("Data isn't available yet. Please check the job run in the oracle node.")
        
def printLatestCid(insuranceContract):
    print(insuranceContract.getLatestCid())


def main():
    deployer_account = accounts.add(config["wallets"]["from_key"]) or accounts[0]
    print(deployer_account.address)
    insuranceContract = GeoInsuranceContract[-1]

    printGeoData(insuranceContract, deployer_account)
    printLatestCid(insuranceContract)