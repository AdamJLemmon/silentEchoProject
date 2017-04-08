/*

Module to provide all encrpytion functionality

*/

// encryption & decryption library
const CryptoJS = require("crypto-js");


module.exports = {
	// currently used to create encryption keys and passwords
	cryptoKeyGenAlg: require("crypto-js/sha256"),
 	passwordGenAlg: require("crypto-js/sha256"),

	generatePasswordAndEncryptionKey: function(userName){
		var cryptoKey = this.cryptoKeyGenAlg(userName);
		var userPassword = this.passwordGenAlg(cryptoKey);

		return {
			'key': cryptoKey.toString(),
			'password': userPassword.toString()
		};
	},

	encryptString: function(userName, dataString){
		var key = this.generatePasswordAndEncryptionKey(userName)['key'];
		var encryptedString = CryptoJS.AES.encrypt(dataString, key);

		return encryptedString
	},

	decryptString: function(userName, dataString){
		var key = this.generatePasswordAndEncryptionKey(userName)['key'];

		// generate key and decrypt the string
		var decryptedBytes = CryptoJS.AES.decrypt(dataString, key);

		// convert to string and return
		var decryptedString = decryptedBytes.toString(CryptoJS.enc.Utf8);

		return decryptedString
	},
}