pragma solidity ^0.4.9;

/***********
* REGISTRY *
***********/
/// @title Registry - Core registry to house all products
/// @author Adam Lemmon <adamjlemmon@gmail.com>
contract Registry {
    /// @notice Registry to hold reference to all existing products and parties
    /// Utilized to initialize manage and track all products

    /**
    * Storage
    */
    address private owner; // eth account address

    /** Reference to all existing products and parties
        mapping id to index:
            * Utilized to lookup the contract by name.
            * Maps the string of the product/party name to the index of where its
            * contract address lives within the address array

        address array:
            * Stores all contract addresses
            * Needed in order to iterate over all products or parties.  No great way
            * to iterate over a mapping

        quantity integer:
            * Required for effecient clean up and updating of arrays
            * The above array is likely to grow and shrink dynamically, semi often
            * To update array then just set the index to default value,
            * shift elements accordingly and update this param.
    **/
    mapping(bytes32=>uint) private productIdToIndex;
    address[] products;
    uint productQuantity;

    /**
    * Events
    */
    event LogProductAddedEvent(bytes32 productId);

    /**
    * Modifiers
    */
    modifier onlyOwner {
        if (msg.sender != owner) throw;
        _;
    }

    /// @dev Error if product does exists
    modifier productDoesNotExist(bytes32 productId) {
        if(products[productIdToIndex[productId]] != address(0x0)) throw;
        _;
    }

    /// @dev Error if product does NOT exist
    modifier productExists(bytes32 productId) {
        if(products[productIdToIndex[productId]] == address(0x0)) throw;
        _;
    }


    /// @dev Constructor
    function Registry() {
        owner = msg.sender;
    }

    /// @dev Default fallback
    function () public payable { }


    /**
    * External
    */
    /// @notice Create a new product within the registry
    /// @dev Create and add a new product to the registry
    /// Product id must be unique and not already exist
    /// Creates new product contract and stores reference to the address
    /// @param productId id of product being added
    function addProduct(bytes32 productId)
      onlyOwner
      productDoesNotExist(productId)
      external
    {
        productIdToIndex[productId] = productQuantity;

        products.push(new Product(msg.sender, productId));
        productQuantity++;

        LogProductAddedEvent(productId);
    }

    /// @dev Product address
    /// @param startingIndex The index within the array to begin
    function getProduct(bytes32 productId)
      onlyOwner
      external
      returns(address product)
    {
      if (productId == 0x0) throw;

      uint productIndex = productIdToIndex[productId];
      product = productList[productIndex];
    }

    /*
        Return the address of the product contract based on id
        Currently creates if the product does not exist, TBD??
        Utilized in order to access the contract from the web api
    */
    function initializeProduct(string productId)
      onlyOwner
      external
      returns(address)
    {
        if(productIdToIndex[productId] == 0){
            addProduct(productId);
        }

        // retrieve product index within address array and return address
        uint productIndex = productIdToIndex[productId];
        return products[productIndex];
    }
}


/// @title Product
contract Product {
    /*
        Represents a unique product as contained within the registry
        Contains:
            - a history of all acquired data of its type
            - associations to parties
            - specific rules or constraints it must abide by
    */

    /* State Variables */
    // identifier for this specific product, must be unique
    // utilized to store and lookup by application server
    string public id;

    address private owner;

    // hold reference back to the repo for access to other contracts
    address private registry;

    // TODO: how to lookup data?? Store some mapping to define index, store structs with
    // 'queryable' attributes
    // TODO Consider just storing merkle root perhaps?? Define storage limits.
    // array of encrypted data hashes
    string[] private dataHistory;

    // 1 to 1 mapping of data hashes to timestamps
    // Utilized for quick lookup to confirm limits not exceeded
    uint[] private dataTimestamps; // microseconds

    // Restrictions for each product
    // The quantity limit that may not be exceeded within a time interval
    uint private quantityLimit;

    // An interval where there is a limit in production quantity
    uint private quantityLimitTimeInterval;

    // array of associated parties, these will be notified when events occur
    // Eg. if quantity limit is exceed an email will be sent to these parties
    string[] private parties;



    /**
    * Modifiers
    */
    modifier onlyOwner {
        // Only the eth that owns the contract may execute
        if(msg.sender != owner){
            errorPermissionDeniedEvent(msg.sender);
            return;
        }
        _;
    }


    /**
    * Events
    */
    event errorPermissionDeniedEvent(address accessor);
    event dataAddedEvent(string dataHash);
    event quantityLimitExceededEvent(
      string id,
      uint quantityLimit,
      uint quantityLimitTimeInterval
    );


    /// @dev Constructor
    function Product(address _owner, string _id){
        // TODO: who should own?  Default now to the owner of the registry
        owner = _owner;
        id = _id;

        // ** Demo static limits **
        quantityLimit = 3;
        quantityLimitTimeInterval = 5000000; // 5s in micro seconds

        // product are only created through the registry!
        registry = msg.sender;
    }


    /* Private and External Methods */
    // TODO: permissioning, consider defining an account specific to this product??
    function addData(string dataHash, uint timestamp) external returns(uint){
        /*
            Add a new data hash into data history
            Accompanied by a timestamp in order to confirm limits within time intervals
            - dataHash: hash of the data to be utilized by server for lookup of raw data
            - timestamp: represents the timestamp as an interger in microseconds
        */
        dataHistory.push(dataHash);
        dataTimestamps.push(timestamp);

        dataAddedEvent(dataHash);

        // if the length is greater than the quantity limit check if it has been exceeded
        if (dataHistory.length > quantityLimit){
            // check if the quantityLimit has been exceeded
            // retrieve the index of the timestamp to compare
            uint quantityLimitIndex = dataHistory.length - 1- quantityLimit;

            // If the difference is less than the limit it has been exceeded
            // Too many products have been added in the time interval
            if ((timestamp - dataTimestamps[quantityLimitIndex]) < quantityLimitTimeInterval){
                // Notify associated parties of this event
                notifyParties('Quantity limit exceeded!');

                // publish event
                quantityLimitExceededEvent(id, quantityLimit, quantityLimitTimeInterval);
            }
        }
    }

    function addPartyAssociation(string partyId) external {
        /*
            Add an association with a party contract
            Very basic for initial demo pursposes
            This party may have specific priviledges or receive specific notifications
            TBD
            - partyId: the party to add to this product
        */
        parties.push(partyId);
    }

    // TODO: define this!! Permission it.
    function getData() onlyOwner constant returns(string latestData){
        /*
            Retrieve data from this product
            TODO: consider advanced queries for lookup
            Currently returns the latest dataHash
        */
        // if data exists return the latest
        if(dataHistory.length > 0){
            latestData = dataHistory[dataHistory.length - 1];
        }
        else {
            latestData = 'Error: No data exists!';
        }
    }

    function notifyParties(string _event) private{
        /*
            Iterate overall all existing parties and notify them of this event
            - _event: the event within this product that has occured
        */
    }
}


/********
* PARTY *
********/
contract Party {
    /*
        Represent a physical entity, human, business, etc. that is associated with
        some sort of contact information, email for example
        Party may be associated with a given product in order to receive notifications
        of events
    */
    // identifier for this specific party, must be unique, consider private and permissioning
    // utilized to store and lookup by application server
    string public id;

    address private owner;

    // hold reference back to the registry for permissioning and for access to other contracts
    address private registry;

    // encrypted contact information used in case of event notifications
    string private contactInfo;


    /* Modifiers */
    modifier onlyRegistry {
        // Only the eth that owns the contract may execute
        if(msg.sender != registry){
            errorPermissionDeniedEvent(msg.sender);
            return;
        }
        _;
    }


    /* Events */
    // when incorrect account accesses a permissioned method
    event errorPermissionDeniedEvent(address accessor);

    // This party has been notified of some event
    // Currently utilized to get the contactInfo and send email
    event notificationEvent(string productId, string _event, string contactInfo);


    /* Constructor */
    function Party(address _owner, string _id, string _contactInfo){
        // TODO: who should own?  Default now to the owner of the registry
        owner = _owner;
        contactInfo = _contactInfo;
        id = _id;

        // parties are only created through the registry!
        registry = msg.sender;
    }


    /* Methods */
    function notification(string productId, string _event) onlyRegistry{
        /*
            To be expanded significatly, bare bones here for demo purposes
            Notifications only routed through registry for time being
        */
        notificationEvent(productId, _event, contactInfo);
    }
}
