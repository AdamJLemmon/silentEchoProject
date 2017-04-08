/*
	Helper functions for the web3 api
*/
var SolidityEvent = require("web3/lib/web3/event.js");


module.exports = {
	decodeFilterLogsToEventObjects: function(web3, contractAbi, logs){
		/*
			Convert the default filter logs into useful event objects
			Lookup the event object definition with ABI and instantiate with data of the log
		*/
		
		// Get the event definitions from the ABI which will be used to decode the filter
		// returned events
		var decoders = contractAbi.filter(function (json) {
	        return json.type === 'event';
	    }).map(function(json) {
	        // note first and third params required only by enocde and execute;
	        // so don't call those!
	        return new SolidityEvent(null, json, null);
	    });

	    // return the decoded array of all logs
	    return logs.map(function(log) {
	    		// find the decoder that matches this logs 'topic' and decode
		        return decoders.find(function(decoder) {
		            return (decoder.signature() == log.topics[0].replace("0x",""));
	        }).decode(log);
	    })
	}
}

