# Mock the output of a product classifier
# Transmit images and associated labels to application server

import cv2
import time
import yaml
import zmq

from datetime import datetime
from random import randint

from .constants import *


class DataAcquisition:

    def __init__(self):
        # settings yml loaded to dict
        self.settings = self.__load_settings__()

        # utilized to control acquisition publisher
        self.publisher_enabled = False

        # init zmo publisher to push data out to app server
        self.publisher = self.__init_data_publisher__(
            ip=self.settings[ZMQ][ZMQ_PUB_IP],
            port=self.settings[ZMQ][PORT]
        )

    def start_acquisition(self):
        """
        Begin randomly selecting demo images and publishing data
        """
        # enable data acquisition
        self.publisher_enabled = True

        # while enabled continue to publish data
        while self.publisher_enabled:
            # randomly generate an image index to transmit
            index = randint(0, len(self.settings[IMAGES]) - 1)

            selected_image = self.settings[IMAGES][index]

            # Load color image
            # Shape needed if we want to view image after storing, print('Shape:', img.shape)
            img = cv2.imread(self.settings[IMAGE_DIR] + selected_image)

            # strip the file type suffix to get label
            label = selected_image.split('.')[0]

            # send message, [label as bytes, raw image bytes]
            # timestamp down to micro seconds? int to drop the decimals
            timestamp = int(datetime.now().timestamp()*1000000)
            self.publisher.send_multipart([label.encode(), img, timestamp.to_bytes(256, 'big')])

            print('Data published:', label)

            # wait interval than grab next image to simulate production supply chain
            time.sleep(self.settings[PROD_INTERVAL])

    def stop_acquisition(self):
        """
        Disable acquisition
        """
        self.publisher_enabled = False

    @staticmethod
    def __init_data_publisher__(ip, port):
        """
        create and return zmq publisher
        """
        context = zmq.Context()
        socket = context.socket(zmq.PUB)
        socket.bind(ip + port)

        return socket

    @staticmethod
    def __load_settings__():
        """
        Load and return settings as dict
        """
        settings_file = open('demo/settings.yml')
        settings = yaml.safe_load(settings_file)
        settings_file.close()

        return settings

    @staticmethod
    def show_image_data(data):
        """
        Show image data in a window
        """
        cv2.imshow('data', data)
        cv2.waitKey(0)
        cv2.destroyAllWindows()

if __name__ == '__main__':
    pass


