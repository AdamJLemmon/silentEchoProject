# @adamlemmon 03-31-2017
# Top level script to execute demo

import threading
import time

from application.application_server import ApplicationServer
from demo.data_acquisition import DataAcquisition


class Demo:

    def __init__(self):
        self.data_acquisition = DataAcquisition()
        self.application = ApplicationServer()

    def acquire_data_for_interval_in_seconds(self, duration):
        """
        Acquire image at random for a specified duration of time
        Randomly reads a file from demo/images folder and publishes over zmq
        :param duration: time in second to acquire data for
        :return:
        """
        # create acquisition thread
        data_acq_thread = threading.Thread(target=self.data_acquisition.start_acquisition)
        data_acq_thread.daemon = True
        data_acq_thread.start()

        # create subscriber listening thread
        sub_thread = threading.Thread(target=self.application.start_listening)
        sub_thread.daemon = True
        sub_thread.start()

        time.sleep(duration)

        self.data_acquisition.stop_acquisition()
        print('Acquisition Complete!')

    def add_product(self, label):
        """
        Add new product to registry
        :param label: unique identifier, mocking the label a classifier may give
        :return:
        """
        print('Adding product:', label)
        client = self.application.__init_blockchain_client__()
        response = client.addProduct(label)
        client.close()

        return response

    def add_party(self, party_id, contact_info):
        """
        Add new party to registry
        :param party_id: unique identifier
        :param contact_info: some way to contact this party, utilized to send notification emails for demo
        :return:
        """
        print('Adding party:', party_id)
        client = self.application.__init_blockchain_client__()
        response = client.addParty(party_id, contact_info)
        client.close()

        return response

    def add_party_assoc_to_product(self, party_id, product_id):
        """
        Add a party's id to a product as an association
        This party with receive email notifications for this product
        :param party_id: id of party
        :param product_id: id of product
        :return:
        """
        print('Adding party assoc:', party_id, product_id)
        client = self.application.__init_blockchain_client__()
        response = client.addPartyAssociationToProduct(party_id, product_id)
        client.close()

        return response

    def deploy_contract(self, contract_id):
        """
        Deploy new contract by id
        Only used to deploy registry contract initially
        :param contract_id: id of contract as found in blockchain/constants.js
        :return:
        """
        # deploy contract
        client = self.application.__init_blockchain_client__()
        response = client.deployContract(contract_id)
        client.close()

        return response

    def get_data(self, label):
        """
        Retrieve latest data point for specific product
        :param label: identifier of product to retrieve data
        :return:
        """
        self.application.get_data(label)

    def get_product_published_event_list(self, label):
        """
        Filter the blockchain for all events published for a given product
         identified by label
        """
        self.application.get_product_published_event_list(label)

    def initialize_registry(self):
        """
        Load registry contract if already deployed and associated parties / products
        :return:
        """
        client = self.application.__init_blockchain_client__()
        response = client.initialize()
        client.close()

        return response

if __name__ == '__main__':
    pass


