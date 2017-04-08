pragma solidity ^0.4.9;

/***********
* REGISTRY *
***********/
contract Registry {
    /*
        Registry to hold reference to all existing products and parties
        Utilized to initialize peer to peer communications, ex. if a product needs
        to notify a party the product would learn of the location of that party
        through the registry
        All items, product, party etc., hold reference back to the registry for exactly
        this reason
    */

    /* State Variables */
    address private owner; // eth account address
    
    /** Reference to all existing products and parties **
        mapping id to index: 
            * Utilized for lookup by the contract by name of item.  
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
    mapping(string=>uint) private productIdToIndex;
    address[] products; 
    uint productQuantity;
    
    mapping(string=>uint) private partyIdToIndex;
    address[] parties;
    uint partyQuantity;
    
    
    /* Events */
    // trying to create party that already exists
    event errorPartyIdExistsEvent(string partyId);  
    // permissioned methods mainly, if not correct addres
    event errorPermissionDeniedEvent(address callerAddress);
    // trying to create a product that already exists
    event errorProductIdExistsEvent(string productId);

    // new items added to registry
    event partyAddedEvent(string partyId);
    event productAddedEvent(string productId);
    
    
    /* Modifiers */
    modifier onlyOwner {
        // Only the eth account that owns the contract may execute
        if(msg.sender != owner){
            errorPermissionDeniedEvent(msg.sender);
            return;
        }
        _;
    }
    
    modifier productDoesNotExist(string productId){
        /*
            Confirm the product does not exist first before creating new            
            Error if this productId already exists in mapping
        */
        // default value of mapping to uint is 0
        if(productIdToIndex[productId] != 0){
            errorProductIdExistsEvent(productId);
            return;
        }    
        _;
    }

    modifier partyDoesNotExist(string partyId){
        /*
            Confirm the party does not exist first before creating new            
            Error if this partyId already exists in mapping
        */
        // default value of mapping to uint is 0
        if(partyIdToIndex[partyId] != 0){
            errorPartyIdExistsEvent(partyId);
            return;
        }    
        _;
    }
    
    
    /* Constructor */
    function Registry(){
        owner = msg.sender;
        
        // default item quantity to 1 in order to check if item already exists
        // default value of uint is 0 so array index of 0 cannot be validated
        productQuantity++;
        products.length++;
        
        partyQuantity++;
        parties.length++;
    }

    
    /* Public and External Methods */
    function addProduct(string productId) onlyOwner productDoesNotExist(productId) public{
        /*
            Create and add a new product to the registry
            Product id must be unique and not already exist
            Creates new product contract and stores reference to the address        
        */
        // add id to mapping, set to current quantity
        productIdToIndex[productId] = productQuantity;

        // create new Product contract and store address in products array
        products.push(new Product(msg.sender, productId));
        productQuantity++;
        
        productAddedEvent(productId);
    }

    function addParty(string partyId, string contactInfo) onlyOwner partyDoesNotExist(partyId) external{
        /*
            Create and add a new party to the registry
            Party id must be unique and not already exist
            Creates new party contract and stores reference to the address        
        */
        // add id to mapping, set to current quantity
        partyIdToIndex[partyId] = partyQuantity;

        // create new Party contract and store address in parties array
        parties.push(new Party(msg.sender, partyId, contactInfo));
        partyQuantity++;
        
        partyAddedEvent(partyId);
    }

    function getProductAddressList(uint startingIndex) onlyOwner external returns(address[10] productList){
        /*
            Return the list of product addresses from a starting index
            Will return the 9 preceeding addressing following the given index
            Cannot return a dynamically sized array for external methods therefore
            default length to return is 10, paginated by passing in another index
            Array starts at index 1
            - startingIndex: the index within the array to begin    
        */
        for (var i = 0; i < 10; i++){
            // if not out of range of the product list then grab the address
            if (startingIndex + i < productQuantity){
                productList[i] = products[startingIndex + i];
            }
            else{
                break;    
            }
        }
    }

    function getPartyAddressList(uint startingIndex) onlyOwner external returns(address[10] partyList){
        /*
            Return the list of party addresses from a starting index
            Will return the 9 preceeding addressing following the given index
            Cannot return a dynamically sized array for external methods therefore
            default length to return is 10, paginated by passing in another index
            Array starts at index 1
            - startingIndex: the index within the array to begin    
        */
        for (var i = 0; i < 10; i++){
            // if not out of range of the product list then grab the address
            if (startingIndex + i < partyQuantity){
                partyList[i] = parties[startingIndex + i];
            }
            else{
                break;    
            }
        }
    }


    /* TODO: for initialize party/product, do we want to create if it doesn't exist?  
    Or just utilize to return address? */
    function initializeParty(string partyId) onlyOwner external returns(address partyAddress){
        /*
            Return the address of the party contract based on id
            Does not create if the party does not exist
            Utilized in order to access the contract from the web api
        */
        if(partyIdToIndex[partyId] != 0){
                    // retrieve party index within address array and return address
            uint partyIndex = partyIdToIndex[partyId];
            partyAddress = parties[partyIndex];
        }
        else {
            partyAddress = address(0x0);
        }
    }

    function initializeProduct(string productId) onlyOwner external returns(address){
        /*
            Return the address of the product contract based on id
            Currnetly creates if the product does not exist, TBD??
            Utilized in order to access the contract from the web api
        */
        if(productIdToIndex[productId] == 0){
            addProduct(productId);
        }

        // retrieve product index within address array and return address
        uint productIndex = productIdToIndex[productId];
        return products[productIndex];
    }

    function notifyParty(string productId, string partyId, string _event) external {
        /*
            Lookup party contract and trigger notification from this product
            - productId: the product where this event originated
            - partyId: the party who is to be notified
            - _event: the event that occured to trigger this notification
        */
        var index = partyIdToIndex[partyId];

        // instantiate contract at address and notify
        Party(parties[index]).notification(productId, _event);
    }
}


/**********
* PRODUCT *
**********/
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



    /* Modifiers */
    modifier onlyOwner {
        // Only the eth that owns the contract may execute
        if(msg.sender != owner){
            errorPermissionDeniedEvent(msg.sender);
            return;
        }
        _;
    }


    /* Events */
    // permissioned methods accessed by wrong account
    event errorPermissionDeniedEvent(address accessor);
    // new data added into the data array
    event dataAddedEvent(string dataHash);
    // event in case of quantity in time interval exceeded
    event quantityLimitExceededEvent(string id, uint quantityLimit, uint quantityLimitTimeInterval);


    /* Constructor */
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
        // Party interaction routed through registry for now
        var registryContract = Registry(registry);

        for(var i = 0; i < parties.length; i++){
            registryContract.notifyParty(id, parties[i], _event);
        }
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

