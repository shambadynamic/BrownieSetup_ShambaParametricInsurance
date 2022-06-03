from brownie import FireInsuranceProvider, FireInsuranceContract

def main():
    contract = FireInsuranceProvider[-1]
    FireInsuranceProvider.publish_source(contract)

    contract = FireInsuranceContract[-1]
    FireInsuranceContract.publish_source(contract)