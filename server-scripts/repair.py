from opsicommon.client import OpsiClient

# Connect to OPSI server (adjust URL and credentials as needed)
client = OpsiClient('https://opsi-server-url:4447/rpc', 'admin', 'password')

depot_id = 'sopsi.lafp.schul.polizei.local'
product_id = 'mint22'

try:
    # Force install product on depot, ignoring locks
    client.depot_installProduct(product_id, depot_id, force=True)
    print(f"Forced install of {product_id} on {depot_id} succeeded.")
except Exception as e:
    print("Error while forcing install:", e)
