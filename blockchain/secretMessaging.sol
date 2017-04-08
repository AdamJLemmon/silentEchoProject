pragma solidity ^0.4.9;

// TODO: Modifiers / permissioning, tight!
/*******
* REPO *
*******/
contract SecretMessageRepo {
    address owner;  // eth account address
    
    // mapping for all users, unique id to contract addresses
    mapping(string=>address) userIdToAddress;
    
    
    /* EVENTS */
    event messageReadEvent(string senderContactInfo, bytes32 messageId);
    event messageSentEvent(bytes32 messageId);
    event userCreatedEvent(string userId);
    event userRemovedEvent(string userId);
    
    
    /* CONSTRUCTOR */
    function SecretMessageRepo(){
        owner = msg.sender;
    }

    
    /* METHODS */
    function createUser (
        address userAccountAddress,
        string userId, 
        string contactInfo,
        bool persisted
    ) 
        /** Notes **
            * address userAccountAddress *: 
            eth account address, used to permission access. User
            must unlock this account and then use address as "token" essentially. This is required
            because all transactions are sent from 1 fueling eth account so that the float for each
            user does NOT need to be maintained.  Only the fueling account needs ether.
            
            * string userId *:  
            unique identifier for user, auto generated in case of temp user.
            used to lookup contract address in repo mapping
            
            * string contactInfo *: 
            some way to notify user, email or phone #
            
            * bool persisted *: 
            whether or not this user is a temp contract created for a user that does
            not exist in the repo. Used to define if the contract should be killed following a read
        **/
    {
        // confirm userId does not already exist
        if(userExists(userId)) throw;
        
        // create new user contract mapped to userId. new returns address
        userIdToAddress[userId] = new SecretMessageUser({
            _owner: userAccountAddress,
            _id: userId,
            _contactInfo: contactInfo, 
            _persisted: persisted
        });
        
        userCreatedEvent(userId);
    }
    
    function getUserContractAddress(
        address userAccountAddress, string userId
    ) onlyUserContractOwner(userAccountAddress, userId) returns(address) 
    /** Notes **
        Utilized when user is logging in. This must be the correct user account
        attempting to retrieve the address of a valid user contract
    **/
    {
        if(!userExists(userId)) throw;

        return userIdToAddress[userId];
    }

    function notificationMessageRead(string senderContactInfo, bytes32 messageId) external {
        messageReadEvent(senderContactInfo, messageId);
    }
    
    function sendMessage(
        address recipientAccountAddress, 
        string recipientId, 
        string recipientContactInfo, 
        string senderId,
        string senderContactInfo,
        bytes32 message
    ) onlyUserContract(senderId) external 
        /** Notes **
            Called by users' contracts, sender, to route message to other user, recipient
            
            * address recipientAccountAddress *: 
            eth account for this user, used for permissioning
            as every transaction sent from fueling account
            
            * string recipientId *:  unique identifier for user, used to lookup contract address 
            
            * string recipientContactInfo *: contact info for this user, email, phone # 
            
            * string senderId *: unique id for who is sending message, used for permissioning to
            confirm real user and that their contract matches.  Cannot lookup msg.sender in the
            mapping so require the contracts id to do the lookup. 
            if(msg.sender != userIdToAddress[senderId]) throw;
            
            * string senderContactInfo *: utilized to notify recipient where the message is from
            eliminating the possibly for harmful anonymous messaging

            * bytes32 message *: encrypted message to send
        **/
    {
        // if the recipient does not exist create a temp user
        if(!userExists(recipientId)) {
            createUser({
                userAccountAddress: recipientAccountAddress, 
                userId: recipientId, 
                contactInfo: recipientContactInfo, 
                persisted: false
            });
        }
        
        // retrieve the address of the recipient's contract
        address recipientAddress = userIdToAddress[recipientId];
        
        // generate a unique id for this message
        bytes32 messageId = sha3(recipientId, senderId, block.timestamp);
        
        // create new message contract!
        // pass owner so when killed funds routed to fueling eth account
        var secretMessageAddress = new SecretMessage({
            _id: messageId,
            _owner: owner,
            _sender: msg.sender,
            _recipient: recipientAddress, 
            _message: message
        });

        // update the recipient user contract, they have a new message
        SecretMessageUser(recipientAddress).newMessageReceived(
            secretMessageAddress, senderContactInfo
        );
        
        messageSentEvent(messageId);
    }
    
    // when a temp user used, clean up after message read
    function removeUser(string id) external onlyUserContract(id){
        // kill and pass in owner account address to allocate funds
        SecretMessageUser(msg.sender).kill(owner);
        
        // clean up user in mapping, reset
        userIdToAddress[id] = address(0x0);
        
        userRemovedEvent(id);
    }
    
    function kill() 
    onlyOwner { selfdestruct(owner); }
    
    // fall back function to recover any ether sent
    function () {}
    
    
    /* MODIFIERS */
    function userExists(string userId) private returns(bool){
        // within map check that the id exists as a valid address
        if(userIdToAddress[userId] == address(0x0)){
            return false;
        }
        else {
            return true;
        }
    }

    // confirm valid contract calling method
    modifier onlyUserContract(string userId) {
        if(msg.sender != userIdToAddress[userId]) throw;
        _;
    }
    
    // only the correct eth account for the specified userId
    modifier onlyUserContractOwner(address userAccountAddress, string userId){
        address contractAddress = userIdToAddress[userId];
        
        if(userAccountAddress != SecretMessageUser(contractAddress).getOwner()) throw;
        _;
    }
    
    modifier onlyOwner {
        if(msg.sender != owner) throw;
        _;
    }
}


/*******
* USER *
*******/
contract SecretMessageUser {
    /** Notes 
        User eth account address to be passed in!
        all transactions sent as fueling account so others do not need to remain funded!!
    **/

    /* STATE VARS */
    // external ether account for each user, NOT a contract
    // used to auth transactions and add permissions 
    // this account must be unlocked first then addr passed in
    address private owner;
    
    // refernece back to repo
    address private repoAddress;
    
    // used to pass to repo in order to confirm this is valid user
    string private id;
    
    // used for notifications
    string private contactInfo;
    
    // used to track current anout of messages and array indexes effeciently
    // no deleting of array items. aids to optimize gas usage
    uint8 private numberOfMessages = 0;  
    
    // a list of secret messages you have received and not viewed yet
    // capped at 5 for initial testing purposes
    address[5] private newMessages;
        
    // non-persisted users created when a message is being sent to a user 
    // that has not been created yet cleaned up and killed once message read
    bool private persisted;
    
    
    /* EVENTS */
    event newMessageReceivedEvent(string senderContactInfo);
    
    
    /* CONSTRUCTOR */
    function SecretMessageUser(
        address _owner, 
        string _id, 
        string _contactInfo, 
        bool _persisted
    )
        /** Notes **
            Invoked from repo so msg.sender is repo contract address
            
            * address _owner *: eth account of the user who is associated to this contract
            This address provides permissioning for method access.  Note all transactions
            sent as fueling account so require this as extra param, cant use msg.sender
            
            * string _id *: unique user id used in repo for lookup of contract
            
            * string _contactInfo *:  some contact info for this user 
            
            * bool _persisted *: whether or not this user was created for temporary purposes.
            In the instance where a user wishes to send a message to a user that does not
            exist within the repo.  A temp user is then created enabling the recipient to
            read the message but the contract is killed immediately afterwards.  persisted is 
            used to check if the contract should be killed following a read.
            
            * address repoAddress *:  address of the repo contract to relay communications
            repo holds ref to all users so new messages routed through repo
        **/
    {
        owner = _owner;
        id = _id;
        contactInfo = _contactInfo;
        persisted = _persisted;
        
        // reference back to repo
        repoAddress = msg.sender;
    }
    
    
    /* METHODS */
    // returns the owner address, creating custom getter in oder to permission
    // instead of making attribute public
    function getOwner() onlyRepo external returns(address){
        return owner;
    }
    
    // TODO: consider killing all outstanding messages too??
    function kill(address _owner) onlyRepo external { selfdestruct(_owner); }
    
    function notificationMessageRead(bytes32 messageId) external{
        // want all major events to be caught by repo, route back
        // pass this user's id as they were the sender and need external notification
        SecretMessageRepo(repoAddress).notificationMessageRead(contactInfo, messageId);
    }
    
    function newMessageReceived(address messageAddress, string senderContactInfo) onlyRepo external {
        // only allowed 5 existing messages at this time
        // must read a message before can receive another
        if(numberOfMessages == 5) throw;
        
        // push new message contract into array to be read
        // indexed at current quantity of messages
        // NOTE: length of newMessages with ALWAYS be 5, don't use length
        newMessages[numberOfMessages] = messageAddress;
        numberOfMessages++;    
        
        newMessageReceivedEvent(senderContactInfo);
    }
    
    
    function readMessage(address accessorAddress) onlyOwner(accessorAddress)
    external returns(string)
        /** Notes **
            messages is a LIFO queue, may only read the oldest message

            * address accessorAddress *: the eth account address for this user, used to
            ensure the correct address is calling method.  Required to pass in because
            msg.sender for every transaction is 1 fueling account to not require float
            management for every user!
        **/
    {
        // no messages to read!
        if(numberOfMessages == 0) throw;
        
        // pop the oldest message from the array
        var message = SecretMessage(newMessages[0]);
        
        // read the message data out of the contract
        var bytesMessage = message.read();
        
        // notify the sender this event has occured
        message.notifySender();
        
        // delete the contract so message cannot be read again
        message.kill();
        
        // if this is a temp contract and there are no more messages to read
        // than tell repo to remove me
        if(!persisted && numberOfMessages == 1){
            SecretMessageRepo(repoAddress).removeUser(id);
        }
        
        // shift all messages in array left as 0 is now gone
        shiftMessagesArrayLeft();
        
        // convert bytes to human readable string
        return bytes32ToString(bytesMessage);
    }
    
    
    function sendMessage(
        address recipientAccountAddress, 
        string recipientId, 
        string recipientContactInfo, 
        address senderAccountAddress,
        bytes32 message
    ) onlyOwner(senderAccountAddress) external 
        /** Notes **
            Called by users eth accounts, sender, to route message to other user, recipient
            Note that non-persisted users may NOT send messages!
            
            * address recipientAccountAddress *: 
            eth account for this user, used for permissioning
            as every transaction sent from fueling account
            
            * string recipientId *:  unique identifier for user, used to lookup contract address 
            
            * string recipientContactInfo *: contact info for this user, email, phone # 
            
            * string senderAccountAddress *: this user's eth account address, used for permissioning
            as msg.sender is always the fueling account cannot user msg.sender for ownership

            * bytes32 message *: encrypted message to send
        **/
    {
        // temporary users only exist for the duration of reading 1 message
        if(persisted){
            // tell repo to send this message
            SecretMessageRepo(repoAddress).sendMessage({
                recipientAccountAddress: recipientAccountAddress, 
                recipientId: recipientId,
                recipientContactInfo: recipientContactInfo, 
                senderId: id, // utilized for security to ensure valid user
                // required so recipient knows where the message is from
                // eliminate potential trolling through anonymous messages
                senderContactInfo: contactInfo, 
                message: message
            });
        }
    }
    
    // fall back function to recover any ether sent
    function () {}
    

    /* PRIVATE HELPERS */
    // Magic to convert bytes32 into a string
    function bytes32ToString(bytes32 x) private returns (string) {
        bytes memory bytesString = new bytes(32);
        
        uint charCount = 0;
        
        for (uint j = 0; j < 32; j++) {
            byte char = byte(bytes32(uint(x) * 2 ** (8 * j)));
            if (char != 0) {
                bytesString[charCount] = char;
                charCount++;
            }
        }
        
        bytes memory bytesStringTrimmed = new bytes(charCount);
        
        for (j = 0; j < charCount; j++) {
            bytesStringTrimmed[j] = bytesString[j];
        }
        
        return string(bytesStringTrimmed);
    }
    
    // Once a message is read it is simply overwritten
    // The array size remains constant and contents shifted left 1 index
    // Number of messages int then decremented to track array contents
    function shiftMessagesArrayLeft() private {
        // confirm messages exist before shifting, should be caught prior though
        if (numberOfMessages != 0){
            for(var i=0; i<numberOfMessages - 1; i++){
                newMessages[i] = newMessages[i + 1];
            }    
        
            numberOfMessages--;
        }
    }
    
    
    /* MODIFIERS */
    // Every transaction is sent as fueling account and therefore require 
    // address to be passed in. msg.sender always fueling account
    modifier onlyOwner(address accessorAddress) {
        if (accessorAddress != owner) throw;
        _;
    }
    
    modifier onlyRepo {
        if (msg.sender != repoAddress) throw;
        _;
    }
}


/*****************
* SECRET MESSAGE *
******************/
// Secret message contains the encrypted data and the recipient
// Contract may be accessed once than is killer
// owner is the recipient address
contract SecretMessage {
    bytes32 id; // unique id to track message, creation / read
    address private owner; // eth external account
    bytes32 private message;  // bytes so it can be returned to user contract on read
    address private senderAddress;  // user contract
    address private recipientAddress;  // user contract

    
    /* CONSTRUCTOR */
    function SecretMessage(
        bytes32 _id, 
        address _owner, 
        address _sender, 
        address _recipient, 
        bytes32 _message
    )
        /** Notes **
            Invoked from repo so msg.sender is contract address
            
            * id *: unique id for this message in order to track creation / read
            
            * address _owner *: the eth account that owns the repo, used to route funds
            in case this contract is killed
            
            * address _sender *: address of the sender's user contract in order to notify
            when this message has been read
            
            * address _recipient *: address of the recipient user's contract to notify user
            and push new message into their contract to be read
            
            * bytes32 _message *: encrypted message as byte string
        **/
    {
        // owner is the repo contract! important selfdestruct funds are routed here 
        owner = _owner;
        id = _id;
        recipientAddress = _recipient;  // important as this is the ONLY person who can view
        senderAddress = _sender;  // used to send notification to sender
        message = _message;
    }
    
    
    /* METHODS */
    function notifySender() onlyRecipient external {
        // notify sender that message has been read
        SecretMessageUser(senderAddress).notificationMessageRead(id);
    }
    
    function read() onlyRecipient external returns(bytes32){
        return message;
    }
    
    function kill() onlyRecipient external
    { selfdestruct(owner); }
    
    // fall back function to recover any ether sent
    function () {}

    
    /* MODIFIERS */
    modifier onlyRecipient {
        if (msg.sender != recipientAddress) throw;
        _;
    }
}
























