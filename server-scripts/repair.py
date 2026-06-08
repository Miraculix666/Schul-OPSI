import os
import sys
from opsicommon.client import OpsiClient

opsi_url = os.environ.get('OPSI_URL', 'https://opsi-server-url:4447/rpc')
opsi_user = os.environ.get('OPSI_USER')
opsi_password = os.environ.get('OPSI_PASSWORD')

if not opsi_user or not opsi_password:
    print("Error: OPSI_USER and OPSI_PASSWORD environment variables must be set.")
    sys.exit(1)

# Connect to OPSI server (adjust URL and credentials as needed)
client = OpsiClient(opsi_url, opsi_user, opsi_password)

depot_id = 'sopsi.lafp.schul.polizei.local'
product_id = 'mint22'

try:
    # Force install product on depot, ignoring locks
    client.depot_installProduct(product_id, depot_id, force=True)
    print(f"Forced install of {product_id} on {depot_id} succeeded.")
except Exception as e:
    print("Error while forcing install:", e)
