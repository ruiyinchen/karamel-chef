#!/usr/bin/env python

'''
@author: Jim Dowling <jdowling@kth.se>

Install:
 requests:    easy_install requests
 Netifaces:   easy_install netifaces
 IPy:         easy_install ipy
 pyOpenSSL:   apt-get install python-openssl
 MySQLdb:     apt-get install python-mysqldb
 pexpect:     apt-get install python-pexpect
'''

import time
from threading import Lock
import os
import sys
import ConfigParser
import requests
import logging.handlers
import json
from OpenSSL import crypto
from os.path import exists, join
import logging
import subprocess


try:
    import http.client as http_client
except ImportError:
    # Python 2
    import httplib as http_client
http_client.HTTPConnection.debuglevel = 1

logging.basicConfig()
logging.getLogger().setLevel(logging.DEBUG)
requests_log = logging.getLogger("requests.packages.urllib3")
requests_log.setLevel(logging.DEBUG)
requests_log.propagate = True
retries = 5
retry_count = 0


class Util:

    def logging_level(self, level):
        return {
            'INFO': logging.INFO,
            'WARN': logging.WARN,
            'WARNING': logging.WARNING,
            'ERROR': logging.ERROR,
            'DEBUG': logging.DEBUG,
            'CRITICAL': logging.CRITICAL,
        }.get(level, logging.NOTSET)


class Register:

    def __init__(self, csr, key):
        global retry_count
        while True:
            cert = Register.register(csr, key)
            if cert is not None:
                Cert.store(cert, key)
                break
            retry_count += 1
            if retry_count == retries:
                break
            time.sleep(retry_interval)

    @staticmethod
    def register(csr, key):
        try:
            json_headers = {'User-Agent': 'Agent', 'content-type': 'application/json'}
            form_headers = {'User-Agent': 'Agent', 'content-type': 'application/x-www-form-urlencoded'}
            payload = {}
            payload['csr'] = csr
            logger.info("Registering with HopsWorks...")
            session = requests.Session()
            session.post(login_url, data={'email': server_username, 'password': server_password}, headers=form_headers, verify=False)
            resp = session.post(sign_cert_url, data=json.dumps(payload), headers=json_headers, verify=False)
            if not resp.status_code == HTTP_OK:
                raise Exception('Could not register: Status code: {0}. response msg: {1}'.format(resp.status_code, resp.content))

            jData = json.loads(resp.content)
            cert = jData['signedCert']
            intermediateCaCert = jData['intermediateCaCert']
            rootCaCert = jData['rootCaCert']

            cert_dir = os.path.dirname(os.path.abspath(__file__))
            with open(join(cert_dir, CA_FILE), "wt") as f:
                f.write(rootCaCert)
            logger.info("Writing Ca Public key to {0}.".format(CA_FILE))

            with open(join(cert_dir, INTERMEDIATE_CA_FILE), "wt") as f:
                f.write(intermediateCaCert)
            logger.info("Writing intermediate Ca Public key to {0}.".format(INTERMEDIATE_CA_FILE))

            logger.info("Registered successfully.")
            return cert
        except Exception as err:
            if retry_count + 1 < retries:
                logger.error("{0}. Number of retries left {1}. Retrying in {2} seconds...".format(err, retries - (retry_count + 1), retry_interval))
            return None

class Cert:

    @staticmethod
    def get_dir():
        return os.path.dirname(os.path.abspath(__file__))

    @staticmethod
    def exist():
        cert_dir = Cert.get_dir()
        return exists(join(cert_dir, CERT_FILE)) and exists(join(cert_dir, KEY_FILE))

    @staticmethod
    def exists_keystore():
        return exists(SERVER_KEYSTORE) and exists(SERVER_TRUSTSTORE)

    @staticmethod
    def create_key_and_csr():
        """
        Create key-pair and certificate sign request (CSR)
        """
        # create a key pair
        pkey = crypto.PKey()
        pkey.generate_key(crypto.TYPE_RSA, 2048)
        # create certificate sign request
        req = crypto.X509Req()
        req.get_subject().C  = cert_c
        req.get_subject().CN = cert_cn
        req.get_subject().ST = cert_s
        req.get_subject().L  = cert_l
        req.get_subject().O  = cert_o
        req.get_subject().OU = cert_ou
        req.get_subject().__setattr__("emailAddress", cert_email)

        req.set_pubkey(pkey)
        req.sign(pkey, 'sha256')
        csr = crypto.dump_certificate_request(crypto.FILETYPE_PEM, req)
        private_key = crypto.dump_privatekey(crypto.FILETYPE_PEM, pkey)
        return csr, private_key

    @staticmethod
    def store(cert, key):
        """
        Write certificate and private key in current directory
        """
        cert_dir = Cert.get_dir()
        with open(join(cert_dir, CERT_FILE), "wt") as f:
            f.write(cert)
        with open(join(cert_dir, KEY_FILE), "wt") as f:
            f.write(key)
        logger.info("Writing Cert/Key pair to {0} - {1}.".format(CERT_FILE, KEY_FILE))

var = "~#@#@!#@!#!@#@!#"

config_mutex = Lock()

HTTP_OK = 200

CONFIG_FILE = "/srv/hops/domains/domain1/config/ca.ini"
LOG_FILE = "/srv/hops/certs-dir/hops-site-certs/csr.log"
CERT_FILE = "/srv/hops/certs-dir/hops-site-certs/pub.pem"
CA_FILE = "/srv/hops/certs-dir/hops-site-certs/ca_pub.pem"
INTERMEDIATE_CA_FILE = "/srv/hops/certs-dir/hops-site-certs/intermediate_ca_pub.pem"
KEY_FILE = "/srv/hops/certs-dir/hops-site-certs/priv.key"
SERVER_KEYSTORE = "/srv/hops/certs-dir/hops-site-certs/keystore.jks"
SERVER_TRUSTSTORE = "/srv/hops/certs-dir/hops-site-certs/truststore.jks"

# reading config
try:
    config = ConfigParser.ConfigParser()
    config.read(CONFIG_FILE)
    hopssite_url = config.get('hops-site', 'url')
    login_url = hopssite_url + config.get('hops-site', 'path-login')
    sign_cert_url = hopssite_url + config.get('hops-site', 'path-sign-cert')
    server_username = config.get('hops-site', 'username')
    server_password = config.get('hops-site', 'password')
    retry_interval = config.getfloat('hops-site', 'retry-interval')
    retries = config.getfloat('hops-site', 'max-retries')
    logging_level = config.get('hops-site', 'logging-level').upper()
    cert_c = config.get('hops-site', 'cert_c')
    cert_cn = config.get('hops-site', 'cert_cn')
    cert_s = config.get('hops-site', 'cert_s')
    cert_l = config.get('hops-site', 'cert_l')
    cert_o = config.get('hops-site', 'cert_o')
    cert_ou = config.get('hops-site', 'cert_ou')
    cert_email = config.get('hops-site', 'cert_email')

except Exception, e:
    print "Exception while reading {0}: {1}".format(CONFIG_FILE, e)
    sys.exit(1)

# logging
try:
    os.remove(LOG_FILE + '.1')
except:
    pass
with open(LOG_FILE, 'w'):  # clear log file
    pass
logger = logging.getLogger('csr-ca-agent')
logger_formatter = logging.Formatter('%(asctime)s %(levelname)s %(message)s')
logger_file_handler = logging.handlers.RotatingFileHandler(LOG_FILE, "w", maxBytes=10000000, backupCount=1)
logger_stream_handler = logging.StreamHandler()
logger_file_handler.setFormatter(logger_formatter)
logger_stream_handler.setFormatter(logger_formatter)
logger.addHandler(logger_file_handler)

logger.addHandler(logger_stream_handler)
logger.setLevel(logging.INFO)

logger.info("Hopsworks Csr-ca Agent started.")
logger.info("Register URL: {0}".format(sign_cert_url))


if __name__ == '__main__':

    logger.setLevel(Util().logging_level(logging_level))

    if not Cert.exist():
        (csr, key) = Cert.create_key_and_csr()
        Register(csr, key)
    else:
        logger.info('Certificate files exist. Already registered. Skipping registration phase.')
