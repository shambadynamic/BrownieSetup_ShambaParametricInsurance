from brownie import FireInsuranceContract, config, accounts

def printFireData(insuranceContract, propertyId, deployer_account):

    tx = insuranceContract.getShambaFireData(propertyId, {'from': deployer_account})

    fireData = tx.events['dataReceived']['_fire']

    if fireData != 0:
        print(fireData)
    else:
        print("Either the Property Id " + str(propertyId) + " does not exist or the data isn't available yet, please check the job run in the oracle node.")
        
def printLatestCid(insuranceContract):
    print(insuranceContract.getLatestCid())


def main():
    deployer_account = accounts.add(config["wallets"]["from_key"]) or accounts[0]
    print(deployer_account.address)
    insuranceContract = FireInsuranceContract[-1]

    printFireData(insuranceContract, 1, deployer_account)
    printLatestCid(insuranceContract)