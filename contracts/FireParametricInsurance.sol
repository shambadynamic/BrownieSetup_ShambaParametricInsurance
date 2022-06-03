// SPDX-License-Identifier: MIT

pragma solidity ^0.8.7;

pragma experimental ABIEncoderV2;

import "@chainlink/contracts/src/v0.8/interfaces/LinkTokenInterface.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorInterface.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@shamba/contracts/ShambaFireConsumer.sol";

contract FireInsuranceProvider {
    
    address public insurer = msg.sender;
    AggregatorV3Interface internal priceFeed;

    uint public constant DAY_IN_SECONDS = 60; //How many seconds in a day. 60 for testing, 86400 for Production
    
    uint256 constant private ORACLE_PAYMENT = 0.1 * 10**19; // 1 LINK
    address public constant LINK_KOVAN = 0xa36085F69e2889c224210F603D836748e7dC0088 ; //address of LINK token on Kovan
    
    //here is where all the insurance contracts are stored.
    mapping (address => FireInsuranceContract) contracts; 
    
    
    constructor()  payable {
        priceFeed = AggregatorV3Interface(0x9326BFA02ADD2366b30bacB125260Af641031331);
    }

    /**
     * @dev Prevents a function being run unless it's called by the Insurance Provider
     */
    modifier onlyOwner() {
		require(insurer == msg.sender,'Only Insurance provider can do this');
        _;
    }
    

   /**
    * @dev Event to log when a contract is created
    */    
    event contractCreated(address _insuranceContract, uint _premium, uint _totalCover);
    
    
    /**
     * @dev Create a new contract for client, automatically approved and deployed to the blockchain
     */ 
    function newContract(address payable _client, uint _duration, uint _premium, uint _payoutValue) public payable onlyOwner() returns(address) {
        

        //create contract, send payout amount so contract is fully funded plus a small buffer
        FireInsuranceContract i = (new FireInsuranceContract){value:((_payoutValue * 1 ether) / (uint(getLatestPrice())))}(_client, _duration, _premium, _payoutValue, LINK_KOVAN,ORACLE_PAYMENT);
         
        contracts[address(i)] = i;  //store insurance contract in contracts Map
        
        //emit an event to say the contract has been created and funded
        emit contractCreated(address(i), msg.value, _payoutValue);
        
        //now that contract has been created, we need to fund it with enough LINK tokens to fulfil 1 Oracle request per day, with a small buffer added
        LinkTokenInterface link = LinkTokenInterface(i.getChainlinkToken());
        link.transfer(address(i), ((_duration / DAY_IN_SECONDS) + 2) * ORACLE_PAYMENT * 2);
        
        
        return address(i);
        
    }
    

    /**
     * @dev returns the contract for a given address
     */
    function getContract(address _contract) external view returns (FireInsuranceContract) {
        return contracts[_contract];
    }
    
    /**
     * @dev updates the contract for a given address
     */
    function updateContract(address _contract,
        string memory dataset_code,
        string memory selected_band,
        string memory image_scale,
        string memory start_date,
        string memory end_date,
        ShambaFireConsumer.Geometry[] memory geometry
    ) external {
        FireInsuranceContract i = FireInsuranceContract(_contract);
        i.updateContract(dataset_code, selected_band, image_scale, start_date, end_date, geometry);
    }
    
    /**
     * @dev gets the current fire for a given contract address
     */
    function getContractFire(address _contract) external view returns(uint) {
        FireInsuranceContract i = FireInsuranceContract(_contract);
        return i.getCurrentFire();
    }
    
    /**
     * @dev gets the current fire for a given contract address
     */
    function getContractRequestCount(address _contract) external view returns(uint) {
        FireInsuranceContract i = FireInsuranceContract(_contract);
        return i.getRequestCount();
    }
    
    
    
    /**
     * @dev Get the insurer address for this insurance provider
     */
    function getInsurer() external view returns (address) {
        return insurer;
    }
    
    
    
    /**
     * @dev Get the status of a given Contract
     */
    function getContractStatus(address _address) external view returns (bool) {
        FireInsuranceContract i = FireInsuranceContract(_address);
        return i.getContractStatus();
    }
    
    /**
     * @dev Return how much ether is in this master contract
     */
    function getContractBalance() external view returns (uint) {
        return address(this).balance;
    }
    
    /**
     * @dev Function to end provider contract, in case of bugs or needing to update logic etc, funds are returned to insurance provider, including any remaining LINK tokens
     */
    function endContractProvider() external payable onlyOwner() {
        LinkTokenInterface link = LinkTokenInterface(LINK_KOVAN);
        require(link.transfer(msg.sender, link.balanceOf(address(this))), "Unable to transfer");
        selfdestruct(payable(insurer));
    }
    
    event latestPriceReceived(uint80 roundID, 
            int price,
            uint startedAt,
            uint timeStamp,
            uint80 answeredInRound);

    /**
     * Returns the latest price
     */
    function getLatestPrice() public returns (int) {
        (
            uint80 roundID, 
            int price,
            uint startedAt,
            uint timeStamp,
            uint80 answeredInRound
        ) = priceFeed.latestRoundData();
        // If the round is not complete yet, timestamp is 0

        emit latestPriceReceived(roundID, price, startedAt, timeStamp, answeredInRound);
        
        require(timeStamp > 0, "Round not complete");
        return price;
    }
    

}


contract FireInsuranceContract is ShambaFireConsumer  {

    AggregatorV3Interface internal priceFeed;
    
    uint public constant DAY_IN_SECONDS = 60; //How many seconds in a day. 60 for testing, 86400 for Production
    uint public constant FIRE_DAYS_THRESDHOLD = 3 ;  //Number of consecutive days without fire data to be defined as a drought
    uint256 private oraclePaymentAmount;

    address payable public insurer;
    address payable client;
    uint startDate;
    uint duration;
    uint premium;
    uint payoutValue;
    
    
    uint daysWithFire;                   //how many days there has been with 0 fire
    bool contractActive;                    //is the contract currently active, or has it ended
    bool contractPaid = false;
    uint currentFire = 0;               //what is the current fire for the location
    uint currentFireDateChecked = block.timestamp;  //when the last fire check was performed
    uint requestCount = 0;                  //how many requests for fire data have been made so far for this insurance contract
    uint dataRequestsSent = 0;             //variable used to determine if both requests have been sent or not
    

    /**
     * @dev Prevents a function being run unless it's called by Insurance Provider
     */
    modifier onlyOwner() {
		require(insurer == msg.sender,'Only Insurance provider can do this');
        _;
    }
    
    /**
     * @dev Prevents a function being run unless the Insurance Contract duration has been reached
     */
    modifier onContractEnded() {
        if (startDate + duration < block.timestamp) {
          _;  
        } 
    }
    
    /**
     * @dev Prevents a function being run unless contract is still active
     */
    modifier onContractActive() {
        require(contractActive == true ,'Contract has ended, cant interact with it anymore');
        _;
    }

    /**
     * @dev Prevents a data request to be called unless it's been a day since the last call (to avoid spamming and spoofing results)
     * apply a tolerance of 2/24 of a day or 2 hours.
     */    
    modifier callFrequencyOncePerDay() {
        require((block.timestamp - currentFireDateChecked) > (DAY_IN_SECONDS - (DAY_IN_SECONDS / 12)),'Can only check fire once per day');
        _;
    }
    
    event contractCreated(address _insurer, address _client, uint _duration, uint _premium, uint _totalCover);
    event contractPaidOut(uint _paidTime, uint _totalPaid, uint _finalFire);
    event contractEnded(uint _endTime, uint _totalReturned);
    event fireThresholdReset(uint _fire);
    event dataRequestSent(bytes32 requestId);
    event dataReceived(uint _fire);
    

    int256 private fire_data;
    string private cid;

    mapping(uint256 => string) private cids;


     /**
     * @dev Creates a new Insurance contract
     */ 
    constructor(address payable _client, uint _duration, uint _premium, uint _payoutValue, 
                address _link, uint256 _oraclePaymentAmount)  payable {
        
        //set ETH/USD Price Feed
        priceFeed = AggregatorV3Interface(0x9326BFA02ADD2366b30bacB125260Af641031331);
        
        //initialize variables required for Chainlink Network interaction
        setChainlinkToken(_link);
        
        oraclePaymentAmount = _oraclePaymentAmount;
        
        //first ensure insurer has fully funded the contract
        require(msg.value >= _payoutValue / uint(getLatestPrice()), "Not enough funds sent to contract");
        
        //now initialize values for the contract
        insurer= payable(msg.sender);
        client = _client;
        startDate = block.timestamp; //contract will be effective immediately on creation
        duration = _duration;
        premium = _premium;
        payoutValue = _payoutValue;
        daysWithFire = 0;
        contractActive = true;
        
        
        emit contractCreated(insurer,
                             client,
                             duration,
                             premium,
                             payoutValue);
    }
    
   /**
     * @dev Calls out to an Oracle to obtain weather data
     */ 
    function updateContract(
        string memory dataset_code,
        string memory selected_band,
        string memory image_scale,
        string memory start_date,
        string memory end_date,
        ShambaFireConsumer.Geometry[] memory geometry
    ) public onContractActive() returns (bytes32 requestId)   {
        //first call end contract in case of insurance contract duration expiring, if it hasn't then this functin execution will resume
        checkEndContract();
        
        //contract may have been marked inactive above, only do request if needed
        if (contractActive) {
            dataRequestsSent = 0;    
            checkFire(dataset_code, selected_band, image_scale, start_date, end_date, geometry);
        }

        return requestId;
    }
    
    /**
     * @dev Calls the requestFireData function of the imported ShambaFireConsumer contract with the corresponding parameters
     */ 
    function checkFire(
        string memory dataset_code,
        string memory selected_band,
        string memory image_scale,
        string memory start_date,
        string memory end_date,
        Geometry[] memory geometry
    ) private onContractActive()   {


        //First build up a request to get the current fire
        ShambaFireConsumer.requestFireData(dataset_code, selected_band, image_scale, start_date, end_date, geometry);

    }
    

    /**
     * @dev 
     * This function will return the latest content id of the metadata that is being stored on the filecoin ipfs
     */ 

    function getLatestCid() public view returns (string memory) {
        return ShambaFireConsumer.getCid(total_oracle_calls - 1);
    }

    /**
     * @dev 
     * This function will return the current fire data returned by the getFireData function of the imported ShambaFireConsumer contract
     */ 

    function getShambaFireData(uint256 propertyID) public returns (uint256) {

        currentFire = ShambaFireConsumer.getFireData(propertyID);

        if (currentFire == 1) { //temp threshold has been  met, add a day of over threshold
              daysWithFire += 1;
        } 
        
        else {
              //there was no fire today, so reset daysWithFire parameter 
              daysWithFire = 0;
              emit fireThresholdReset(currentFire);
        }
       
        if (daysWithFire >= FIRE_DAYS_THRESDHOLD) {  // day threshold has been met
              //need to pay client out insurance amount
              payOutContract();
        } 

        emit dataReceived(currentFire);

        return currentFire;

    }
    
    
    /**
     * @dev Insurance conditions have been met, do payout of total cover amount to client
     */ 
    function payOutContract() private onContractActive()  {
        
        //Transfer agreed amount to client
        client.transfer(address(this).balance);
        
        //Transfer any remaining funds (premium) back to Insurer
        LinkTokenInterface link = LinkTokenInterface(chainlinkTokenAddress());
        require(link.transfer(insurer, link.balanceOf(address(this))), "Unable to transfer");
        
        emit contractPaidOut(block.timestamp, payoutValue, currentFire);
        
        //now that amount has been transferred, can end the contract 
        //mark contract as ended, so no future calls can be done
        contractActive = false;
        contractPaid = true;
    
    }  
    
    /**
     * @dev Insurance conditions have not been met, and contract expired, end contract and return funds
     */ 
    function checkEndContract() private onContractEnded()   {
        //Insurer needs to have performed at least 1 weather call per day to be eligible to retrieve funds back.
        //We will allow for 1 missed weather call to account for unexpected issues on a given day.
        if (requestCount >= (duration / DAY_IN_SECONDS) - 2) {
            //return funds back to insurance provider then end/kill the contract
            insurer.transfer(address(this).balance);
        } else { //insurer hasn't done the minimum number of data requests, client is eligible to receive his premium back
            // need to use ETH/USD price feed to calculate ETH amount
            client.transfer(premium / uint(getLatestPrice()));
            insurer.transfer(address(this).balance);
        }
        
        //transfer any remaining LINK tokens back to the insurer
        LinkTokenInterface link = LinkTokenInterface(chainlinkTokenAddress());
        require(link.transfer(insurer, link.balanceOf(address(this))), "Unable to transfer remaining LINK tokens");
        
        //mark contract as ended, so no future state changes can occur on the contract
        contractActive = false;
        emit contractEnded(block.timestamp, address(this).balance);
    }
    event latestPriceReceived(uint80 roundID, 
            int price,
            uint startedAt,
            uint timeStamp,
            uint80 answeredInRound);
    /**
     * Returns the latest price
     */
    function getLatestPrice() public returns (int) {
        (
            uint80 roundID, 
            int price,
            uint startedAt,
            uint timeStamp,
            uint80 answeredInRound
        ) = priceFeed.latestRoundData();
        // If the round is not complete yet, timestamp is 0
        emit latestPriceReceived(roundID, price, startedAt, timeStamp, answeredInRound);
        require(timeStamp > 0, "Round not complete");
        return price;
    }
    
    
    /**
     * @dev Get the balance of the contract
     */ 
    function getContractBalance() external view returns (uint) {
        return address(this).balance;
    } 
    
    
    /**
     * @dev Get the Total Cover
     */ 
    function getPayoutValue() external view returns (uint) {
        return payoutValue;
    } 
    
    
    /**
     * @dev Get the Premium paid
     */ 
    function getPremium() external view returns (uint) {
        return premium;
    } 
    
    /**
     * @dev Get the status of the contract
     */ 
    function getContractStatus() external view returns (bool) {
        return contractActive;
    }
    
    /**
     * @dev Get whether the contract has been paid out or not
     */ 
    function getContractPaid() external view returns (bool) {
        return contractPaid;
    }
    
    
    /**
     * @dev Get the current recorded fire for the contract
     */ 
    function getCurrentFire() external view returns (uint) {
        return currentFire;
    }
    
    /**
     * @dev Get the recorded number of days without fire
     */ 
    function getDaysWithFire() external view returns (uint) {
        return daysWithFire;
    }
    
    /**
     * @dev Get the count of requests that has occured for the Insurance Contract
     */ 
    function getRequestCount() external view returns (uint) {
        return requestCount;
    }
    
    /**
     * @dev Get the last time that the fire was checked for the contract
     */ 
    function getCurrentFireDateChecked() external view returns (uint) {
        return currentFireDateChecked;
    }
    
    /**
     * @dev Get the contract duration
     */ 
    function getDuration() external view returns (uint) {
        return duration;
    }
    
    /**
     * @dev Get the contract start date
     */ 
    function getContractStartDate() external view returns (uint) {
        return startDate;
    }
    
    /**
     * @dev Get the current date/time according to the blockchain
     */ 
    function getNow() external view returns (uint) {
        return block.timestamp;
    }
    
    /**
     * @dev Get address of the chainlink token
     */ 
    function getChainlinkToken() public view returns (address) {
        return chainlinkTokenAddress();
    }
    
    /**
     * @dev Helper function for converting a string to a bytes32 object
     */ 
    function stringToBytes32(string memory source) private pure returns (bytes32 result) {
        bytes memory tempEmptyStringTest = bytes(source);
        if (tempEmptyStringTest.length == 0) {
         return 0x0;
        }

        assembly { // solhint-disable-line no-inline-assembly
        result := mload(add(source, 32))
        }
    }
}