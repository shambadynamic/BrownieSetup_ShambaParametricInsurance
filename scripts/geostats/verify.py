from brownie import GeoInsuranceProvider, GeoInsuranceContract

def main():
    contract = GeoInsuranceProvider[-1]
    GeoInsuranceProvider.publish_source(contract)

    contract = GeoInsuranceContract[-1]
    GeoInsuranceContract.publish_source(contract)