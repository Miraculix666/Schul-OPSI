import os
import sys
from opsicommon.client import OpsiClient

opsi_url = os.environ.get('OPSI_URL', 'https://opsi-server-url:4447/rpc')
opsi_username = os.environ.get('OPSI_USERNAME')
opsi_password = os.environ.get('OPSI_PASSWORD')

if not opsi_username or not opsi_password:
    print("Error: OPSI_USERNAME and OPSI_PASSWORD environment variables must be set.", file=sys.stderr)
    sys.exit(1)

# Connect to OPSI server
client = OpsiClient(opsi_url, opsi_username, opsi_password)

depot_id = 'sopsi.lafp.schul.polizei.local'
product_id = 'mint22'

try:
    # Force install product on depot, ignoring locks
    client.depot_installProduct(product_id, depot_id, force=True)
    print(f"Forced install of {product_id} on {depot_id} succeeded.")
except Exception as e:
    print("Error while forcing install:", e)
