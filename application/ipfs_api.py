# backend object storage
# push and pull images to and from ipfs

import ipfsapi
import io


class IpfsApi:

    def __init__(self, ip, port):
        # create connection with ipfs instance
        # note ipfs daemon must be running on host machine: '$ ipfs daemon' to start
        self.api = ipfsapi.connect(ip, port)
        print('Connected to IPFS at:', ip, port)

    def put_block(self, block_data, **kwargs):
        """
        Put a block of bytes data into ipfs
        <class 'bytes'> required as input
        """
        # convert to bytes so accepted as block by ipfs then put
        byte_data = io.BytesIO(block_data)
        response = self.api.block_put(byte_data)
        return response

    def get_block(self, data_hash):
        """
        Retrieve a block of bytes looked up by the data hash
        """
        response = self.api.block_get(data_hash)
        return response

    def get_data(self, data_hash):
        """
        Download data into active directory where file name is the hash
        """
        response = self.api.get(data_hash)
        return response

if __name__ == '__main__':
    pass

