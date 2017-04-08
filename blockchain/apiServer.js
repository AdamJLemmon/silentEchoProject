var zerorpc = require("zerorpc"); // rpc to serve api
var YAML = require('yamljs');
var Web3 = require('web3'); // ethereum interface
var mailer = require('nodemailer'); // module to send notification emails
var web3Utils = require('../utils/web3');

var constants = YAML.load('../constants.yml'); // static strings

// connect to local geth node
var web3 = new Web3(
	new Web3.providers.HttpProvider("http://localhost:8545")
);


// ***************
// * EXPOSED API *
// ***************
/* TODOS: 
	- encryption: define where; party contact info, data hash, etc.
	- compute required gas for transactions
	- Refactor: 
		-- addParty and addProduct redundant, continue to refactor party/product to be generic
		-- createlisteners helpers, consider making generic
	- update getData to define queries outside of just returning the latest item
*/

// Note _ prefix denotes private function to be isolated in future
// Object organzied as follows: Public then private attributes, public then private methods
// Alphabetical within sections
var server = new zerorpc.Server({
	// local object to store runtime reference to contract instances
	_contracts: {
		partyContracts: {}, // map party id to contract
		registryContract: {}, // single instance of registry contract
		productContracts: {}, // map product id to contract
	},

	// ** Note parameter 'reply' is the channel for rpc response **

	addData: function(label, data, timestamp, reply){
		/*
			Push new data into product contract
			- label: product label
			- data: hash, likely to be encrypted, of new  data
			- timestamp:  microsecond timestamp when data acquired
		*/
		debugLogOutput('Adding new data: ' + label + ', ' + data);

		var productContracts = this._contracts[constants.PRODUCT_CONTRACTS];
		var response;

		// init account to send the transaction
		var owner = this._setupFuelingAccountForTransaction();

		// check to see if we already have a handler on this contract
		// If not, error out, product needs to be added first!
		if (!(label in productContracts)){
			response = 'Error: Product Label: ' + label + ' not recognized!';
			errorLogOutput(response);
			// TODO: consider if we want to auto-create this product if it doesnt already exist
			// this._initializeProduct(label);
		}

		else {

			// contract exists, grab contract instance from local object and addData direct
			var contract = productContracts[label];

			// send transaction to push data into contract storage
			response = contract.addData.sendTransaction(
				data, timestamp, {
					gas: 1000000,
					from: owner
				}
			);	
		}

		reply(null, response);
	},

	addParty: function(id, contactInfo, reply){
		/* 
			Attempt to add a party to the registry, will error out if it already exists
			- id: unique identifier for this party
			- contactInfo: email of party now, used for notifications
		*/
		debugLogOutput('Adding party: ' + id);

		var registry = this._contracts[constants.REGISTRY_CONTRACT];
		var response;

		// init account to send the transaction
		var ownerAddr = this._setupFuelingAccountForTransaction();

		// if the registry contract does not exist cannot add!
		// registry is an object with constructor Contract
		if(Object.keys(registry).length !== 0){
			// Invoke add product method of the registry contract
			response = registry.addParty.sendTransaction(
				id, contactInfo, 
				{
					gas: 1000000, // TODO compute gas
					from: ownerAddr
				}
			);	
		}
		else{
			response = 'Error registry does not exist!  Did you remember to deploy the contract? Or try initializing server.';
			errorLogOutput(response);
		}

		reply(null, response);
	},

	addPartyAssociationToProduct: function(partyId, productId, reply){
		/*
			Add the party's id to the product's list of parties
			Update this product's list of parties
			- partyId: id of party being added
			- productId: id of product to add party
		*/
		debugLogOutput('Adding party: ' + partyId + ' assoc to product: ' + productId);
		
		var owner = this._setupFuelingAccountForTransaction();
		var productContracts = this._contracts[constants.PRODUCT_CONTRACTS]; 
		var response;

		if(productId in productContracts){
			// if this id exists in local object then add the party's id
			var productContract = productContracts[productId];	

			// send transaction from owner, permissioned
			response = productContract.addPartyAssociation.sendTransaction(
				partyId, 
				{
					gas: 1000000,
					from: owner
				}
			);
		}
		else {
			response = 'Error: Product id does not exist!'
			errorLogOutput(response);
		}
		
		reply(null, response);
	},

	addProduct: function(label, reply){
		/* 
			Attempt to add a product to the registry, will error out if it already exists
			- label: unique identifier for this product
		*/
		debugLogOutput('Adding product: ' + label);

		var registry = this._contracts[constants.REGISTRY_CONTRACT];
		var response;

		// init account to send the transaction
		var ownerAddr = this._setupFuelingAccountForTransaction();

		// if the registry contract does not exist cannot add a product!
		// registry is an object with constructor Contract
		if(Object.keys(registry).length !== 0){
			// Invoke add product method of the registry contract
			response = registry.addProduct.sendTransaction(
				label, 
				{
					gas: 1000000, // TODO compute gas
					from: ownerAddr
				}
			);	
		}
		else{
			response = 'Error registry does not exist!  Did you remember to deploy the contract? Or try initializing server.';
			errorLogOutput(response);
		}

		reply(null, response);
	},

	// Not to be included / exposed in prod
	deployContract: function (contractId, reply) {
		/* 
			Deploy a specific contract, interface and data looked up in constants 
			based on id, note utilized to deploy registry initially
			- contractId: id used to lookup contract info; interface, data
		*/
		debugLogOutput('Deploying contract: ' + contractId);

	    // Init user account, unlock account and set default
	    var ownerAddr = this._setupFuelingAccountForTransaction(
	    	web3, constants.FUELING_ACCOUNT, constants.FUELING_PASSWORD
    	);
	    
	    // retrieve data and interface
	    var contractObject = web3.eth.contract(
	    	constants.contractData[contractId]['interface']
    	)
	    
	    // estimate gas for contract
	    var gasEstimate = web3.eth.estimateGas({
	    	data: constants.contractData[contractId]['data']
	    });

	    // reference to outer scope for contract callback method within object
	    var that = this;

	    // instantiate and deploy contract
		contractObject.new(
			{
				from: ownerAddr,
				data: constants.contractData[contractId]['data'],
				gas: gasEstimate*2
			}, function (e, contract){
				that._contractDeploymentCallback(e, contract, contractId, that);
		})

	    reply(null, gasEstimate);
	},

	getData: function(label, reply){
		/*
			Currently retrieves the latest data item from a product
			- label: identifier of the product whos latest data is to be returned
		*/
		debugLogOutput('Get Data of product: ' + label);

		// currently implemented to just return the latest data point
		// TODO: update for more elaborate queries
		var response;
		var owner = this._setupFuelingAccountForTransaction();
		var productContracts = this._contracts[constants.PRODUCT_CONTRACTS];

		// if this product does exist than retireve data
		if (label in productContracts){
			var contract = productContracts[label];

			// retrieve latest from product contract
			response = contract.getData.call({from: owner});
		}

		else {
			response = 'Error: product does not exist!';
			errorLogOutput(response);
		}
			

		reply(null, response);
	},

	getProductPublishedEventList: function(label, reply){
		/*
			Fetch the list of events that have been published by a given product
			Filter the blockahin based on this product's contract
		*/
		debugLogOutput('Get publised events of product: ' + label);

		var response;
		var productContracts = this._contracts[constants.PRODUCT_CONTRACTS];

		// if this product does exist than filter by its contract address
		if (label in productContracts){
			var contract = productContracts[label];

			// create the filter for this 
			// TODO define the from block
			var filter = web3.eth.filter({
				fromBlock: 100,
				toBlock: 'latest',
				address: contract.address,
				// topics: TODO
			});

			// Get all past logs for this product based on the filter
			filter.get(function(err, logs){
				if (err){
					response = err;
				}

				else {
					// Will append the name of each event and return
					response = []

					// default logs are not useful so decode them into the initial event objects
					var decoded_logs = web3Utils.decodeFilterLogsToEventObjects(
						web3, contract.abi, logs
					);

					// return just the event name for now, TODO define this??
					for (var i = 0; i < decoded_logs.length; i++){
						response.push(decoded_logs[i].event);
					}

				    debugLogOutput(decoded_logs);
				}

				reply(null, response);
			})
		}

		else {
			response = 'Error: product does not exist!';
			errorLogOutput(response);
			reply(null, response);
		}
	},

	initialize: function(reply){
		/* 
			Init function to load all existing contracts
		*/
		debugLogOutput('Initializing Blockchain API')

		this._loadExistingContracts();
		reply(null, 'API Initialized!');
	},

	_contractDeploymentCallback: function(e, contract, contractId){
		/*
			Helper utilized when deploying a contract
			- contract: contract instance in the process of being deployed
			- contractId: the type of contract, registry for example, defines 
			the listener method to invoke
		*/
		if(!e) {
			if(!contract.address) {
			  debugLogOutput("Contract transaction sent: TransactionHash: " + contract.transactionHash + " waiting to be mined...");
			} else {
				debugLogOutput("Contract mined! Address: " + contract.address);

				// create corresponding listenered for the registry contract events
				if (contractId == constants.REGISTRY_CONTRACT){
					this._createRegistryListeners(contract);

					// save reference to the new registry contract within object
					this._contracts[constants.REGISTRY_CONTRACT] = contract;
				}
			}
		} // end contract addr if
		else {
			console.log("err: " + e)
		}
	},

	_createContractEventListener: function(contract, event){
		/* 
			Helper to bind generic listeners to contract events 
			- contract: contract instance
			- event: string event name that exists within contract
		*/
		// create generice output for event listener
		contract[event]().watch(function(error, result) {
			debugLogOutput('EVENT: ' + event);

			if (!error)
				console.log(result.args)
			else
				console.log("Err: " + error)
		})
	},


	_creatPartyListeners: function(contract){
		/* 
			Listeners that are specific to the party contracts
			- contract: contract instance
		*/
		debugLogOutput('Creating Party listeners');
		
		// standard events that generate console log event
		var standardEvents = ['errorPermissionDeniedEvent'];
		
		for (var i=0; i<standardEvents.length; i++){
			this._createContractEventListener(contract, standardEvents[i]);
		}

		// reference in order to send email within the event listiner callback
		var that = this;

		// Custom listener if there is a notification for this party
		// Send an email using contact info for now
		contract.notificationEvent().watch(function(error, result) {
			var event = result.args._event;
			var productId = result.args.productId;
			var contactInfo = result.args.contactInfo;

			debugLogOutput(
				'EVENT: Party Notification\nEvent: ' + result.args._event 
				+ '\nProduct: ' + result.args.productId
			);

			if (!error){
				// Send an email to the party re the current product and event
				that._sendEmail(contactInfo, productId, event);
			}
				
			else{
				errorLogOutput("Err: " + error)
			}
		})
	},

	_creatProductListeners: function(contract){
		/*
			Listeners specific to the product contracts	
			- contract: contract instance
		*/
		debugLogOutput('Creating Product listeners');
		
		// standard events that generate console log event
		var standardEvents = ['dataAddedEvent'];
		
		for (var i=0; i<standardEvents.length; i++){
			this._createContractEventListener(contract, standardEvents[i]);
		}

		// Custom listener for if the quantity limit is exceeded
		// May be redundant as party receives notification
		contract.quantityLimitExceededEvent().watch(function(error, result) {
			debugLogOutput(
				'EVENT: Quantity Limit Exceeded for product: ' + result.args.id 
				+ ' ' + result.args.quantityLimit + ' produced in ' 
				+ (result.args.quantityLimitTimeInterval/1000000) + ' seconds'
			);

			if (!error){}
				
			else{
				errorLogOutput("Err: " + error)
			}
		})
	},

	_createRegistryListeners: function(contract){
		/*
			Bind all of the listeners associated to registry events
			- contract: contract instance
		*/
		debugLogOutput('Creating Registry listeners');
		
		// standard events just generate console log event
		var standardEvents = ['errorPermissionDeniedEvent', 'errorProductIdExistsEvent'];
		
		for (var i=0; i<standardEvents.length; i++){
			this._createContractEventListener(contract, standardEvents[i]);
		}	

		// reference so event callbacks can access this object to update the registry
		var that = this;

		// custom logic for product added, need to update product contracts list
		contract.productAddedEvent().watch(function(error, result) {
			debugLogOutput('EVENT: New Product Added: ' + result.args.productId);

			// load this new product into local object
			if (!error){
				that._initializeItem(result.args.productId, constants.PRODUCT_CONTRACTS);
			}
				
			else{
				errorLogOutput("Err: " + error)
			}
		})

		// custom logic for party added, need to update party contracts list
		contract.partyAddedEvent().watch(function(error, result) {
			debugLogOutput('EVENT: New Party Added: ' + result.args.partyId);

			// load this new product into local object
			if (!error){
				that._initializeItem(result.args.partyId, constants.PARTY_CONTRACTS);
			}
				
			else{
				errorLogOutput("Err: " + error)
			}
		})
	},

	_initializeItem: function(itemId, itemType, reply){
		/* 
			Get the address of this item's contract from the registry
			Then load this contract into the local object
			- itemId: the party or product identifier
			- itemType: the type of contract it is, product, party, registry for example
		*/
		var owner = this._setupFuelingAccountForTransaction();
		var registry = this._contracts[constants.REGISTRY_CONTRACT];
		var contractAddress;

		// Call initialize within registry and pass this id to retrieve the address
		// get product address
		if (itemType == constants.PRODUCT_CONTRACTS){
			contractAddress = registry.initializeProduct.call(itemId, {from: owner});
		}

		// get party address
		else if (itemType == constants.PARTY_CONTRACTS){
			contractAddress = registry.initializeParty.call(itemId, {from: owner});
		}

		// Load item contract into local object
		this._loadRegistryItem(contractAddress, itemId, itemType);
	},

	_loadContract: function(itemType, address){
		/* 
			Load a contract instance
			Lookup contract data and interface based on type and then instantiate at address
			- itemType: the type of contract it is, product, party, registry for example
		*/
		debugLogOutput('Loading Contract: ' + itemType + ' at address: ' + address);
		
		var contract = null;
		var interface = constants.contractData[itemType].interface;

		// if address exists meaning it has been deployed then grab instance
		if (address){
			var contract = web3.eth.contract(interface).at(address);

			// create event listeners for the loaded contracts
			// currently party, product, registry have unique listeners
			// specific listeners and logic for both registry and product contracts
			if (itemType == constants.REGISTRY_CONTRACT)
				this._createRegistryListeners(contract);
			
			else if(itemType == constants.PRODUCT_CONTRACTS)
				this._creatProductListeners(contract);

			else if(itemType == constants.PARTY_CONTRACTS)
				this._creatPartyListeners(contract);
		}

		return contract;
	},

	_loadExistingContracts: function(){
		/* 
			Load existing registry contract and if it exists than load the associated products / parties
			Grab a reference to the registry, product and party contract that exist
		*/
		var registry = this._loadContract(
			constants.REGISTRY_CONTRACT,
			constants.contractData[constants.REGISTRY_CONTRACT].address
		);

		// if a registry exists than set local var and grab the items that exist within it
		if (registry){
			this._contracts[constants.REGISTRY_CONTRACT] = registry;
			this._loadItems(registry, constants.PRODUCT_CONTRACTS);	
			this._loadItems(registry, constants.PARTY_CONTRACTS);	
		}
	},

	_loadItems: function(registryContract, itemType){
		/* 
			Grab the existing items from the registry contract, parties, products, etc.
			Iterate over all the items returned by the registry and load for direct use locally
			Note the registry will always return an array of 10 addresses
			- registryContract: instance of the registryContract
			- itemType: the type of contract it is, product, party, registry for example
		*/
		var owner = this._setupFuelingAccountForTransaction();
		var productAddresses, partyAddresses;
		
		if (itemType == constants.PRODUCT_CONTRACTS){
			// Get all product contract addresses and load if any exist
			productAddresses = registryContract.getProductAddressList.call(
				1, { from: owner }
			);	

			// if any product contract addresses exist then load in the contracts
			if (productAddresses.length){
				this._loadItemsList(productAddresses, constants.PRODUCT_CONTRACTS);	
			}
		}

		else if (itemType == constants.PARTY_CONTRACTS){
			// Get all party contract addresses and load if any exist
			partyAddresses = registryContract.getPartyAddressList.call(
				1, { from: owner }
			);	

			// if any party contract addresses exist then load in the contracts
			if (partyAddresses.length){
				this._loadItemsList(partyAddresses, constants.PARTY_CONTRACTS);	
			}
		}
	},

	_loadItemsList: function(itemsList, itemType){
		/*
			Pass in the list of party or product addresses and this will load them
			all into the local object
			- itemList: a list of item contract adddress to be instantiated in not empty
			- itemType: the type of contract it is, product, party, registry for example
		*/
		for (var i = 0; i < itemsList.length; i++){
			// if the address is not an empty address then load the contract
			if(itemsList[i] !== constants.EMPTY_ADDRESS){
				this._loadRegistryItem(itemsList[i], null, itemType);
			}
		}
	},

	_loadRegistryItem: function(address, id, itemType){
		/* 
			Item may be either a party or product
			Load the product contract based on address
			push into local array for later reference
			- address: address of this contract
			- id: unique id for this item, used to store ref in local object
			- itemType: the type of contract it is, product, party, registry for example
		*/
		var itemContract = this._loadContract(itemType, address);
		var owner = this._setupFuelingAccountForTransaction();

		// id is passed in when the registry event is fired
		// on initial load it needs to be fetched from the contract
		if (!id){
			id = itemContract.id();
		}

		debugLogOutput('Loading Item: ' + id);

		// create new key in object for this product
		// product Id should NOT already exist
		if (!(id in this._contracts[itemType])){
			this._contracts[itemType][id] = itemContract;
		}

		else{
			errorLogOutput('Duplicate Item ID: ' + id);
		}
	},

	_sendEmail: function(emailAddress, productId, event){
		/*
			Very specific email method for now to send in case of product quantity exceeded
			TODO: move into functions and make generic to send other emails
		*/
		debugLogOutput('Sending email!!')

		const nodemailer = require('nodemailer');

		// create reusable transporter object using the default SMTP transport
		let transporter = nodemailer.createTransport({
		    service: 'gmail',
		    auth: {
		        user: 'adamjlemmon@gmail.com',
		        pass: 'twistedflip'
		    }
		});

		// setup email data with unicode symbols
		let mailOptions = {
		    from: 'Silent Echo <adamjlemmon@gmail.com>', // sender address
		    to: emailAddress, // list of receivers
		    subject: 'Project Silent Echo: Notification ✔', // Subject line
		    text: 'Product: ' + productId + ' Event: ' + event, // plain text body
		    // html: '<b>Important</b>' // html body
		};

		// send mail with defined transport object
		transporter.sendMail(mailOptions, (error, info) => {
		    if (error) {
		        return console.log(error);
		    }
		    console.log('Message %s sent: %s', info.messageId, info.response);
		});
	},

	_setupFuelingAccountForTransaction: function(){
		/*
			Helper to unlock account to send transactions
		*/
		// TODO: confirm account balance!
		web3.personal.unlockAccount(constants.FUELING_ACCOUNT, 'geth');
		return constants.FUELING_ACCOUNT;
	}
}, heartbeat=3000);


// External helpers
// quick testing helper to output clean consistent ogs
function debugLogOutput(log){
	console.log('\n--------------');
	console.log(log);
	console.log('--------------');
}

function errorLogOutput(log){
	console.log('\n*******************');
	console.log(log);
	console.log('*******************');
}


// RPC Server
var url = "tcp://0.0.0.0:4242";
server.bind(url);
console.log("Zerorpc listening on: " + url);