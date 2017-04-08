# Central server for application
# Interface with data acquisition, storage and blockchain
# Retrieves data from data acquisition stores in storage and
# communicates to blockchain api over rpc
import cv2
import numpy as np
import yaml
import zerorpc
import zmq

from application.ipfs_api import IpfsApi
from application.constants import *


class ApplicationServer:

    def __init__(self):
        # settings yml loaded to dict
        self.settings = self.__load_settings__()

        # init the subscriber to receive data
        self.subscriber = self.__init_data_subscriber__(
            ip=self.settings[ZMQ][ZMQ_SUB_IP],
            port=self.settings[ZMQ][PORT]
        )

        # attr to control the subscriber
        self.subscriber_enabled = False

        # init IPFS connection for raw data block storage
        self.storage = IpfsApi(
            ip=self.settings[IPFS][IP],
            port=self.settings[IPFS][PORT]
        )

    def get_data(self, label):
        """
        Get the raw data back from ipfs
        Retrieve lookup hash from contract and then fetch
        Note need to shape the bytes correctly to visualize and therefore need to know the
        shape of the image when being saved... to be improved!
        """
        # TODO: define query to get data??
        client = self.__init_blockchain_client__()
        data_hash = client.getData(label)
        client.close()
        print('Data Retrieved:', data_hash)

        # raw bytes block returned
        block_data = self.storage.get_block(data_hash)

        # shaped into original image in order to be visualized
        shaped_image = np.fromstring(block_data, np.uint8).reshape(SHAPE[label])

        # TODO: remove below, here to test correct data returned
        cv2.imwrite(
            'demo/images/latest_{}{}'.format(label, SUFFIX[label]),
            shaped_image
        )

        return data_hash

    def get_product_published_event_list(self, label):
        """
        Filter the blockchain for all events published for a given product
         identified by label
        """
        client = self.__init_blockchain_client__()
        transaction_list = client.getProductPublishedEventList(label)
        client.close()

        print(transaction_list)

        return transaction_list

    def new_data_received(self, label, data, timestamp):
        """
        New data has been received from the data acquisition publisher
        Contains the label the data has been given by upstream classification module
        and the raw data itself
        Store the data in IPFS and push the hash to contract
        """
        # push raw data to storage and pull out the return data hash
        put_response = self.storage.put_block(data)
        data_hash = put_response[IPFS_HASH]

        # init connection and addData to blockchain client
        client = self.__init_blockchain_client__()
        response = client.addData(label, data_hash, timestamp)
        client.close()

        print('Response:', response)

    def start_listening(self):
        """
        Enable the subscriber and start listening for messages from publisher
        """
        self.subscriber_enabled = True

        # init to receive an array of data, bytes representations
        while self.subscriber_enabled:
            [label, data, timestamp] = self.subscriber.recv_multipart()

            # convert timestamp back to int
            timestamp = int.from_bytes(timestamp, 'big')

            if label:
                # data received, store and update contract, decode label to string
                self.new_data_received(label.decode(), data, timestamp)

    def stop_listening(self):
        """
        Disable the subscriber, stop it from listening
        """
        self.subscriber_enabled = False

    # TODO: figure out why client connection is dying
    def __init_blockchain_client__(self):
        """
        Init the connection to the blockchain rpc
        """
        client = zerorpc.Client(heartbeat=3000)
        client.connect(
            self.settings[ZRPC][IP] +
            self.settings[ZRPC][PORT]
        )
        return client

    @staticmethod
    def __init_data_subscriber__(ip, port):
        """
        Create a subscriber to the data acquisition publisher
        """
        context = zmq.Context()
        socket = context.socket(zmq.SUB)
        socket.connect(ip + port)

        # subscribe to all topics for demo purposes
        socket.setsockopt_string(zmq.SUBSCRIBE, '')

        return socket

    @staticmethod
    def __load_settings__():
        """
        Load and return settings yml as dict
        """
        settings_file = open('settings.yml')
        settings = yaml.safe_load(settings_file)
        settings_file.close()

        return settings

if __name__ == '__main__':
    pass
