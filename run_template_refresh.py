from database import SessionLocal
from sync_service import SyncService

db = SessionLocal()

try:
    service = SyncService(db)

    # This reruns the full active eBay sync.
    # With your new edit, existing listings now also refresh templates.
    result = service.sync_ebay_listings()

    print(result)

finally:
    db.close()
